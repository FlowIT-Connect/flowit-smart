// Adaptateur Home Assistant (API WebSocket officielle) :
// https://developers.home-assistant.io/docs/api/websocket/
//
// La passerelle tourne sur le réseau local : Home Assistant n'a pas besoin d'être
// exposé à Internet (§6.2). Le jeton longue durée reste dans le .env de la passerelle.

import { EventEmitter } from 'node:events';

import { log } from '../log.js';
import { buildInventory, deviceSnapshot, serviceCall, stateMatches } from './ha_mapping.js';

export class HomeAssistantAdapter extends EventEmitter {
  /**
   * @param {{url:string, token:string, filter?:RegExp|null, wsFactory?:(url:string)=>WebSocket}} opts
   */
  constructor({ url, token, filter = null, wsFactory = (u) => new WebSocket(u) }) {
    super();
    this.wsUrl = `${url.replace(/^http/, 'ws')}/api/websocket`;
    this.token = token;
    this.filter = filter;
    this.wsFactory = wsFactory;
    this.ws = null;
    this.nextId = 1;
    this.pending = new Map();
    this.states = new Map();
    this.inventory = new Map();
    this.byEntity = new Map(); // entity_id -> externalId
    this.waiters = new Set();
    this.stopped = false;
    this.backoffMs = 1000;
    this.reinventoryTimer = null;
  }

  async start() {
    await this.#connect();
  }

  stop() {
    this.stopped = true;
    clearTimeout(this.reinventoryTimer);
    this.ws?.close();
  }

  devices() {
    return [...this.inventory.values()];
  }

  snapshot(externalId) {
    const d = this.inventory.get(externalId);
    return d ? deviceSnapshot(d, this.states) : { state: {}, availability: 'unavailable' };
  }

  async #connect() {
    const ws = this.wsFactory(this.wsUrl);
    this.ws = ws;
    await new Promise((resolve, reject) => {
      ws.onmessage = (ev) => {
        const msg = JSON.parse(typeof ev.data === 'string' ? ev.data : ev.data.toString());
        if (msg.type === 'auth_required') {
          ws.send(JSON.stringify({ type: 'auth', access_token: this.token }));
        } else if (msg.type === 'auth_ok') {
          ws.onmessage = (e) => this.#onMessage(JSON.parse(typeof e.data === 'string' ? e.data : e.data.toString()));
          resolve();
        } else if (msg.type === 'auth_invalid') {
          reject(new Error('Jeton Home Assistant refusé'));
        }
      };
      ws.onerror = () => reject(new Error(`Connexion impossible à Home Assistant (${this.wsUrl})`));
      ws.onclose = () => reject(new Error('Connexion Home Assistant fermée pendant l\'authentification'));
    });
    ws.onclose = () => this.#onClose();
    ws.onerror = () => {};
    this.backoffMs = 1000;
    log.info('home_assistant.connected', { url: this.wsUrl });

    await this.#refreshInventory();
    await this.#send({ type: 'subscribe_events', event_type: 'state_changed' });
    for (const event_type of ['entity_registry_updated', 'device_registry_updated']) {
      await this.#send({ type: 'subscribe_events', event_type }).catch(() => {});
    }
    this.emit('connection', true);
  }

  #onClose() {
    for (const { reject } of this.pending.values()) reject(new Error('Connexion Home Assistant perdue'));
    this.pending.clear();
    this.emit('connection', false);
    if (this.stopped) return;
    const delay = this.backoffMs;
    this.backoffMs = Math.min(this.backoffMs * 2, 60_000);
    log.warn('home_assistant.disconnected', { retry_in_ms: delay });
    setTimeout(() => this.#connect().catch((e) => {
      log.error('home_assistant.reconnect_failed', { error: e.message });
      this.#onClose();
    }), delay);
  }

  #send(payload) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.ws.send(JSON.stringify({ id, ...payload }));
    });
  }

  #onMessage(msg) {
    if (msg.type === 'result') {
      const p = this.pending.get(msg.id);
      if (!p) return;
      this.pending.delete(msg.id);
      if (msg.success) p.resolve(msg.result);
      else p.reject(new Error(msg.error?.message ?? 'Erreur Home Assistant'));
      return;
    }
    if (msg.type !== 'event') return;
    const ev = msg.event;
    if (ev.event_type === 'state_changed') {
      const { entity_id, new_state } = ev.data;
      if (new_state) this.states.set(entity_id, new_state);
      else this.states.delete(entity_id);
      for (const w of this.waiters) w(entity_id, new_state);
      const externalId = this.byEntity.get(entity_id);
      if (externalId) this.emit('device', externalId, this.snapshot(externalId));
    } else if (ev.event_type.endsWith('_registry_updated')) {
      clearTimeout(this.reinventoryTimer);
      this.reinventoryTimer = setTimeout(() => this.#refreshInventory().catch((e) => log.error('home_assistant.inventory_failed', { error: e.message })), 2000);
    }
  }

  async #refreshInventory() {
    const [states, entities, devices] = await Promise.all([
      this.#send({ type: 'get_states' }),
      this.#send({ type: 'config/entity_registry/list' }).catch(() => []),
      this.#send({ type: 'config/device_registry/list' }).catch(() => []),
    ]);
    this.states = new Map(states.map((s) => [s.entity_id, s]));
    const list = buildInventory(states, entities, devices, this.filter);
    this.inventory = new Map(list.map((d) => [d.externalId, d]));
    this.byEntity = new Map();
    for (const d of list) for (const e of Object.values(d.capMap)) this.byEntity.set(e.entityId, d.externalId);
    log.info('home_assistant.inventory', { devices: list.length, entities: states.length });
    this.emit('inventory');
  }

  /**
   * Exécute une commande et attend un retour d'état fiable.
   * @returns {Promise<{status:'confirmed'|'failed'|'timeout', error?:string}>}
   */
  async execute(externalId, key, value, timeoutMs) {
    const device = this.inventory.get(externalId);
    const entry = device?.capMap[key];
    if (!entry) return { status: 'failed', error: 'Capacité absente côté Home Assistant' };
    const call = serviceCall(entry, value);
    if (!call) return { status: 'failed', error: 'Commande non prise en charge par la passerelle' };
    const current = this.states.get(entry.entityId);
    if (!current || current.state === 'unavailable') return { status: 'failed', error: 'Appareil indisponible' };

    let waiter;
    const confirmed = new Promise((resolve) => {
      waiter = (entityId, newState) => {
        if (entityId === entry.entityId && stateMatches(entry, newState, value)) resolve(true);
      };
      this.waiters.add(waiter);
    });
    let timer;
    const timeout = new Promise((resolve) => {
      timer = setTimeout(() => resolve(false), timeoutMs);
    });
    try {
      await this.#send({ type: 'call_service', domain: call.domain, service: call.service, service_data: call.data, target: call.target });
      if (stateMatches(entry, this.states.get(entry.entityId), value)) return { status: 'confirmed' };
      const ok = await Promise.race([confirmed, timeout]);
      return ok ? { status: 'confirmed' } : { status: 'timeout', error: 'Aucun retour d\'état de l\'appareil dans le délai' };
    } catch (e) {
      return { status: 'failed', error: e.message };
    } finally {
      clearTimeout(timer);
      this.waiters.delete(waiter);
    }
  }
}
