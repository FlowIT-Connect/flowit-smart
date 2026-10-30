import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { afterEach, beforeEach, describe, test } from 'node:test';

import { addTTLock, buildLockDevice, lockRecords, passcodeWindow } from '../src/adapters/ttlock.js';
import { md5, TTLockClient } from '../src/adapters/ttlock_api.js';
import { Bridge } from '../src/bridge.js';
import { loadConfig } from '../src/config.js';
import { setLogLevel } from '../src/log.js';
import { validateValue } from '../src/validate.js';
import { CLIENT_ID, CLIENT_SECRET, FakeTTLockCloud, PASSWORD_MD5, USERNAME } from './fake_ttlock_cloud.js';
import { MemoryStore } from './memory_store.js';

setLogLevel('error');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function until(fn, ms = 3000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (await fn()) return true;
    await sleep(20);
  }
  return false;
}

const client = (cloud, extra = {}) =>
  new TTLockClient({ clientId: CLIENT_ID, clientSecret: CLIENT_SECRET, username: USERNAME, passwordMd5: PASSWORD_MD5, fetchImpl: cloud.fetch, ...extra });

/** Adaptateur de base sans appareil (comme un compte Tuya vide). */
class EmptyAdapter extends EventEmitter {
  async start() {}
  stop() {}
  devices() { return []; }
  snapshot() { return { state: {}, availability: 'unavailable' }; }
  async execute() { return { status: 'failed', error: 'aucun appareil' }; }
}

describe('API TTLock', () => {
  test('mot de passe haché en MD5 minuscule (exigé par TTLock)', () => {
    assert.equal(md5('password'), '5f4dcc3b5aa765d61d8327deb882cf99');
    assert.match(md5('Été 2026'), /^[0-9a-f]{32}$/);
  });

  test('connexion puis appel authentifié avec clientId, accessToken et date', async () => {
    const cloud = new FakeTTLockCloud();
    const locks = await client(cloud).listLocks();
    assert.equal(locks.length, 2);
    const call = cloud.calls.find((c) => c.path === '/v3/lock/list');
    assert.equal(call.params.clientId, CLIENT_ID);
    assert.equal(call.params.accessToken, 'tok-1');
    assert.match(call.params.date, /^\d{13}$/);
  });

  test('jeton refusé : renouvelé automatiquement', async () => {
    const cloud = new FakeTTLockCloud();
    const c = client(cloud);
    await c.listLocks();
    cloud.tokens.clear();
    assert.equal((await c.listLocks()).length, 2);
    assert.equal(cloud.issued, 2);
  });

  test('erreurs expliquées : mauvais mot de passe, pas de passerelle', async () => {
    const cloud = new FakeTTLockCloud();
    await assert.rejects(client(cloud, { passwordMd5: md5('faux') }).listLocks(), /Identifiant ou mot de passe TTLock incorrect/);
    await assert.rejects(client(cloud).unlock(1001), /aucune passerelle TTLock/);
  });
});

describe('Correspondance TTLock', () => {
  test('sans passerelle : codes, batterie, historique ; pas d\'ouverture à distance', () => {
    const d = buildLockDevice({ lockId: 1, lockAlias: 'Entrée', lockName: 'M201', hasGateway: 0 });
    assert.equal(d.isSensitive, true);
    assert.equal(d.connectionSource, 'cloud');
    assert.deepEqual(d.capabilities.map((c) => c.capability_key), ['access_code', 'ekey', 'battery', 'access_log']);
  });

  test('avec passerelle : ouverture à distance et état ouvert / fermé', () => {
    const d = buildLockDevice({ lockId: 2, lockName: 'S31', hasGateway: 1 });
    assert.equal(d.name, 'S31');
    assert.deepEqual(d.capabilities.map((c) => c.capability_key), ['access_code', 'ekey', 'lock_action', 'lock_state', 'battery', 'access_log']);
  });

  test('historique : origine du passage, code masqué', () => {
    const [a, b] = lockRecords([
      { recordType: 4, success: 1, keyboardPwd: '48213977', lockDate: 0 },
      { recordType: 99, success: 0, username: 'baziz', lockDate: 0 },
    ]);
    assert.deepEqual(a, { at: '1970-01-01T00:00:00.000Z', method: 'code', ok: true, who: '••77' });
    assert.deepEqual(b, { at: '1970-01-01T00:00:00.000Z', method: 'other', ok: false, who: 'baziz' });
  });

  test('dates des codes : 6 h pour un code unique, période à l\'heure près', () => {
    const now = Date.parse('2026-10-30T10:20:00Z');
    assert.deepEqual(passcodeWindow({ type: 'one_time' }, now), { startDate: now, endDate: now + 6 * 3600_000 });
    assert.deepEqual(passcodeWindow({ type: 'permanent' }, now), { startDate: now, endDate: null });
    const p = passcodeWindow({ type: 'period', start: '2026-10-31T09:30:00Z', end: '2026-11-02T17:10:00Z' }, now);
    assert.equal(new Date(p.startDate).toISOString(), '2026-10-31T09:00:00.000Z');
    assert.equal(new Date(p.endDate).toISOString(), '2026-11-02T18:00:00.000Z');
  });

  test('validation des demandes de code (liste blanche)', () => {
    const cap = { capability_key: 'access_code', type: 'string', writable: true, metadata: { kind: 'access_code', options: ['one_time', 'period', 'permanent'] } };
    assert.equal(validateValue(cap, { type: 'one_time', name: 'Livreur' }), null);
    assert.equal(validateValue(cap, { type: 'period', start: '2026-10-31T09:00:00Z', end: '2099-01-01T00:00:00Z' }), 'Période d\'un an au plus');
    assert.equal(validateValue(cap, { type: 'period', start: '2099-01-02T00:00:00Z', end: '2099-01-01T00:00:00Z' }), 'La fin doit être après le début');
    assert.equal(validateValue(cap, { type: 'master' }), 'Type de code non pris en charge');
    assert.equal(validateValue(cap, { type: 'one_time', code: '1234' }), 'Demande de code invalide');
    assert.equal(validateValue(cap, 'one_time'), 'Demande de code invalide');
    assert.equal(validateValue({ ...cap, metadata: {} }, { type: 'one_time' }), 'Type de capacité non pilotable');
    const key = { capability_key: 'ekey', type: 'string', writable: true, metadata: { kind: 'ekey', options: ['send', 'freeze', 'unfreeze', 'change_period', 'delete'] } };
    assert.equal(validateValue(key, { action: 'send', receiver: '+213555000111' }), null);
    assert.equal(validateValue(key, { action: 'send', receiver: 'a b' }), 'Compte TTLock du destinataire attendu (téléphone ou e-mail)');
    assert.equal(validateValue(key, { action: 'send', receiver: 'x@y.dz', start: '2099-01-01T00:00:00Z' }), 'Dates de début et de fin attendues');
    assert.equal(validateValue(key, { action: 'freeze', key_id: 12 }), null);
    assert.equal(validateValue(key, { action: 'freeze', key_id: '12' }), 'Clé électronique introuvable');
    assert.equal(validateValue(key, { action: 'transfer', key_id: 12 }), 'Action non prise en charge');
  });

  test('configuration : TTLock facultatif, mot de passe attendu en MD5', () => {
    const base = { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'k', INTEGRATION_ID: 'i', ADAPTER: 'simulator' };
    assert.equal(loadConfig(base).ttlock, null);
    const ok = loadConfig({ ...base, TTLOCK_CLIENT_ID: 'c', TTLOCK_CLIENT_SECRET: 's', TTLOCK_USERNAME: 'u', TTLOCK_PASSWORD_MD5: PASSWORD_MD5.toUpperCase() });
    assert.equal(ok.ttlock.passwordMd5, PASSWORD_MD5);
    assert.equal(ok.ttlock.baseUrl, 'https://euapi.ttlock.com');
    assert.equal(ok.ttlock.pollMs, 300_000);
    assert.throws(() => loadConfig({ ...base, TTLOCK_CLIENT_ID: 'c', TTLOCK_CLIENT_SECRET: 's', TTLOCK_USERNAME: 'u', TTLOCK_PASSWORD_MD5: 'motdepasse' }), /MD5/);
  });
});

describe('Passerelle avec serrures TTLock', () => {
  let cloud, store, bridge;

  beforeEach(async () => {
    cloud = new FakeTTLockCloud();
    store = new MemoryStore();
    const adapter = addTTLock(new EmptyAdapter(), client(cloud), { pollMs: 60_000 });
    bridge = new Bridge({
      store,
      adapter,
      config: { integrationId: 'integ-1', commandTimeoutMs: 500, pendingMaxAgeMs: 30_000, pollIntervalMs: 30, automationRefreshMs: 60_000, runAutomations: false },
    });
    await bridge.start();
  });

  afterEach(async () => {
    await bridge.stop();
  });

  const cmd = (device, capability_key, value, extra = {}) =>
    store.insertCommand({ home_id: 'home-1', device_id: device.id, capability_key, value, idempotency_key: Math.random().toString(), requested_by: 'owner-1', ...extra });

  test('inventaire : boîtiers sensibles, batterie et historique', () => {
    const box = store.deviceByName('Boîtier entrée');
    assert.equal(box.is_sensitive, true);
    assert.equal(box.vendor, 'TTLock');
    assert.equal(box.availability, 'available');
    assert.equal(box.state.battery, 82);
    assert.equal(box.state.access_log[0].who, '••77');
    assert.equal(store.deviceByName('Porte garage').state.lock_state, 'locked');
  });

  test('clé Bluetooth de la serrure transmise pour l\'app Android, jamais dans l\'état', () => {
    const box = store.deviceByName('Boîtier entrée');
    assert.equal(store.bleKeys.get(box.id).lock_data, 'lockdata-1001');
    assert.equal(store.bleKeys.get(box.id).home_id, 'home-1');
    assert.ok(!JSON.stringify(box.state).includes('lockdata'));
    // Pas de clé du compte sur la porte du garage : rien n'est enregistré.
    assert.equal(store.bleKeys.has(store.deviceByName('Porte garage').id), false);
  });

  test('base sans table des clés Bluetooth : l\'inventaire continue', async () => {
    const failing = new MemoryStore();
    failing.saveBleKey = async () => {
      throw new Error('relation "device_ble_keys" does not exist');
    };
    const other = new Bridge({
      store: failing,
      adapter: addTTLock(new EmptyAdapter(), client(new FakeTTLockCloud()), { pollMs: 60_000 }),
      config: { integrationId: 'integ-1', commandTimeoutMs: 500, pendingMaxAgeMs: 30_000, pollIntervalMs: 30, automationRefreshMs: 60_000, runAutomations: false },
    });
    await other.start();
    try {
      assert.equal(failing.deviceByName('Porte garage').vendor, 'TTLock');
    } finally {
      await other.stop();
    }
  });

  test('code refusé tant que la ou le propriétaire n\'a pas activé le boîtier', async () => {
    const box = store.deviceByName('Boîtier entrée');
    const c = await cmd(box, 'access_code', { type: 'one_time' });
    assert.ok(await until(() => c.status === 'rejected'));
    assert.equal(cloud.calls.filter((x) => x.path === '/v3/keyboardPwd/get').length, 0);
    assert.equal(store.accessCodes.length, 0);
  });

  test('boîtier activé : code créé, enregistré pour l\'app, jamais dans la commande', async () => {
    const box = store.deviceByName('Boîtier entrée');
    box.security_validated_at = new Date().toISOString();
    const c = await cmd(box, 'access_code', { type: 'period', name: 'Femme de ménage', start: new Date().toISOString(), end: new Date(Date.now() + 86_400_000).toISOString() });
    assert.ok(await until(() => c.status === 'confirmed'), `statut ${c.status} ${c.error}`);
    const call = cloud.calls.find((x) => x.path === '/v3/keyboardPwd/get');
    assert.equal(call.params.keyboardPwdType, '3');
    assert.equal(call.params.keyboardPwdName, 'Femme de ménage');
    assert.equal(store.accessCodes.length, 1);
    const saved = store.accessCodes[0];
    assert.equal(saved.kind, 'period');
    assert.equal(saved.command_id, c.id);
    assert.equal(saved.created_by, 'owner-1');
    assert.match(saved.code, /^\d+$/);
    assert.equal(JSON.stringify(c).includes(saved.code), false);
  });

  test('automatisation ou scène : refusée même boîtier activé', async () => {
    const box = store.deviceByName('Boîtier entrée');
    box.security_validated_at = new Date().toISOString();
    const a = await cmd(box, 'access_code', { type: 'one_time' }, { requested_by: null, automation_id: 'auto-1' });
    assert.ok(await until(() => a.status === 'rejected'));
    assert.equal(store.accessCodes.length, 0);
  });

  test('ouverture à distance : impossible sans passerelle, confirmée avec', async () => {
    const box = store.deviceByName('Boîtier entrée');
    const garage = store.deviceByName('Porte garage');
    box.security_validated_at = garage.security_validated_at = new Date().toISOString();
    const a = await cmd(box, 'lock_action', 'unlock');
    assert.ok(await until(() => a.status === 'rejected'), `statut ${a.status}`); // capacité absente
    const b = await cmd(garage, 'lock_action', 'unlock');
    assert.ok(await until(() => b.status === 'confirmed'), `statut ${b.status} ${b.error}`);
    assert.equal(cloud.openState.get(1002), 1);
    assert.ok(await until(() => garage.state.lock_state === 'unlocked'));
  });

  test('accès partagés : liste sans la clé du compte, partage programmé, désactivation, réactivation, suppression', async () => {
    const box = store.deviceByName('Boîtier entrée');
    assert.deepEqual(box.state.ekeys.map((k) => k.name), ['Karim']);
    box.security_validated_at = new Date().toISOString();
    const start = new Date(Date.now() + 3600_000).toISOString();
    const end = new Date(Date.now() + 7 * 86_400_000).toISOString();
    const send = await cmd(box, 'ekey', { action: 'send', receiver: 'amina@x.dz', name: 'Amina', start, end });
    assert.ok(await until(() => send.status === 'confirmed'), `statut ${send.status} ${send.error}`);
    const amina = box.state.ekeys.find((k) => k.name === 'Amina');
    assert.equal(amina.receiver, 'amina@x.dz');
    assert.equal(amina.start, start);
    assert.equal(amina.status, 'active');

    const freeze = await cmd(box, 'ekey', { action: 'freeze', key_id: amina.id });
    assert.ok(await until(() => freeze.status === 'confirmed'));
    assert.equal(box.state.ekeys.find((k) => k.id === amina.id).status, 'frozen');
    const unfreeze = await cmd(box, 'ekey', { action: 'unfreeze', key_id: amina.id });
    assert.ok(await until(() => unfreeze.status === 'confirmed'));
    assert.equal(box.state.ekeys.find((k) => k.id === amina.id).status, 'active');
    const forever = await cmd(box, 'ekey', { action: 'change_period', key_id: amina.id });
    assert.ok(await until(() => forever.status === 'confirmed'));
    assert.equal(box.state.ekeys.find((k) => k.id === amina.id).end, null);
    const del = await cmd(box, 'ekey', { action: 'delete', key_id: amina.id });
    assert.ok(await until(() => del.status === 'confirmed'));
    assert.equal(box.state.ekeys.some((k) => k.id === amina.id), false);
  });

  test('accès partagé : destinataire sans compte TTLock expliqué', async () => {
    const box = store.deviceByName('Boîtier entrée');
    box.security_validated_at = new Date().toISOString();
    const c = await cmd(box, 'ekey', { action: 'send', receiver: 'inconnu@x.dz' });
    assert.ok(await until(() => c.status === 'failed'));
    assert.match(c.error, /installer l'app TTLock/);
  });

  test('erreur TTLock : commande en échec avec un message clair', async () => {
    const garage = store.deviceByName('Porte garage');
    garage.security_validated_at = new Date().toISOString();
    cloud.failNext = -3002;
    const c = await cmd(garage, 'lock_action', 'unlock');
    assert.ok(await until(() => c.status === 'failed'));
    assert.match(c.error, /Passerelle TTLock hors ligne/);
  });
});

test('assistant : section TTLock du .env relue par la configuration', async () => {
  const { parseEnv, renderEnv } = await import('../src/setup.js');
  const v = { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'k', INTEGRATION_ID: 'i', TUYA_ACCESS_ID: 'a', TUYA_ACCESS_SECRET: 's', TUYA_REGION: 'eu' };
  assert.equal(parseEnv(renderEnv(v)).TTLOCK_CLIENT_ID, undefined);
  const env = parseEnv(renderEnv({ ...v, TTLOCK_CLIENT_ID: 'c', TTLOCK_CLIENT_SECRET: 'cs', TTLOCK_USERNAME: 'u', TTLOCK_PASSWORD_MD5: PASSWORD_MD5 }));
  assert.equal(loadConfig(env).ttlock.username, 'u');
  assert.equal(renderEnv({ ...v, TTLOCK_CLIENT_ID: 'c', TTLOCK_PASSWORD_MD5: PASSWORD_MD5 }).includes('motdepasse'), false);
});

test('Ajouter-TTLock : lecture du formulaire du Bloc-notes', async () => {
  const { readForm } = await import('../src/setup_ttlock.js');
  const filled = readForm('﻿# aide\r\nCLIENT_ID= cid \r\nCLIENT_SECRET=s=1\r\nIDENTIFIANT_APP_TTLOCK=+213555000111\r\nMOT_DE_PASSE_APP_TTLOCK=pw\r\n');
  assert.deepEqual(filled.missing, []);
  assert.equal(filled.values.CLIENT_ID, 'cid');
  assert.equal(filled.values.CLIENT_SECRET, 's=1');
  assert.deepEqual(readForm('CLIENT_ID=cid\nCLIENT_SECRET=\n').missing, ['CLIENT_SECRET', 'IDENTIFIANT_APP_TTLOCK', 'MOT_DE_PASSE_APP_TTLOCK']);
});
