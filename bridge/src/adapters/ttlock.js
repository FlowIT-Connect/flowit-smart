// Serrures et contrôles d'accès TTLock, ajoutés à l'inventaire de n'importe quel adaptateur
// (Tuya Cloud, Home Assistant ou simulateur) quand TTLOCK_CLIENT_ID est renseigné.
//
// Sans passerelle TTLock (G2/G3), le cloud permet quand même de créer des codes au clavier
// (calculés par TTLock, reconnus par la serrure hors ligne) et de lire la batterie et
// l'historique remontés par l'app TTLock. L'ouverture à distance n'est proposée que si
// TTLock annonce une passerelle pour la serrure (hasGateway).
//
// Ces appareils sont « sensibles » (§9) : bloqués tant que le propriétaire ne les a pas
// activés dans l'application, puis réservés aux commandes manuelles (voir la migration
// 20261030000000_solea_access_control.sql).

import { log } from '../log.js';

const HOUR = 3600_000;
/** Un code à usage unique TTLock doit être tapé dans les 6 heures. */
const ONE_TIME_MS = 6 * HOUR;
/** Origine des passages (recordType TTLock) ; les autres restent « other ». */
const RECORD_METHODS = { 1: 'app', 4: 'code', 7: 'card', 8: 'fingerprint', 10: 'key', 12: 'remote' };

/** État d'une clé électronique (keyStatus TTLock). */
const KEY_STATUS = { 110401: 'active', 110402: 'pending', 110405: 'frozen', 110408: 'deleted', 110410: 'reset' };

/** Accès partagés (eKeys) tels que les montre l'application ; la clé du compte de la passerelle est exclue. */
export function lockKeys(list, ownUsername) {
  return list
    .filter((k) => !ownUsername || k.username !== ownUsername)
    .map((k) => ({
      id: k.keyId,
      name: k.keyName || null,
      receiver: k.username,
      status: KEY_STATUS[Number(k.keyStatus)] ?? 'unknown',
      start: k.startDate ? new Date(k.startDate).toISOString() : null,
      end: k.endDate ? new Date(k.endDate).toISOString() : null,
    }))
    .filter((k) => k.status !== 'deleted' && k.status !== 'reset');
}

/** Masque un code d'accès dans l'historique : seuls les deux derniers chiffres restent. */
export const maskCode = (code) => (code ? `••${String(code).slice(-2)}` : null);

export function lockRecords(list) {
  return list.slice(0, 20).map((r) => ({
    at: new Date(r.lockDate ?? r.serverDate).toISOString(),
    method: RECORD_METHODS[r.recordType] ?? 'other',
    ok: r.success !== 0,
    who: r.username || maskCode(r.keyboardPwd),
  }));
}

/** Descripteur d'appareil FlowIT pour une serrure TTLock (même forme que les autres adaptateurs). */
export function buildLockDevice(lock) {
  const remote = lock.hasGateway === 1;
  const capabilities = [
    { capability_key: 'access_code', type: 'string', writable: true, metadata: { kind: 'access_code', options: ['one_time', 'period', 'permanent'] } },
    { capability_key: 'ekey', type: 'string', writable: true, metadata: { kind: 'ekey', options: ['send', 'freeze', 'unfreeze', 'change_period', 'delete'] } },
  ];
  if (remote) {
    capabilities.push(
      { capability_key: 'lock_action', type: 'enum', writable: true, metadata: { kind: 'lock', options: ['unlock'] } },
      { capability_key: 'lock_state', type: 'sensor', writable: false, metadata: { kind: 'lock_state' } },
    );
  }
  capabilities.push(
    { capability_key: 'battery', type: 'sensor', writable: false, metadata: { unit: '%' } },
    { capability_key: 'access_log', type: 'sensor', writable: false, metadata: { kind: 'access_log' } },
  );
  return {
    externalId: `ttlock:${lock.lockId}`,
    lockId: lock.lockId,
    remote,
    name: lock.lockAlias || lock.lockName || 'Serrure TTLock',
    vendor: 'TTLock',
    model: lock.lockName || 'Serrure TTLock',
    protocol: 'ble',
    connectionSource: remote ? 'gateway' : 'cloud',
    isSensitive: true,
    capabilities,
  };
}

/**
 * Dates du code demandé, en millisecondes, aux limites acceptées par TTLock
 * (code « période » à l'heure près).
 */
export function passcodeWindow(value, now) {
  switch (value.type) {
    case 'one_time':
      return { startDate: now, endDate: now + ONE_TIME_MS };
    case 'permanent':
      return { startDate: now, endDate: null };
    case 'period': {
      const start = Math.floor(Date.parse(value.start) / HOUR) * HOUR;
      const end = Math.ceil(Date.parse(value.end) / HOUR) * HOUR;
      return { startDate: Math.max(start, Math.floor(now / HOUR) * HOUR), endDate: end };
    }
    default:
      throw new Error('Type de code inconnu');
  }
}

/**
 * Ajoute les serrures TTLock à l'inventaire d'un adaptateur existant.
 * @param {any} adapter
 * @param {import('./ttlock_api.js').TTLockClient} client
 */
export function addTTLock(adapter, client, { pollMs = 5 * 60_000, now = () => Date.now() } = {}) {
  let descs = new Map(); // externalId -> descripteur
  const states = new Map(); // externalId -> état FlowIT
  let reachable = null; // dernier résultat du cloud TTLock (null = jamais interrogé)

  const snapshotOf = (externalId) => ({ state: states.get(externalId) ?? {}, availability: reachable ? 'available' : 'unavailable' });
  const setState = (externalId, patch) => {
    const before = JSON.stringify(states.get(externalId) ?? {});
    const next = { ...states.get(externalId), ...patch };
    states.set(externalId, next);
    if (JSON.stringify(next) !== before) adapter.emit('device', externalId, snapshotOf(externalId));
  };

  const refreshKeys = async (desc) => {
    try {
      setState(desc.externalId, { ekeys: lockKeys(await client.listKeys(desc.lockId), client.username) });
    } catch (e) {
      log.warn('ttlock.keys_failed', { lock: desc.lockId, error: e.message });
    }
  };

  const refreshRecords = async (desc) => {
    try {
      setState(desc.externalId, { access_log: lockRecords(await client.listRecords(desc.lockId)) });
    } catch (e) {
      log.warn('ttlock.records_failed', { lock: desc.lockId, error: e.message });
    }
  };

  const refresh = async () => {
    let locks;
    try {
      locks = await client.listLocks();
    } catch (e) {
      log.error('ttlock.poll_failed', { error: e.message });
      if (reachable !== false) {
        reachable = false;
        for (const id of descs.keys()) adapter.emit('device', id, snapshotOf(id));
      }
      return;
    }
    const wasReachable = reachable;
    reachable = true;
    const next = new Map(locks.map((l) => [`ttlock:${l.lockId}`, buildLockDevice(l)]));
    const changed =
      next.size !== descs.size || [...next].some(([id, d]) => descs.get(id)?.remote !== d.remote || descs.get(id)?.name !== d.name);
    descs = next;
    for (const lock of locks) {
      const id = `ttlock:${lock.lockId}`;
      if (typeof lock.electricQuantity === 'number' && lock.electricQuantity >= 0) setState(id, { battery: lock.electricQuantity });
      if (next.get(id).remote) {
        try {
          const s = await client.openState(lock.lockId);
          setState(id, { lock_state: s === 1 ? 'unlocked' : s === 0 ? 'locked' : 'unknown' });
        } catch (e) {
          log.warn('ttlock.state_failed', { lock: lock.lockId, error: e.message });
        }
      }
      await refreshRecords(next.get(id));
      await refreshKeys(next.get(id));
    }
    if (!locks.length) log.warn('ttlock.no_locks', { hint: 'Aucune serrure : vérifiez le compte de l\'app TTLock (identifiant et mot de passe)' });
    if (changed) {
      log.info('ttlock.inventory', { locks: next.size, remote: [...next.values()].filter((d) => d.remote).length });
      adapter.emit('inventory');
    } else if (!wasReachable) {
      for (const id of descs.keys()) adapter.emit('device', id, snapshotOf(id));
    }
  };

  const execute = async (desc, key, value) => {
    try {
      if (key === 'access_code') {
        const window = passcodeWindow(value, now());
        const r = await client.createPasscode(desc.lockId, { type: value.type, name: value.name, ...window });
        return {
          status: 'confirmed',
          accessCode: {
            kind: value.type,
            name: value.name || null,
            code: String(r.keyboardPwd),
            starts_at: new Date(window.startDate).toISOString(),
            ends_at: window.endDate ? new Date(window.endDate).toISOString() : null,
          },
        };
      }
      if (key === 'ekey') {
        const dates = (v) => (v.start && v.end ? { startDate: Date.parse(v.start), endDate: Date.parse(v.end) } : { startDate: 0, endDate: 0 });
        if (value.action === 'send') await client.sendKey(desc.lockId, { receiver: value.receiver, name: value.name || value.receiver, ...dates(value) });
        else if (value.action === 'freeze') await client.freezeKey(value.key_id);
        else if (value.action === 'unfreeze') await client.unfreezeKey(value.key_id);
        else if (value.action === 'delete') await client.deleteKey(value.key_id);
        else if (value.action === 'change_period') await client.changeKeyPeriod(value.key_id, dates(value));
        await refreshKeys(desc); // l'application voit tout de suite la nouvelle liste
        return { status: 'confirmed' };
      }
      if (key === 'lock_action' && value === 'unlock') {
        if (!desc.remote) return { status: 'failed', error: 'Ouverture à distance impossible : ajoutez une passerelle TTLock (G2/G3)' };
        await client.unlock(desc.lockId);
        setState(desc.externalId, { lock_state: 'unlocked' });
        setTimeout(() => refreshRecords(desc), 5_000).unref?.();
        return { status: 'confirmed' };
      }
      return { status: 'failed', error: 'Capacité absente côté TTLock' };
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
  adapter.snapshot = (externalId) => (descs.has(externalId) ? snapshotOf(externalId) : base.snapshot(externalId));
  adapter.execute = async (externalId, key, value, ...rest) => {
    const desc = descs.get(externalId);
    return desc ? execute(desc, key, value) : base.execute(externalId, key, value, ...rest);
  };
  return adapter;
}
