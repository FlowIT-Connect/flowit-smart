// Adaptateur Home Assistant (API WebSocket officielle) :
// https://developers.home-assistant.io/docs/api/websocket/
//
// La passerelle tourne sur le réseau local : Home Assistant n'a pas besoin d'être
// exposé à Internet (§6.2). Le jeton longue durée reste dans le .env de la passerelle.

import { EventEmitter } from 'node:events';

import { log } from '../log.js';
import { addBroadlink, codesFile, IrProfileStore, irServiceCall, PROFILE_ACTIONS, profileTestCodes, readLearnedCommands } from './broadlink.js';
import { buildInventory, deviceSnapshot, serviceCall, stateMatches } from './ha_mapping.js';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export class HomeAssistantAdapter extends EventEmitter {
  /**
   * @param {{url?:string, wsUrl?:string, token:string, filter?:RegExp|null, platforms?:Set<string>|null,
   *   configDir?:string|null, wsFactory?:(url:string)=>WebSocket, fetchImpl?:typeof fetch, readImpl?:Function,
   *   learnPollMs?:number, learnWaitMs?:number}} opts
   *   platforms : intégrations HA retenues (ex. broadlink) ; configDir : dossier de configuration de HA,
   *   lu pour connaître les touches apprises des télécommandes Broadlink ; irStore : télécommandes de
   *   clim choisies dans la bibliothèque (IrProfileStore, gardé dans /data/broadlink sur la box).
   */
  constructor({
    url, wsUrl, token, filter = null, platforms = null, configDir = null,
    wsFactory = (u) => new WebSocket(u), fetchImpl = (...a) => fetch(...a), readImpl = undefined,
    learnPollMs = 1000, learnWaitMs = 25_000, codesPollMs = 60_000, irStore = new IrProfileStore(),
  }) {
    super();
    this.platforms = platforms;
    this.configDir = configDir;
    this.readImpl = readImpl;
    this.learnPollMs = learnPollMs;
    this.learnWaitMs = learnWaitMs;
    this.codesPollMs = codesPollMs;
    this.remotes = []; // télécommandes Broadlink : [{entityId, uniqueId, deviceId, name, model}]
    this.learned = new Map(); // uniqueId -> {appareil: [touches]}
    this.assumed = new Map(); // état supposé des clims infrarouges
    this.irStore = irStore;
    this.profiles = new Map(); // uniqueId -> {appareil: télécommande de clim de la bibliothèque}
    this.codesTimer = null;
    this.registries = { entities: [], devices: [] };
    // wsUrl direct : utilisé par le module complémentaire Home Assistant (ws://supervisor/core/websocket).
    this.wsUrl = wsUrl ?? `${url.replace(/^http/, 'ws')}/api/websocket`;
    // API REST (images de caméras) : http://ha:8123 ou http://supervisor/core dans le module.
    this.httpUrl = url ?? this.wsUrl.replace(/^ws/, 'http').replace(/\/(api\/)?websocket$/, '');
    this.fetchImpl = fetchImpl;
    this.token = token;
    this.filter = filter;
    this.wsFactory = wsFactory;
    this.ws = null;
    this.nextId = 1;
    this.pending = new Map();
    this.states = new Map();
    this.inventory = new Map();
    this.byEntity = new Map(); // entity_id -> Set(externalId)
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
    clearInterval(this.codesTimer);
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
      for (const externalId of this.byEntity.get(entity_id) ?? []) this.emit('device', externalId, this.snapshot(externalId));
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
    this.registries = { entities, devices };
    const byId = new Map(devices.map((d) => [d.id, d]));
    this.remotes = entities
      .filter((e) => e.platform === 'broadlink' && e.entity_id.startsWith('remote.') && !e.disabled_by)
      .filter((e) => (!this.platforms || this.platforms.has('broadlink')) && (!this.filter || this.filter.test(e.entity_id)))
      .map((e) => {
        const dev = byId.get(e.device_id);
        return { entityId: e.entity_id, uniqueId: e.unique_id, deviceId: e.device_id ?? null, name: dev?.name_by_user ?? dev?.name ?? null, model: dev?.model ?? null };
      });
    await this.#readCodes();
    await this.#loadProfiles();
    this.#rebuild();
    if (this.remotes.length && !this.codesTimer && this.configDir) {
      // Touches apprises directement dans Home Assistant : vues dans la minute.
      this.codesTimer = setInterval(() => this.#readCodes().then((changed) => changed && this.#rebuild()).catch(() => {}), this.codesPollMs);
    }
  }

  #rebuild() {
    const states = [...this.states.values()];
    const list = buildInventory(states, this.registries.entities, this.registries.devices, this.filter, this.platforms);
    if (this.remotes.length) addBroadlink(list, this.remotes, this.learned, this.assumed, this.profiles);
    this.inventory = new Map(list.map((d) => [d.externalId, d]));
    this.byEntity = new Map();
    for (const d of list) {
      for (const e of Object.values(d.capMap)) {
        if (!this.byEntity.has(e.entityId)) this.byEntity.set(e.entityId, new Set());
        this.byEntity.get(e.entityId).add(d.externalId);
      }
    }
    log.info('home_assistant.inventory', { devices: list.length, entities: states.length, ...(this.remotes.length ? { broadlink: this.remotes.length } : {}) });
    this.emit('inventory');
  }

  /** Relit les touches apprises des télécommandes Broadlink ; true si elles ont changé. */
  async #readCodes() {
    if (!this.configDir) return false;
    let changed = false;
    for (const r of this.remotes) {
      if (!r.uniqueId) continue;
      try {
        const codes = await readLearnedCommands(codesFile(this.configDir, r.uniqueId), this.readImpl);
        if (JSON.stringify(codes) !== JSON.stringify(this.learned.get(r.uniqueId) ?? null)) {
          this.learned.set(r.uniqueId, codes);
          changed = true;
        }
      } catch (e) {
        log.warn('broadlink.codes_unreadable', { entity: r.entityId, error: e.message });
      }
    }
    return changed;
  }

  /** Télécommandes de clim choisies dans la bibliothèque (codes téléchargés une fois). */
  async #loadProfiles() {
    if (!this.remotes.length) return;
    try {
      await this.irStore.load();
    } catch (e) {
      log.warn('broadlink.profiles_unreadable', { error: e.message });
    }
    for (const r of this.remotes) if (r.uniqueId) this.profiles.set(r.uniqueId, await this.irStore.resolved(r.uniqueId));
  }

  /** Essai, choix ou retrait d'une télécommande de clim de la bibliothèque. */
  async #executeProfile(entry, value) {
    try {
      if (value.action === 'profile_clear') {
        await this.irStore.select(entry.uniqueId, value.device.trim(), null);
      } else {
        const profile = await this.irStore.profile(value.profile);
        if (value.action === 'profile_test') {
          const codes = profileTestCodes(profile, value.mode ?? 'cool');
          if (!codes) return { status: 'failed', error: 'Réglage absent de cette télécommande' };
          await this.#send({ type: 'call_service', domain: 'remote', service: 'send_command', service_data: { command: codes.map((c) => `b64:${c}`) }, target: { entity_id: entry.entityId } });
          return { status: 'confirmed' };
        }
        await this.irStore.select(entry.uniqueId, value.device.trim(), value.profile);
      }
    } catch (e) {
      return { status: 'failed', error: e.message };
    }
    // Nouvelle télécommande : la clim repart d'un état connu (éteinte).
    for (const id of this.assumed.keys()) if (id.endsWith(`:ir:${value.device.trim()}`)) this.assumed.delete(id);
    await this.#loadProfiles();
    this.#rebuild();
    return { status: 'confirmed' };
  }

  /** Envoi d'une touche, clim infrarouge, apprentissage : aucun retour d'état possible. */
  async #executeIr(externalId, entry, value) {
    const remote = this.states.get(entry.entityId);
    if (!remote || remote.state === 'unavailable') return { status: 'failed', error: 'Broadlink injoignable' };
    if (entry.base === 'ir_learn' && PROFILE_ACTIONS.includes(value?.action)) {
      if (remote.state === 'off') await this.#send({ type: 'call_service', domain: 'remote', service: 'turn_on', target: { entity_id: entry.entityId } }).catch(() => {});
      return this.#executeProfile(entry, value);
    }
    const r = irServiceCall(entry, value, this.assumed, externalId);
    if (r.error) return { status: 'failed', error: r.error };
    try {
      if (r.call) {
        // Télécommande désactivée dans HA : réactivée, sinon HA refuse l'envoi.
        if (remote.state === 'off') await this.#send({ type: 'call_service', domain: 'remote', service: 'turn_on', target: { entity_id: entry.entityId } });
        await this.#send({ type: 'call_service', domain: r.call.domain, service: r.call.service, service_data: r.call.data, target: r.call.target });
      }
    } catch (e) {
      return { status: 'failed', error: e.message };
    }
    if (r.learn) return this.#confirmLearn(entry.uniqueId, r.learn);
    r.after?.();
    this.emit('device', externalId, this.snapshot(externalId));
    return { status: 'confirmed' };
  }

  /** HA ne signale pas l'échec d'un apprentissage : on vérifie que la touche est bien enregistrée. */
  async #confirmLearn(uniqueId, { device, command, action }) {
    if (!this.configDir || !uniqueId) return { status: 'confirmed' };
    const has = () => (this.learned.get(uniqueId)?.[device] ?? []).includes(command);
    const end = Date.now() + this.learnWaitMs;
    for (;;) {
      await this.#readCodes().catch(() => false);
      if (has() === (action !== 'delete')) {
        this.#rebuild();
        return { status: 'confirmed' };
      }
      if (Date.now() >= end) break;
      await sleep(this.learnPollMs);
    }
    return action === 'delete'
      ? { status: 'failed', error: 'Touche non supprimée' }
      : { status: 'failed', error: 'Aucun signal reçu : visez le Broadlink avec la télécommande et réessayez' };
  }

  /**
   * Image actuelle d'une caméra (API camera_proxy de Home Assistant).
   * @returns {Promise<{bytes:Buffer, contentType:string}|null>} null si l'appareil n'a pas de caméra
   */
  async cameraSnapshot(externalId, key = 'camera') {
    const entry = this.inventory.get(externalId)?.capMap[key];
    if (!entry || entry.base !== 'camera') return null;
    const res = await this.fetchImpl(`${this.httpUrl}/api/camera_proxy/${encodeURIComponent(entry.entityId)}`, {
      headers: { Authorization: `Bearer ${this.token}` },
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) throw new Error(`Image de caméra indisponible (HTTP ${res.status})`);
    return { bytes: Buffer.from(await res.arrayBuffer()), contentType: res.headers.get('content-type')?.split(';')[0] || 'image/jpeg' };
  }

  /**
   * Exécute une commande et attend un retour d'état fiable.
   * @returns {Promise<{status:'confirmed'|'failed'|'timeout', error?:string}>}
   */
  async execute(externalId, key, value, timeoutMs) {
    const device = this.inventory.get(externalId);
    const entry = device?.capMap[key];
    if (!entry) return { status: 'failed', error: 'Capacité absente côté Home Assistant' };
    if (entry.base.startsWith('ir_')) return this.#executeIr(externalId, entry, value);
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
