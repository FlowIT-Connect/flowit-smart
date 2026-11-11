import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { EventEmitter } from 'node:events';

import { addBroadlink, CLIMATE_PROFILES, climateCommand, irClimate, irDeviceName, IrProfileStore, parseProfile, profileCodes, profileUrl, readLearnedCommands, validateIrLearn } from '../src/adapters/broadlink.js';
import { FakeHomeAssistant } from '../src/adapters/fake_home_assistant.js';
import { addHomeAssistant, isHaExternalId } from '../src/adapters/ha_import.js';
import { HomeAssistantAdapter } from '../src/adapters/home_assistant.js';
import { validateValue } from '../src/validate.js';

const MAC = '34ea34aabbcc';

/** Box Home Assistant avec un RM4 Pro (télécommande + capteur), une prise Tuya et un appareil exporté par Solea. */
function rm4Home() {
  const s = (entity_id, state, attributes = {}) => ({ entity_id, state, attributes });
  return {
    states: [
      s('remote.rm4_pro', 'on', { friendly_name: 'RM4 Pro' }),
      s('sensor.rm4_pro_temperature', '24.5', { device_class: 'temperature', unit_of_measurement: '°C' }),
      s('sensor.rm4_pro_humidity', '61', { device_class: 'humidity', unit_of_measurement: '%' }),
      s('switch.prise_tuya', 'on'),
      s('switch.solea_prise', 'on'),
    ],
    entities: [
      { entity_id: 'remote.rm4_pro', platform: 'broadlink', unique_id: MAC, device_id: 'rm4' },
      { entity_id: 'sensor.rm4_pro_temperature', platform: 'broadlink', unique_id: `${MAC}-temperature`, device_id: 'rm4' },
      { entity_id: 'sensor.rm4_pro_humidity', platform: 'broadlink', unique_id: `${MAC}-humidity`, device_id: 'rm4' },
      { entity_id: 'switch.prise_tuya', platform: 'tuya', device_id: 'tuya1' },
      { entity_id: 'switch.solea_prise', platform: 'mqtt', device_id: 'solea1' },
    ],
    devices: [
      { id: 'rm4', name: 'RM4 Pro', manufacturer: 'Broadlink', model: 'RM4 Pro' },
      { id: 'tuya1', name: 'Prise' },
      { id: 'solea1', name: 'Prise (Solea)' },
    ],
  };
}

function codesDir(codes) {
  const dir = mkdtempSync(join(tmpdir(), 'ha-config-'));
  mkdirSync(join(dir, '.storage'));
  const write = (c) => writeFileSync(join(dir, '.storage', `broadlink_remote_${MAC}_codes`), JSON.stringify({ version: 1, key: 'x', data: c }));
  if (codes) write(codes);
  return { dir, write };
}

const CODES = {
  tv: { power: 'JgBQ', volume_up: 'JgBR', volume_down: 'JgBS' },
  clim: { off: 'A', cool_18: 'B', cool_22: 'C', cool_24: 'D', heat_22: 'E', heat_26: 'F', dry: 'G', swing: 'H' },
};

test('touches apprises lues dans le stockage de HA, codes jamais remontés', async () => {
  const { dir } = codesDir(CODES);
  const learned = await readLearnedCommands(join(dir, '.storage', `broadlink_remote_${MAC}_codes`));
  assert.deepEqual(learned, { tv: ['power', 'volume_down', 'volume_up'], clim: ['cool_18', 'cool_22', 'cool_24', 'dry', 'heat_22', 'heat_26', 'off', 'swing'] });
  assert.deepEqual(await readLearnedCommands(join(dir, 'absent')), {});
});

test('clim infrarouge : modes et températures déduits des noms de touches', () => {
  const c = irClimate(['off', 'cool_18', 'cool_22', 'heat_22', 'dry', 'swing']);
  assert.deepEqual(c.modes, ['cool', 'heat', 'dry']);
  assert.equal(c.min, 18);
  assert.equal(c.max, 22);
  assert.equal(irClimate(['power', 'volume_up']), null, 'une télé n\'est pas une clim');
  assert.equal(irClimate(['cool_22']), null, 'sans touche off, pas de thermostat');
  const cmds = ['off', 'cool_18', 'cool_22', 'cool_24', 'dry'];
  const cc = irClimate(cmds);
  assert.equal(climateCommand(cc, cmds, 'cool', 21), 'cool_22', 'température apprise la plus proche');
  assert.equal(climateCommand(cc, cmds, 'cool', 30), 'cool_24');
  assert.equal(climateCommand(cc, cmds, 'dry', 22), 'dry');
  assert.equal(climateCommand(cc, cmds, 'off', 22), 'off');
  assert.equal(climateCommand(cc, cmds, 'heat', 22), null);
  assert.equal(irDeviceName('tv'), 'Télé');
  assert.equal(irDeviceName('salon_deco'), 'Salon deco');
});

test('inventaire : Broadlink + une fiche par appareil appris, clim en thermostat', () => {
  const hub = { externalId: 'device:rm4', name: 'RM4 Pro', capabilities: [], capMap: { temperature: { entityId: 'sensor.t', base: 'temperature', read: () => 24 } } };
  const list = addBroadlink([hub], [{ entityId: 'remote.rm4_pro', uniqueId: MAC, deviceId: 'rm4' }], new Map([[MAC, { tv: ['power', 'volume_up'], clim: ['cool_22', 'dry', 'off', 'swing'] }]]), new Map());
  assert.deepEqual(list.map((d) => d.externalId), ['device:rm4', 'device:rm4:ir:tv', 'device:rm4:ir:clim']);
  const learn = hub.capabilities.find((c) => c.capability_key === 'ir_learn');
  assert.equal(learn.metadata.kind, 'ir_learn');
  assert.deepEqual(learn.metadata.learned.tv, ['power', 'volume_up']);
  const [, tv, clim] = list;
  assert.equal(tv.name, 'Télé');
  assert.deepEqual(tv.capabilities, [{ capability_key: 'ir_command', type: 'enum', writable: true, metadata: { options: ['power', 'volume_up'], kind: 'ir_command' } }]);
  assert.deepEqual(clim.capabilities.map((c) => c.capability_key), ['hvac_mode', 'target_temperature', 'current_temperature', 'ir_command']);
  assert.deepEqual(clim.capabilities[0].metadata.options, ['off', 'cool', 'dry']);
  assert.deepEqual(clim.capabilities[3].metadata.options, ['swing'], 'touches hors convention gardées en boutons');
});

test('apprentissage : demande validée (noms sûrs uniquement)', () => {
  const cap = { capability_key: 'ir_learn', type: 'string', writable: true, metadata: { kind: 'ir_learn' } };
  assert.equal(validateValue(cap, { device: 'tv', command: 'power' }), null);
  assert.equal(validateValue(cap, { device: 'clim', command: 'cool_22', action: 'delete' }), null);
  assert.match(validateValue(cap, { device: '../x', command: 'p' }), /appareil/);
  assert.match(validateValue(cap, { device: 'tv', command: '' }), /touche/);
  assert.match(validateValue(cap, { device: 'tv', command: 'p', code: 'JgB' }), /invalide/);
  assert.equal(validateIrLearn({ device: 'Télé salon', command: 'volume +' }), null);
});

function rm4Adapter(fake, dir, extra = {}) {
  return new HomeAssistantAdapter({
    url: 'http://ha', token: 'simulateur', wsFactory: () => fake.socket(), configDir: dir,
    platforms: new Set(['broadlink']), learnPollMs: 10, learnWaitMs: 300, ...extra,
  });
}

test('box HA : seul le Broadlink est repris, touches et clim pilotées, état supposé', async () => {
  const fake = new FakeHomeAssistant(rm4Home(), { latencyMs: 5 });
  const { dir } = codesDir(CODES);
  const ha = rm4Adapter(fake, dir);
  await ha.start();
  try {
    const ids = ha.devices().map((d) => d.externalId);
    assert.deepEqual(ids, ['device:rm4', 'device:rm4:ir:tv', 'device:rm4:ir:clim'], 'ni la prise Tuya ni l\'appareil exporté par Solea');
    const hub = ha.devices()[0];
    assert.deepEqual(hub.capabilities.map((c) => c.capability_key), ['temperature', 'humidity', 'ir_learn']);
    assert.deepEqual(ha.snapshot('device:rm4').state, { temperature: 24.5, humidity: 61 });

    assert.deepEqual(await ha.execute('device:rm4:ir:tv', 'ir_command', 'volume_up', 1000), { status: 'confirmed' });
    assert.deepEqual(fake.calls.at(-1), { domain: 'remote', service: 'send_command', entityId: 'remote.rm4_pro', data: { device: 'tv', command: 'volume_up' } });

    // Clim : consigne retenue tant qu'elle est éteinte, puis envoyée avec le mode.
    const before = fake.calls.length;
    assert.equal((await ha.execute('device:rm4:ir:clim', 'target_temperature', 24, 1000)).status, 'confirmed');
    assert.equal(fake.calls.length, before, 'rien envoyé, clim éteinte');
    assert.equal((await ha.execute('device:rm4:ir:clim', 'hvac_mode', 'cool', 1000)).status, 'confirmed');
    assert.equal(fake.calls.at(-1).data.command, 'cool_24');
    assert.equal((await ha.execute('device:rm4:ir:clim', 'target_temperature', 21, 1000)).status, 'confirmed');
    assert.equal(fake.calls.at(-1).data.command, 'cool_22');
    assert.deepEqual(ha.snapshot('device:rm4:ir:clim').state, { hvac_mode: 'cool', target_temperature: 21, current_temperature: 24.5 });
    assert.equal((await ha.execute('device:rm4:ir:clim', 'hvac_mode', 'off', 1000)).status, 'confirmed');
    assert.equal(fake.calls.at(-1).data.command, 'off');
    assert.equal((await ha.execute('device:rm4:ir:clim', 'hvac_mode', 'heat', 1000)).status, 'confirmed');
    assert.equal(fake.calls.at(-1).data.command, 'heat_22', 'chaud : température apprise la plus proche de 21');

    // Broadlink débranché : échec franc.
    fake.setState('remote.rm4_pro', 'unavailable');
    await new Promise((r) => setTimeout(r, 20));
    assert.equal(ha.snapshot('device:rm4:ir:tv').availability, 'unavailable');
    assert.equal((await ha.execute('device:rm4:ir:tv', 'ir_command', 'power', 1000)).status, 'failed');
  } finally {
    ha.stop();
  }
});

test('apprentissage : confirmé quand HA a enregistré la touche, nouvel appareil créé', async () => {
  const fake = new FakeHomeAssistant(rm4Home(), { latencyMs: 5 });
  const { dir, write } = codesDir(null); // rien d'appris
  const ha = rm4Adapter(fake, dir);
  await ha.start();
  try {
    assert.deepEqual(ha.devices().map((d) => d.externalId), ['device:rm4']);
    let inventories = 0;
    ha.on('inventory', () => inventories++);
    // HA enregistre la touche quelques instants après la fin de l'apprentissage.
    setTimeout(() => write({ decodeur: { power: 'JgB' } }), 60);
    const r = await ha.execute('device:rm4', 'ir_learn', { device: 'decodeur', command: 'power' }, 1000);
    assert.deepEqual(r, { status: 'confirmed' });
    const call = fake.calls.find((c) => c.service === 'learn_command');
    assert.deepEqual(call.data, { device: 'decodeur', command: 'power', command_type: 'ir' });
    assert.ok(inventories >= 1);
    const dec = ha.devices().find((d) => d.externalId === 'device:rm4:ir:decodeur');
    assert.equal(dec.name, 'Décodeur');

    // Aucune touche pressée : échec avec un conseil.
    const miss = await ha.execute('device:rm4', 'ir_learn', { device: 'decodeur', command: 'mute' }, 1000);
    assert.equal(miss.status, 'failed');
    assert.match(miss.error, /Aucun signal/);

    // Oublier une touche.
    setTimeout(() => write({}), 30);
    assert.deepEqual(await ha.execute('device:rm4', 'ir_learn', { device: 'decodeur', command: 'power', action: 'delete' }, 1000), { status: 'confirmed' });
    assert.equal(fake.calls.at(-1).service, 'delete_command');
    assert.deepEqual(ha.devices().map((d) => d.externalId), ['device:rm4']);
  } finally {
    ha.stop();
  }
});

test('passerelle Smart Life : appareils HA greffés, routage des commandes, pas de réexport', async () => {
  const fake = new FakeHomeAssistant(rm4Home(), { latencyMs: 5 });
  const { dir } = codesDir(CODES);
  const tuya = new EventEmitter();
  const tuyaCalls = [];
  Object.assign(tuya, {
    start: async () => {},
    stop: () => {},
    devices: () => [{ externalId: 'tuya:abc', name: 'Rideau', capabilities: [] }],
    snapshot: () => ({ state: { x: 1 }, availability: 'available' }),
    execute: async (...a) => {
      tuyaCalls.push(a);
      return { status: 'confirmed' };
    },
  });
  const ha = rm4Adapter(fake, dir);
  addHomeAssistant(tuya, ha);
  let inventory = 0;
  tuya.on('inventory', () => inventory++);
  await tuya.start();
  await new Promise((r) => setTimeout(r, 50));
  try {
    assert.ok(inventory >= 1);
    assert.deepEqual(tuya.devices().map((d) => d.externalId), ['tuya:abc', 'device:rm4', 'device:rm4:ir:tv', 'device:rm4:ir:clim']);
    await tuya.execute('tuya:abc', 'cover_control', 'open', 1000);
    assert.equal(tuyaCalls.length, 1);
    assert.equal((await tuya.execute('device:rm4:ir:tv', 'ir_command', 'power', 1000)).status, 'confirmed');
    assert.equal(tuyaCalls.length, 1);
    assert.deepEqual(tuya.snapshot('device:rm4').state, { temperature: 24.5, humidity: 61 });
    assert.equal(isHaExternalId('device:rm4:ir:tv'), true);
    assert.equal(isHaExternalId('tuya:abc'), false);
    assert.equal(isHaExternalId('yeedi:1'), false);
  } finally {
    tuya.stop();
  }
});

// Télécommande Hyundai HSE09PH5V de la bibliothèque (codes raccourcis).
const temps = (p) => Object.fromEntries([18, 24, 30].map((t) => [String(t), `${p}${t}AA==`]));
const HYUNDAI = {
  manufacturer: 'Hyundai', supportedModels: ['HSE09PH5V'], supportedController: 'Broadlink', commandsEncoding: 'Base64',
  minTemperature: 18, maxTemperature: 30, precision: 1,
  operationModes: ['heat', 'cool', 'heat_cool', 'dry', 'fan_only'], fanModes: ['low', 'mid', 'high', 'auto'],
  commands: {
    off: 'OFFAA==',
    cool: { low: temps('CL'), mid: temps('CM'), high: temps('CH'), auto: temps('CA') },
    heat: { low: temps('HL'), auto: temps('HA') },
    heat_cool: { auto: temps('XA') },
    dry: { auto: temps('DA') },
    fan_only: { low: temps('FL'), high: temps('FH') },
  },
};

function fakeFetch(json, calls = []) {
  return async (url) => {
    calls.push(url);
    return { ok: true, status: 200, text: async () => JSON.stringify(json) };
  };
}

test('bibliothèque de clims : index Broadlink, codes par réglage complet', () => {
  assert.ok(CLIMATE_PROFILES.size > 300);
  assert.deepEqual([...CLIMATE_PROFILES.values()].filter((p) => p.brand === 'Hyundai').map((p) => p.id), [2660, 2661, 2663, 2664]);
  assert.match(profileUrl(2660), /^https:\/\/raw\.githubusercontent\.com\/smartHomeHub\/SmartIR\/[0-9a-f]{40}\/codes\/climate\/2660\.json$/);
  const p = parseProfile(2660, HYUNDAI);
  assert.deepEqual(p.fans, ['low', 'mid', 'high', 'auto']);
  assert.deepEqual(profileCodes(p, { hvac_mode: 'cool', fan_mode: 'high', target_temperature: 25 }), ['CH24AA=='], 'température la plus proche');
  assert.deepEqual(profileCodes(p, { hvac_mode: 'heat', fan_mode: 'mid', target_temperature: 30 }), ['HL30AA=='], 'vitesse absente du mode : la première');
  assert.deepEqual(profileCodes(p, { hvac_mode: 'off', fan_mode: 'auto', target_temperature: 24 }), ['OFFAA==']);
  assert.equal(profileCodes(p, { hvac_mode: 'auto', fan_mode: 'auto', target_temperature: 24 }), null);
  assert.equal(parseProfile(2660, { ...HYUNDAI, supportedController: 'Xiaomi' }), null);
  assert.equal(parseProfile(1, HYUNDAI), null, 'hors index');
  assert.equal(validateIrLearn({ action: 'profile_test', profile: 2660 }), null);
  assert.equal(validateIrLearn({ action: 'profile_set', device: 'clim', profile: 2660 }), null);
  assert.equal(validateIrLearn({ action: 'profile_clear', device: 'clim' }), null);
  assert.match(validateIrLearn({ action: 'profile_set', device: 'clim', profile: 42 }), /inconnue/);
  assert.match(validateIrLearn({ action: 'profile_test', profile: 2660, mode: 'heat' }), /Essai/);
});

test('box HA : clim Hyundai choisie dans la bibliothèque, modes et vitesses sans apprentissage', async () => {
  const fake = new FakeHomeAssistant(rm4Home(), { latencyMs: 5 });
  const { dir } = codesDir({ clim: { off: 'A', cool_22: 'B', allume: 'C' } });
  const data = mkdtempSync(join(tmpdir(), 'ir-data-'));
  const fetched = [];
  const store = () => new IrProfileStore({ dir: data, fetchImpl: fakeFetch(HYUNDAI, fetched) });
  let ha = rm4Adapter(fake, dir, { irStore: store() });
  await ha.start();
  try {
    // Essai : froid 24°, vitesse auto, envoyé en code brut.
    assert.deepEqual(await ha.execute('device:rm4', 'ir_learn', { action: 'profile_test', profile: 2660 }, 1000), { status: 'confirmed' });
    assert.deepEqual(fake.calls.at(-1), { domain: 'remote', service: 'send_command', entityId: 'remote.rm4_pro', data: { command: ['b64:CA24AA=='] } });
    assert.equal(fetched.length, 1);

    assert.deepEqual(await ha.execute('device:rm4', 'ir_learn', { action: 'profile_set', device: 'clim', profile: 2660 }, 1000), { status: 'confirmed' });
    assert.equal(fetched.length, 1, 'codes téléchargés une seule fois');
    const clim = ha.devices().find((d) => d.externalId === 'device:rm4:ir:clim');
    assert.equal(clim.model, 'Hyundai HSE09PH5V');
    assert.deepEqual(clim.capabilities.map((c) => c.capability_key), ['hvac_mode', 'target_temperature', 'fan_mode', 'current_temperature', 'ir_command']);
    assert.deepEqual(clim.capabilities[0].metadata.options, ['off', 'heat', 'cool', 'heat_cool', 'dry', 'fan_only']);
    assert.deepEqual(clim.capabilities[2].metadata.options, ['low', 'mid', 'high', 'auto']);
    assert.deepEqual(clim.capabilities[4].metadata.options, ['allume'], 'touches apprises hors réglage gardées');
    assert.deepEqual(ha.devices()[0].capabilities.find((c) => c.capability_key === 'ir_learn').metadata.profiles, { clim: 2660 });

    const before = fake.calls.length;
    assert.equal((await ha.execute('device:rm4:ir:clim', 'fan_mode', 'high', 1000)).status, 'confirmed');
    assert.equal(fake.calls.length, before, 'clim éteinte : rien envoyé');
    assert.equal((await ha.execute('device:rm4:ir:clim', 'hvac_mode', 'cool', 1000)).status, 'confirmed');
    assert.deepEqual(fake.calls.at(-1).data, { command: ['b64:CH24AA=='] });
    assert.equal((await ha.execute('device:rm4:ir:clim', 'target_temperature', 18, 1000)).status, 'confirmed');
    assert.deepEqual(fake.calls.at(-1).data, { command: ['b64:CH18AA=='] });
    assert.deepEqual(ha.snapshot('device:rm4:ir:clim').state, { hvac_mode: 'cool', target_temperature: 18, fan_mode: 'high', current_temperature: 24.5 });
    assert.equal((await ha.execute('device:rm4:ir:clim', 'hvac_mode', 'off', 1000)).status, 'confirmed');
    assert.deepEqual(fake.calls.at(-1).data, { command: ['b64:OFFAA=='] });
  } finally {
    ha.stop();
  }

  // Redémarrage du module : le choix et les codes sont gardés sur la box, sans réseau.
  ha = rm4Adapter(fake, dir, { irStore: new IrProfileStore({ dir: data, fetchImpl: async () => { throw new Error('hors ligne'); } }) });
  await ha.start();
  try {
    const clim = ha.devices().find((d) => d.externalId === 'device:rm4:ir:clim');
    assert.ok(clim.capabilities.some((c) => c.capability_key === 'fan_mode'));
    assert.deepEqual(await ha.execute('device:rm4', 'ir_learn', { action: 'profile_clear', device: 'clim' }, 1000), { status: 'confirmed' });
    const back = ha.devices().find((d) => d.externalId === 'device:rm4:ir:clim');
    assert.ok(!back.capabilities.some((c) => c.capability_key === 'fan_mode'), 'retour aux touches apprises');
  } finally {
    ha.stop();
  }
});
