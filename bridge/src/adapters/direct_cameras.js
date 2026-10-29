// Caméras IP branchées directement sur la passerelle (variable CAMERAS), sans Home Assistant.
//
// Chaque caméra est décrite par son adresse d'image fixe (« snapshot ») sur le réseau local :
//   CAMERAS="Entrée=http://admin:motdepasse@192.168.1.20/cgi-bin/snapshot.cgi;Garage=http://…"
// La passerelle doit donc tourner dans la maison (PC, box, mini-PC), sur le même réseau que les
// caméras. Authentification HTTP « Basic » uniquement (identifiants dans l'adresse).

import { createHash } from 'node:crypto';

import { log } from '../log.js';

/** @returns {Array<{name:string, url:string}>} */
export function parseCameras(raw) {
  if (!raw?.trim()) return [];
  return raw
    .split(/[;\n]/)
    .map((part) => part.trim())
    .filter(Boolean)
    .map((part) => {
      const i = part.indexOf('=');
      if (i <= 0) throw new Error(`CAMERAS : « Nom=adresse » attendu (reçu « ${part.slice(0, 40)} »)`);
      const name = part.slice(0, i).trim();
      const url = part.slice(i + 1).trim();
      let parsed;
      try {
        parsed = new URL(url);
      } catch {
        throw new Error(`CAMERAS : adresse invalide pour « ${name} »`);
      }
      if (!['http:', 'https:'].includes(parsed.protocol)) throw new Error(`CAMERAS : adresse http(s) attendue pour « ${name} »`);
      return { name, url };
    });
}

/** Requête sans identifiants dans l'URL (refusés par fetch) : ils passent en en-tête Basic. */
export function snapshotRequest(url) {
  const u = new URL(url);
  const headers = {};
  if (u.username || u.password) {
    headers.Authorization = `Basic ${Buffer.from(`${decodeURIComponent(u.username)}:${decodeURIComponent(u.password)}`).toString('base64')}`;
    u.username = '';
    u.password = '';
  }
  return { url: u.toString(), headers };
}

/**
 * Ajoute les caméras directes à l'inventaire d'un adaptateur existant (Home Assistant,
 * Tuya Cloud ou simulateur) : mêmes appareils, mêmes images, sans changer le cœur de la passerelle.
 */
export function addDirectCameras(adapter, cameras, { fetchImpl = (...a) => fetch(...a), probeEveryMs = 5 * 60_000 } = {}) {
  if (!cameras.length) return adapter;
  const descs = new Map();
  const status = new Map(); // externalId -> 'available' | 'unavailable' | 'unknown'
  for (const cam of cameras) {
    // Identifiant stable dérivé de l'adresse (sans l'exposer) : renommer la caméra ne la duplique pas.
    const externalId = `camera:${createHash('sha256').update(snapshotRequest(cam.url).url).digest('hex').slice(0, 16)}`;
    descs.set(externalId, {
      externalId,
      url: cam.url,
      name: cam.name,
      vendor: null,
      model: 'Caméra IP',
      protocol: 'wifi',
      connectionSource: 'local',
      isSensitive: false,
      capabilities: [{ capability_key: 'camera', type: 'string', writable: false, metadata: { kind: 'camera' } }],
      capMap: { camera: { base: 'camera' } },
    });
    status.set(externalId, 'unknown');
  }

  const fetchFrame = async (desc) => {
    const req = snapshotRequest(desc.url);
    const res = await fetchImpl(req.url, { headers: req.headers, signal: AbortSignal.timeout(8000) });
    if (!res.ok) throw new Error(`Image de caméra indisponible (HTTP ${res.status})`);
    return { bytes: Buffer.from(await res.arrayBuffer()), contentType: res.headers.get('content-type')?.split(';')[0] || 'image/jpeg' };
  };
  const setStatus = (externalId, next) => {
    if (status.get(externalId) === next) return;
    status.set(externalId, next);
    adapter.emit('device', externalId, snapshotOf(externalId));
  };
  const snapshotOf = (externalId) => {
    const s = status.get(externalId);
    return { state: s === 'available' ? { camera: 'idle' } : {}, availability: s };
  };
  const probe = async () => {
    for (const desc of descs.values()) {
      try {
        await fetchFrame(desc);
        setStatus(desc.externalId, 'available');
      } catch (e) {
        log.warn('camera.unreachable', { camera: desc.name, error: e.message });
        setStatus(desc.externalId, 'unavailable');
      }
    }
  };

  const base = {
    start: adapter.start.bind(adapter),
    stop: adapter.stop.bind(adapter),
    devices: adapter.devices.bind(adapter),
    snapshot: adapter.snapshot.bind(adapter),
    execute: adapter.execute.bind(adapter),
    cameraSnapshot: adapter.cameraSnapshot?.bind(adapter),
  };
  let timer = null;
  adapter.start = async () => {
    await base.start();
    await probe();
    timer = setInterval(() => probe().catch(() => {}), probeEveryMs);
  };
  adapter.stop = () => {
    clearInterval(timer);
    base.stop();
  };
  adapter.devices = () => [...base.devices(), ...descs.values()];
  adapter.snapshot = (externalId) => (descs.has(externalId) ? snapshotOf(externalId) : base.snapshot(externalId));
  adapter.execute = async (externalId, ...rest) =>
    descs.has(externalId) ? { status: 'failed', error: 'Une caméra ne se pilote pas' } : base.execute(externalId, ...rest);
  adapter.cameraSnapshot = async (externalId, key) => {
    const desc = descs.get(externalId);
    if (!desc) return base.cameraSnapshot ? base.cameraSnapshot(externalId, key) : null;
    try {
      const frame = await fetchFrame(desc);
      setStatus(externalId, 'available');
      return frame;
    } catch (e) {
      setStatus(externalId, 'unavailable');
      throw e;
    }
  };
  return adapter;
}
