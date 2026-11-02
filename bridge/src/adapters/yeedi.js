// Robots aspirateurs yeedi / Ecovacs, ajoutés à l'inventaire de n'importe quel adaptateur
// quand YEEDI_URL est renseigné.
//
// La passerelle ne parle pas elle-même au cloud yeedi : elle lit le module séparé
// « Solea Yeedi » (dossier yeedi/ du dépôt, licence GPL) par son API locale HTTP.
// Les deux programmes restent indépendants ; seul ce petit client vit ici.

import { log } from '../log.js';

export const VACUUM_ACTIONS = ['start', 'pause', 'resume', 'stop', 'charge'];
export const SUCTION_OPTIONS = ['quiet', 'standard', 'strong', 'max'];

export class YeediClient {
  /** @param {{url:string, token:string, fetchImpl?:typeof fetch}} opts */
  constructor({ url, token, fetchImpl = fetch }) {
    this.url = url.replace(/\/$/, '');
    this.token = token;
    this.fetch = fetchImpl;
  }

  async #call(path, init = {}, timeoutMs = 10_000) {
    const res = await this.fetch(`${this.url}${path}`, {
      ...init,
      headers: { authorization: `Bearer ${this.token}`, 'content-type': 'application/json' },
      signal: AbortSignal.timeout(timeoutMs),
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || `module yeedi : HTTP ${res.status}`);
    return body;
  }

  /** @returns {Promise<Array<{id:string,name:string,model:string,online:boolean,state:object}>>} */
  robots() {
    return this.#call('/robots');
  }

  /** @param {{action?:string, suction?:string}} cmd */
  command(id, cmd, timeoutMs) {
    return this.#call(`/robots/${encodeURIComponent(id)}/command`, { method: 'POST', body: JSON.stringify(cmd) }, timeoutMs + 5_000);
  }
}

/** Descripteur d'appareil FlowIT d'un robot aspirateur (même forme que les autres adaptateurs). */
export function buildVacuumDevice(robot) {
  return {
    externalId: `yeedi:${robot.id}`,
    robotId: robot.id,
    name: robot.name || 'Robot aspirateur',
    vendor: 'yeedi',
    // « yeedi 2 hybrid » → « 2 hybrid » : l'application affiche déjà la marque devant.
    model: String(robot.model || '').replace(/^yeedi\s+/i, '') || 'robot aspirateur',
    protocol: 'wifi',
    connectionSource: 'cloud',
    isSensitive: false,
    capabilities: [
      { capability_key: 'vacuum_action', type: 'enum', writable: true, metadata: { kind: 'vacuum', options: VACUUM_ACTIONS } },
      { capability_key: 'vacuum_state', type: 'sensor', writable: false, metadata: { kind: 'vacuum_state' } },
      { capability_key: 'suction', type: 'enum', writable: true, metadata: { options: SUCTION_OPTIONS } },
      { capability_key: 'battery', type: 'sensor', writable: false, metadata: { unit: '%' } },
      { capability_key: 'vacuum_error', type: 'sensor', writable: false, metadata: { kind: 'text' } },
    ],
  };
}

/** État FlowIT d'un robot lu dans le module. */
export function vacuumState(robot) {
  const s = robot.state ?? {};
  const state = {};
  if (s.status) state.vacuum_state = s.status;
  if (Number.isFinite(s.battery)) state.battery = s.battery;
  if (s.suction) state.suction = s.suction;
  if (s.error) state.vacuum_error = s.error;
  return state;
}

/**
 * Ajoute les robots du module yeedi à l'inventaire d'un adaptateur existant.
 * @param {any} adapter
 * @param {YeediClient} client
 */
export function addYeedi(adapter, client, { pollMs = 15_000 } = {}) {
  let descs = new Map(); // externalId -> descripteur
  const snapshots = new Map(); // externalId -> {state, availability}
  let reachable = null;

  const publish = (robot) => {
    const id = `yeedi:${robot.id}`;
    const snap = { state: vacuumState(robot), availability: robot.online && reachable ? 'available' : 'unavailable' };
    const before = JSON.stringify(snapshots.get(id) ?? null);
    snapshots.set(id, snap);
    if (JSON.stringify(snap) !== before && descs.has(id)) adapter.emit('device', id, snap);
  };

  const refresh = async () => {
    let robots;
    try {
      robots = await client.robots();
    } catch (e) {
      if (reachable !== false) {
        log.error('yeedi.unreachable', { error: e.message, hint: 'Le module yeedi tourne-t-il ? (Lancer-Yeedi.cmd)' });
        reachable = false;
        for (const [id, snap] of snapshots) {
          snapshots.set(id, { ...snap, availability: 'unavailable' });
          adapter.emit('device', id, snapshots.get(id));
        }
      }
      return;
    }
    reachable = true;
    const next = new Map(robots.map((r) => [`yeedi:${r.id}`, buildVacuumDevice(r)]));
    const changed = next.size !== descs.size || [...next].some(([id, d]) => descs.get(id)?.name !== d.name);
    descs = next;
    for (const r of robots) publish(r);
    if (changed) {
      log.info('yeedi.inventory', { robots: next.size });
      adapter.emit('inventory');
    }
  };

  // Un robot met souvent plus de temps qu'une prise à annoncer son nouvel état.
  const execute = async (desc, key, value, timeoutMs) => {
    timeoutMs = Math.max(timeoutMs ?? 0, 30_000);
    const cmd = key === 'vacuum_action' ? { action: value } : key === 'suction' ? { suction: value } : null;
    if (!cmd) return { status: 'failed', error: 'Capacité absente côté yeedi' };
    try {
      const r = await client.command(desc.robotId, cmd, timeoutMs);
      if (r.robot) publish(r.robot);
      return r.status === 'confirmed' ? { status: 'confirmed' } : { status: r.status === 'timeout' ? 'timeout' : 'failed', error: r.error };
    } catch (e) {
      return { status: 'failed', error: e.message };
    }
  };

  const base = {
    start: adapter.start.bind(adapter),
    stop: adapter.stop.bind(adapter),
    devices: adapter.devices.bind(adapter),
    snapshot: adapter.snapshot.bind(adapter),
    execute: adapter.execute.bind(adapter),
  };
  let timer = null;
  adapter.start = async () => {
    await base.start();
    await refresh();
    timer = setInterval(() => refresh().catch(() => {}), pollMs);
  };
  adapter.stop = () => {
    clearInterval(timer);
    base.stop();
  };
  adapter.devices = () => [...base.devices(), ...descs.values()];
  adapter.snapshot = (externalId) =>
    descs.has(externalId) ? (snapshots.get(externalId) ?? { state: {}, availability: 'unavailable' }) : base.snapshot(externalId);
  adapter.execute = async (externalId, key, value, timeoutMs, ...rest) => {
    const desc = descs.get(externalId);
    return desc ? execute(desc, key, value, timeoutMs) : base.execute(externalId, key, value, timeoutMs, ...rest);
  };
  return adapter;
}
