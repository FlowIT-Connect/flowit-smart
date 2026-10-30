import assert from 'node:assert/strict';
import { createHash, createHmac } from 'node:crypto';
import { afterEach, beforeEach, describe, test } from 'node:test';

import { canonicalPath, sign, TuyaClient } from '../src/adapters/tuya_api.js';
import { TuyaCloudAdapter } from '../src/adapters/tuya_cloud.js';
import { buildTuyaDevice, hexToHsv, hsvToHex, statusMap, tuyaSnapshot, tuyaStateMatches } from '../src/adapters/tuya_mapping.js';
import { Bridge } from '../src/bridge.js';
import { loadConfig } from '../src/config.js';
import { setLogLevel } from '../src/log.js';
import { ACCESS_ID, ACCESS_SECRET, demoTuyaDevices, FakeTuyaCloud } from './fake_tuya_cloud.js';
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
const demo = (id) => demoTuyaDevices().find((d) => d.id === id);
const descOf = (id) => buildTuyaDevice(demo(id), demo(id).spec);

describe('API Tuya', () => {
  test('signature : chaîne à signer et HMAC conformes à la documentation Tuya', () => {
    const body = '{"commands":[{"code":"switch_1","value":true}]}';
    const path = '/v1.0/devices/abc/commands';
    const str = `POST\n${createHash('sha256').update(body).digest('hex')}\n\n${path}`;
    const expected = createHmac('sha256', 'secret').update(`idtok1700000000000n1${str}`).digest('hex').toUpperCase();
    assert.equal(sign({ clientId: 'id', secret: 'secret', accessToken: 'tok', t: '1700000000000', nonce: 'n1', method: 'POST', body, pathWithQuery: path }), expected);
  });

  test('paramètres triés et vides ignorés', () => {
    assert.equal(canonicalPath('/v1.0/x', { size: 100, last_row_key: undefined, a: 'b' }), '/v1.0/x?a=b&size=100');
    assert.equal(canonicalPath('/v1.0/x'), '/v1.0/x');
  });

  test('jeton expiré : renouvelé automatiquement', async () => {
    const cloud = new FakeTuyaCloud();
    const client = new TuyaClient({ accessId: ACCESS_ID, accessSecret: ACCESS_SECRET, baseUrl: 'https://openapi.tuyaeu.com', fetchImpl: cloud.fetch });
    assert.equal((await client.listDevices()).length, 9);
    cloud.token = 'tok-2'; // le cloud invalide l'ancien jeton
    assert.equal((await client.listDevices()).length, 9);
    assert.equal(cloud.calls.filter((c) => c === 'GET /v1.0/token').length, 2);
  });

  test('mauvais Access Secret : message clair', async () => {
    const cloud = new FakeTuyaCloud();
    const client = new TuyaClient({ accessId: ACCESS_ID, accessSecret: 'faux', baseUrl: 'https://openapi.tuyaeu.com', fetchImpl: cloud.fetch });
    await assert.rejects(client.listDevices(), /Access ID ou Access Secret incorrect/);
  });
});

describe('Correspondance Tuya → FlowIT', () => {
  test('prise : interrupteur + puissance et énergie à l\'échelle', () => {
    const d = descOf('plug1');
    assert.deepEqual(d.capabilities.map((c) => c.capability_key), ['switch', 'power', 'energy']);
    assert.equal(d.protocol, 'tuya');
    assert.equal(d.connectionSource, 'cloud');
    const snap = tuyaSnapshot(d, statusMap([{ code: 'switch_1', value: true }, { code: 'cur_power', value: 1180 }, { code: 'add_ele', value: 125 }]), true);
    assert.deepEqual(snap, { state: { switch: true, power: 118, energy: 0.125 }, availability: 'available' });
    assert.deepEqual(d.capMap.switch.write(true), [{ code: 'switch_1', value: true }]);
  });

  test('multiprise : switch puis switch_2 dans l\'ordre des prises', () => {
    const d = descOf('multi1');
    assert.deepEqual(d.capabilities.map((c) => c.capability_key), ['switch', 'switch_2']);
    assert.deepEqual(d.capMap.switch_2.write(true), [{ code: 'switch_2', value: true }]);
  });

  test('ampoule : luminosité en %, blanc en kelvins, couleur', () => {
    const d = descOf('bulb1');
    assert.deepEqual(d.capabilities.map((c) => c.capability_key), ['switch', 'brightness', 'color_temp', 'color']);
    const st = statusMap(demo('bulb1').status);
    assert.equal(d.capMap.brightness.read(st), 51);
    assert.equal(d.capMap.color_temp.read(st), 2700);
    assert.equal(d.capMap.color.read(st), '#FF0000');
    assert.deepEqual(d.capMap.brightness.write(100), [{ code: 'switch_led', value: true }, { code: 'work_mode', value: 'white' }, { code: 'bright_value_v2', value: 1000 }]);
    assert.deepEqual(d.capMap.color.write('#00FF00').at(-1), { code: 'colour_data_v2', value: { h: 120, s: 1000, v: 1000 } });
    assert.equal(d.capMap.color_temp.write(6500).at(-1).value, 1000);
  });

  test('couleurs : aller-retour HSV ↔ #RRGGBB', () => {
    for (const hex of ['#FF0000', '#3F51B5', '#FFFFFF', '#123456']) {
      const { h, s, v } = hexToHsv(hex);
      assert.ok(tuyaStateMatches({ base: 'color', read: () => hsvToHex(h, s, v) }, null, hex), hex);
    }
  });

  test('capteur température / humidité / batterie (lecture seule)', () => {
    const d = descOf('th1');
    assert.deepEqual(d.capabilities.map((c) => [c.capability_key, c.writable]), [['temperature', false], ['humidity', false], ['battery', false]]);
    assert.deepEqual(tuyaSnapshot(d, statusMap(demo('th1').status), true).state, { temperature: 21.5, humidity: 48, battery: 90 });
  });

  test('serrure : sensible, aucune commande exposée', () => {
    const d = descOf('lock1');
    assert.equal(d.isSensitive, true);
    assert.deepEqual(d.capabilities.map((c) => c.capability_key), ['battery']);
  });

  test('rideau avec position : ouverture en % + boutons Ouvrir / Stop / Fermer', () => {
    const d = descOf('curtain1');
    assert.deepEqual(d.capabilities.map((c) => c.capability_key), ['cover_position', 'cover_control']);
    assert.deepEqual(d.capabilities[1].metadata.options, ['open', 'stop', 'close']); // « continue » n'est pas proposé
    const st = statusMap(demo('curtain1').status);
    assert.equal(d.capMap.cover_position.read(st), 30);
    assert.equal(d.capMap.cover_control.read(st), 'stop');
    assert.deepEqual(d.capMap.cover_control.write('open'), [{ code: 'control', value: 'open' }]);
  });

  test('rideau sans position : boutons seuls, dans l\'ordre Ouvrir / Stop / Fermer', () => {
    const d = descOf('curtain2');
    assert.deepEqual(d.capabilities.map((c) => c.capability_key), ['cover_control']);
    assert.deepEqual(d.capabilities[0].metadata.options, ['open', 'stop', 'close']);
    assert.equal(d.capMap.cover_control.read(statusMap([{ code: 'control', value: 'continue' }])), null);
  });

  test('appareil hors ligne : indisponible', () => {
    assert.deepEqual(tuyaSnapshot(descOf('off1'), new Map(), false), { state: {}, availability: 'unavailable' });
  });

  test('appareil sans fonction reconnue : aucune capacité', () => {
    assert.equal(descOf('ir1').capabilities.length, 0);
  });
});

describe('Passerelle avec Tuya Cloud (sans box)', () => {
  let cloud, store, bridge, adapter;

  beforeEach(async () => {
    cloud = new FakeTuyaCloud();
    store = new MemoryStore();
    const client = new TuyaClient({ accessId: ACCESS_ID, accessSecret: ACCESS_SECRET, baseUrl: 'https://openapi.tuyaeu.com', fetchImpl: cloud.fetch });
    adapter = new TuyaCloudAdapter({ client, pollMs: 50, confirmPollMs: 20 });
    bridge = new Bridge({
      store,
      adapter,
      config: { integrationId: 'integ-1', commandTimeoutMs: 400, pendingMaxAgeMs: 30_000, pollIntervalMs: 50, automationRefreshMs: 60_000, runAutomations: false },
    });
    await bridge.start();
  });

  afterEach(async () => {
    await bridge.stop();
  });

  const cmd = (device, capability_key, value) =>
    store.insertCommand({ home_id: 'home-1', device_id: device.id, capability_key, value, idempotency_key: Math.random().toString(), requested_by: 'u1' });

  test('inventaire : appareils importés, intégration connectée', () => {
    assert.equal(store.devices.size, 8); // la télécommande IR sans fonction reconnue est ignorée
    assert.equal(store.integrations.get('integ-1').status, 'connected');
    assert.equal(store.deviceByName('Prise garage').availability, 'unavailable');
    assert.equal(store.deviceByName('Serrure').is_sensitive, true);
    assert.equal(store.deviceByName('Prise salon').state.energy, 0.125);
  });

  test('commande confirmée seulement après relecture de l\'état', async () => {
    const plug = store.deviceByName('Prise salon');
    const c = await cmd(plug, 'switch', true);
    assert.ok(await until(() => c.status === 'confirmed'), `statut ${c.status}`);
    assert.deepEqual(cloud.commands.at(-1), { id: 'plug1', commands: [{ code: 'switch_1', value: true }] });
    assert.equal(plug.state.switch, true);
  });

  test('couleur d\'une ampoule', async () => {
    const bulb = store.deviceByName('Ampoule bureau');
    const c = await cmd(bulb, 'color', '#3F51B5');
    assert.ok(await until(() => c.status === 'confirmed'), `statut ${c.status}`);
    assert.equal(cloud.devices.get('bulb1').status.find((s) => s.code === 'work_mode').value, 'colour');
  });

  test('rideau : bouton Stop envoyé au moteur et confirmé', async () => {
    const curtain = store.deviceByName('Rideau chambre');
    assert.equal(curtain.state.cover_control, 'close');
    const c = await cmd(curtain, 'cover_control', 'stop');
    assert.ok(await until(() => c.status === 'confirmed'), `statut ${c.status}`);
    assert.deepEqual(cloud.commands.at(-1), { id: 'curtain2', commands: [{ code: 'control', value: 'stop' }] });
  });

  test('rideau : action non proposée par le moteur refusée', async () => {
    const c = await cmd(store.deviceByName('Rideau salon'), 'cover_control', 'continue');
    assert.ok(await until(() => !['pending', 'sent'].includes(c.status)));
    assert.equal(c.status, 'rejected');
    assert.equal(cloud.commands.length, 0);
  });

  test('appareil hors ligne : échec immédiat, pas d\'appel au cloud', async () => {
    const c = await cmd(store.deviceByName('Prise garage'), 'switch', true);
    assert.ok(await until(() => !['pending', 'sent'].includes(c.status)));
    assert.equal(c.status, 'failed');
    assert.match(c.error, /hors ligne/);
    assert.equal(cloud.commands.length, 0);
  });

  test('appareil qui ne change pas d\'état : timeout, pas de faux succès', async () => {
    cloud.ignoreCommands = true;
    const c = await cmd(store.deviceByName('Prise salon'), 'switch', true);
    assert.ok(await until(() => c.status === 'timeout'), `statut ${c.status}`);
  });

  test('changement fait dans Smart Life : remonte par interrogation', async () => {
    const multi = store.deviceByName('Multiprise');
    cloud.setStatus('multi1', 'switch_2', true);
    assert.ok(await until(() => multi.state.switch_2 === true));
  });

  test('nouvel appareil ajouté dans Smart Life : importé automatiquement', async () => {
    cloud.devices.set('plug2', { ...structuredClone(demo('plug1')), id: 'plug2', name: 'Prise cuisine' });
    assert.ok(await until(() => store.deviceByName('Prise cuisine')));
  });

  const pairing = (extra = {}) => {
    const req = { id: `pair-${store.pairings.length}`, home_id: 'home-1', kind: 'scan', name: null, room_id: null, lock_data: null, status: 'pending', created_at: new Date().toISOString(), ...extra };
    store.pairings.push(req);
    return req;
  };

  test('ajout depuis l\'application : nouvel appareil Smart Life repéré, nommé et rangé', async () => {
    const req = pairing({ name: 'Prise salon', room_id: 'room-salon' });
    cloud.devices.set('plug3', { ...structuredClone(demo('plug1')), id: 'plug3', name: 'Smart Plug' });
    assert.ok(await until(() => req.status === 'done'), `statut ${req.status}`);
    const dev = store.devices.get(req.device_id);
    assert.equal(dev.name, 'Prise salon');
    assert.equal(dev.room_id, 'room-salon');
  });

  test('ajout depuis l\'application : rien de nouveau, échec clair après le délai', async () => {
    bridge.config.pairingScanMs = 150;
    bridge.config.pairingRetryMs = 30;
    const req = pairing();
    assert.ok(await until(() => req.status === 'failed'), `statut ${req.status}`);
    assert.match(req.error, /Aucun nouvel appareil/);
    assert.equal(req.device_id, null);
  });

  test('ajout depuis l\'application : un appareil déjà là n\'est pas repris', async () => {
    bridge.config.pairingScanMs = 150;
    bridge.config.pairingRetryMs = 30;
    const req = pairing({ created_at: new Date(Date.now() + 1000).toISOString() });
    assert.ok(await until(() => req.status === 'failed'));
  });

  test('cloud injoignable puis rétabli : statut de l\'intégration suivi', async () => {
    const realFetch = cloud.fetch;
    adapter.client.fetchImpl = async () => { throw new Error('réseau coupé'); };
    assert.ok(await until(() => store.integrations.get('integ-1').status === 'error'));
    adapter.client.fetchImpl = realFetch;
    assert.ok(await until(() => store.integrations.get('integ-1').status === 'connected'));
  });
});

test('ajout depuis l\'application : relecture immédiate sans attendre l\'interrogation', async () => {
  const cloud = new FakeTuyaCloud();
  const store = new MemoryStore();
  const client = new TuyaClient({ accessId: ACCESS_ID, accessSecret: ACCESS_SECRET, baseUrl: 'https://openapi.tuyaeu.com', fetchImpl: cloud.fetch });
  const bridge = new Bridge({
    store,
    adapter: new TuyaCloudAdapter({ client, pollMs: 60_000, confirmPollMs: 20 }), // interrogation normale : 1 min
    config: { integrationId: 'integ-1', commandTimeoutMs: 400, pendingMaxAgeMs: 30_000, pollIntervalMs: 30, automationRefreshMs: 60_000, runAutomations: false, pairingRetryMs: 50 },
  });
  await bridge.start();
  try {
    const req = { id: 'pair-x', home_id: 'home-1', kind: 'scan', name: null, room_id: null, status: 'pending', created_at: new Date().toISOString() };
    store.pairings.push(req);
    cloud.devices.set('plug4', { ...structuredClone(demo('plug1')), id: 'plug4', name: 'Prise bureau' });
    assert.ok(await until(() => req.status === 'done', 1500), `statut ${req.status}`);
    assert.equal(store.devices.get(req.device_id).name, 'Prise bureau');
  } finally {
    await bridge.stop();
  }
});

test('configuration Tuya Cloud', () => {
  const base = { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'k', INTEGRATION_ID: 'i', ADAPTER: 'tuya_cloud' };
  assert.throws(() => loadConfig(base), /TUYA_ACCESS_ID/);
  const c = loadConfig({ ...base, TUYA_ACCESS_ID: ' id ', TUYA_ACCESS_SECRET: 's' });
  assert.equal(c.tuyaAccessId, 'id');
  assert.equal(c.tuyaBaseUrl, 'https://openapi.tuyaeu.com');
  assert.equal(c.tuyaPollMs, 30_000);
  assert.equal(c.haToken, null);
  assert.throws(() => loadConfig({ ...base, TUYA_ACCESS_ID: 'id', TUYA_ACCESS_SECRET: 's', TUYA_REGION: 'mars' }), /TUYA_REGION/);
});

test('assistant de configuration : .env Tuya relu à l\'identique', async () => {
  const { parseEnv, renderEnv } = await import('../src/setup.js');
  const v = { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'k', INTEGRATION_ID: 'i', TUYA_ACCESS_ID: 'a', TUYA_ACCESS_SECRET: 's', TUYA_REGION: 'eu' };
  const env = parseEnv(renderEnv(v).replace(/\n/g, '\r\n'));
  const c = loadConfig(env);
  assert.equal(c.adapter, 'tuya_cloud');
  assert.equal(c.tuyaAccessSecret, 's');
  assert.equal(c.integrationId, 'i');
});
