import assert from 'node:assert/strict';
import { test } from 'node:test';

import { entityCapabilities, serviceCall } from '../src/adapters/ha_mapping.js';
import { buildTuyaDevice, statusMap, tuyaSnapshot, tuyaStateMatches } from '../src/adapters/tuya_mapping.js';

const fn = (code, type, values = {}) => ({ code, type, values: JSON.stringify(values) });

// Climatiseur Tuya (catégorie kt) : marche, mode, consigne, ventilation, oscillation.
const AC_SPEC = {
  category: 'kt',
  functions: [
    fn('switch', 'Boolean'),
    fn('temp_set', 'Integer', { min: 16, max: 31, scale: 0, step: 1, unit: '℃' }),
    fn('mode', 'Enum', { range: ['cold', 'hot', 'wet', 'wind', 'auto'] }),
    fn('windspeed', 'Enum', { range: ['low', 'mid', 'high', 'auto'] }),
    fn('swing', 'Boolean'),
    fn('sleep', 'Boolean'),
  ],
  status: [fn('temp_current', 'Integer', { min: -20, max: 60, scale: 0 })],
};

test('Tuya clim : modes FlowIT, marche/arrêt dans le mode, ventilation traduite', () => {
  const d = buildTuyaDevice({ id: 'ac1', name: 'Clim salon' }, AC_SPEC);
  const keys = d.capabilities.map((c) => c.capability_key);
  for (const k of ['switch', 'target_temperature', 'current_temperature', 'hvac_mode', 'fan_mode', 'swing', 'sleep']) assert.ok(keys.includes(k), k);
  const mode = d.capabilities.find((c) => c.capability_key === 'hvac_mode');
  assert.deepEqual(mode.metadata.options, ['off', 'auto', 'cool', 'heat', 'dry', 'fan_only']);
  const fan = d.capabilities.find((c) => c.capability_key === 'fan_mode');
  assert.deepEqual(fan.metadata.options, ['auto', 'low', 'medium', 'high']);
  const temp = d.capabilities.find((c) => c.capability_key === 'target_temperature');
  assert.equal(temp.metadata.min, 16);
  assert.equal(temp.metadata.step, 1);

  const st = statusMap([{ code: 'switch', value: true }, { code: 'mode', value: 'cold' }, { code: 'temp_set', value: 24 }, { code: 'windspeed', value: 'mid' }, { code: 'temp_current', value: 29 }]);
  const snap = tuyaSnapshot(d, st, true).state;
  assert.equal(snap.hvac_mode, 'cool');
  assert.equal(snap.fan_mode, 'medium');
  assert.equal(snap.target_temperature, 24);
  assert.equal(snap.current_temperature, 29);

  assert.deepEqual(d.capMap.hvac_mode.write('heat'), [{ code: 'switch', value: true }, { code: 'mode', value: 'hot' }]);
  assert.deepEqual(d.capMap.hvac_mode.write('off'), [{ code: 'switch', value: false }]);
  assert.deepEqual(d.capMap.fan_mode.write('medium'), [{ code: 'windspeed', value: 'mid' }]);
  const off = statusMap([{ code: 'switch', value: false }, { code: 'mode', value: 'cold' }]);
  assert.equal(tuyaSnapshot(d, off, true).state.hvac_mode, 'off');
  assert.ok(tuyaStateMatches(d.capMap.hvac_mode, off, 'off'));
});

test('Tuya vanne de radiateur : programmes en ambiances, fenêtre ouverte, état de chauffe', () => {
  const d = buildTuyaDevice({ id: 'v1', name: 'Radiateur chambre' }, {
    category: 'wkf',
    functions: [
      fn('temp_set', 'Integer', { min: 50, max: 300, scale: 1, step: 5 }),
      fn('mode', 'Enum', { range: ['auto', 'manual', 'holiday', 'eco', 'comfort'] }),
      fn('window_check', 'Boolean'),
      fn('child_lock', 'Boolean'),
    ],
    status: [
      fn('temp_current', 'Integer', { scale: 1 }),
      fn('window_state', 'Enum', { range: ['close', 'open'] }),
      fn('work_state', 'Enum', { range: ['opened', 'closed'] }),
      fn('battery_percentage', 'Integer', {}),
    ],
  });
  const caps = Object.fromEntries(d.capabilities.map((c) => [c.capability_key, c]));
  assert.ok(!caps.hvac_mode, 'pas de marche/arrêt déclarée : pas de mode inventé');
  assert.deepEqual(caps.preset.metadata.options, ['schedule', 'manual', 'comfort', 'eco', 'away']);
  assert.equal(caps.target_temperature.metadata.max, 30);
  assert.ok(caps.window_detection && caps.child_lock && caps.window_open && caps.hvac_action && caps.battery);
  assert.ok(!caps.temperature, 'température mesurée non dupliquée');
  const st = statusMap([{ code: 'mode', value: 'holiday' }, { code: 'window_state', value: 'open' }, { code: 'work_state', value: 'opened' }, { code: 'temp_set', value: 215 }]);
  const snap = tuyaSnapshot(d, st, true).state;
  assert.equal(snap.preset, 'away');
  assert.equal(snap.window_open, true);
  assert.equal(snap.hvac_action, 'heating');
  assert.equal(snap.target_temperature, 21.5);
  assert.deepEqual(d.capMap.preset.write('away'), [{ code: 'mode', value: 'holiday' }]);
});

test('Tuya radiateur / chaudière avec simple marche : arrêt ou chauffe', () => {
  const d = buildTuyaDevice({ id: 'h1' }, { category: 'rs', functions: [fn('switch', 'Boolean'), fn('temp_set', 'Integer', { min: 30, max: 75, scale: 0, step: 1 })], status: [] });
  const mode = d.capabilities.find((c) => c.capability_key === 'hvac_mode');
  assert.deepEqual(mode.metadata.options, ['off', 'heat']);
  assert.deepEqual(d.capMap.hvac_mode.write('heat'), [{ code: 'switch', value: true }]);
});

test('Tuya lumière avec work_mode : aucune capacité de chauffage', () => {
  const d = buildTuyaDevice({ id: 'l1' }, { category: 'dj', functions: [fn('switch_led', 'Boolean'), fn('work_mode', 'Enum', { range: ['white', 'colour'] })], status: [] });
  assert.ok(!d.capabilities.some((c) => ['hvac_mode', 'preset'].includes(c.capability_key)));
});

test('Home Assistant clim : presets, ventilation, oscillation et appels de service', () => {
  const s = {
    entity_id: 'climate.salon', state: 'cool',
    attributes: { temperature: 24, current_temperature: 27, hvac_modes: ['off', 'cool', 'heat'], preset_modes: ['none', 'eco', 'away', 'sleep'], preset_mode: 'eco', fan_modes: ['auto', 'low', 'high'], fan_mode: 'auto', swing_modes: ['off', 'vertical'], swing_mode: 'off', hvac_action: 'cooling', current_humidity: 55 },
  };
  const caps = entityCapabilities(s);
  const by = Object.fromEntries(caps.map((c) => [c.key, c]));
  assert.equal(by.preset.read(s), 'eco');
  assert.equal(by.fan_mode.read(s), 'auto');
  assert.equal(by.swing_mode.read(s), 'off');
  assert.equal(by.hvac_action.read(s), 'cooling');
  assert.equal(by.humidity.read(s), 55);
  const entry = (base) => ({ entityId: 'climate.salon', base });
  assert.deepEqual(serviceCall(entry('preset'), 'away'), { domain: 'climate', service: 'set_preset_mode', target: { entity_id: 'climate.salon' }, data: { preset_mode: 'away' } });
  assert.equal(serviceCall(entry('fan_mode'), 'low').service, 'set_fan_mode');
  assert.equal(serviceCall(entry('swing_mode'), 'vertical').service, 'set_swing_mode');
});

test('Home Assistant chauffe-eau : consigne et mode sur le domaine water_heater', () => {
  const s = { entity_id: 'water_heater.chaudiere', state: 'eco', attributes: { temperature: 55, current_temperature: 52, min_temp: 35, max_temp: 70, operation_list: ['eco', 'performance', 'off'], operation_mode: 'eco', away_mode: 'off' } };
  const by = Object.fromEntries(entityCapabilities(s).map((c) => [c.key, c]));
  assert.equal(by.target_temperature.metadata.max, 70);
  assert.equal(by.preset.read(s), 'eco');
  assert.equal(by.away.read(s), false);
  const entry = (base) => ({ entityId: 'water_heater.chaudiere', base });
  assert.equal(serviceCall(entry('target_temperature'), 50).domain, 'water_heater');
  assert.deepEqual(serviceCall(entry('preset'), 'performance').data, { operation_mode: 'performance' });
  assert.equal(serviceCall(entry('away'), true).service, 'set_away_mode');
});

// ---------------------------------------------------------------- Ambiances par pièce
import { deviceCommands, effectivePreset, scheduledPreset, seasonMode } from '../src/climate.js';

const WEEK = [
  { days: [1, 2, 3, 4, 5], at: '06:30', preset: 'comfort' },
  { days: [1, 2, 3, 4, 5], at: '08:30', preset: 'eco' },
  { days: [1, 2, 3, 4, 5, 6, 7], at: '22:30', preset: 'sleep' },
  { days: [6, 7], at: '08:00', preset: 'comfort' },
];

test('programme : dernière plage commencée, y compris la veille', () => {
  assert.equal(scheduledPreset(WEEK, { weekday: 1, minutes: 7 * 60 }), 'comfort');
  assert.equal(scheduledPreset(WEEK, { weekday: 1, minutes: 12 * 60 }), 'eco');
  assert.equal(scheduledPreset(WEEK, { weekday: 1, minutes: 23 * 60 }), 'sleep');
  assert.equal(scheduledPreset(WEEK, { weekday: 2, minutes: 3 * 60 }), 'sleep', 'nuit commencée lundi soir');
  assert.equal(scheduledPreset(WEEK, { weekday: 6, minutes: 7 * 60 }), 'sleep', 'samedi avant 8 h');
  assert.equal(scheduledPreset([], { weekday: 1, minutes: 0 }), null);
});

test('priorités : pièce > maison > vacances > programme, dérogations expirées ignorées', () => {
  const now = new Date('2030-01-07T12:00:00Z');
  const local = { weekday: 1, minutes: 13 * 60 };
  const zone = { schedule: WEEK };
  assert.deepEqual(effectivePreset(zone, null, [], now, local), { preset: 'eco', source: 'schedule' });
  assert.deepEqual(effectivePreset(zone, null, ['vacation'], now, local), { preset: 'away', source: 'vacation' });
  const home = { home_preset: 'comfort', home_preset_until: '2030-01-08T00:00:00Z' };
  assert.deepEqual(effectivePreset(zone, home, ['vacation'], now, local), { preset: 'comfort', source: 'home' });
  const room = { ...zone, preset_override: 'sleep', override_until: null };
  assert.deepEqual(effectivePreset(room, home, [], now, local), { preset: 'sleep', source: 'room' });
  const expired = { ...zone, preset_override: 'sleep', override_until: '2030-01-07T11:00:00Z' };
  assert.equal(effectivePreset(expired, null, [], now, local).source, 'schedule');
  assert.deepEqual(effectivePreset({ schedule: [] }, null, [], now, local), { preset: 'comfort', source: 'default' });
  assert.equal(seasonMode(['winter']), 'heat');
  assert.equal(seasonMode(['summer', 'vacation']), 'cool');
  assert.equal(seasonMode([]), null);
});

const acDevice = (state) => ({
  state,
  caps: new Map([
    ['target_temperature', { writable: true, metadata: { min: 16, max: 30, step: 1 } }],
    ['hvac_mode', { writable: true, metadata: { options: ['off', 'cool', 'heat', 'dry'] } }],
  ]),
});

test('commandes : saison, consigne bornée et arrondie, rien si déjà réglé', () => {
  const presets = { comfort: { heat: 21.5, cool: 24 }, frost: { heat: 7, cool: null } };
  // Hiver : clim éteinte → chauffage à 22 (21,5 arrondi au pas de 1 °C).
  assert.deepEqual(deviceCommands(acDevice({ hvac_mode: 'off', target_temperature: 25 }), presets, 'comfort', 'heat').commands, [
    { capability_key: 'hvac_mode', value: 'heat' },
    { capability_key: 'target_temperature', value: 22 },
  ]);
  // Sans saison : la clim en froid reçoit la consigne « froid ».
  assert.deepEqual(deviceCommands(acDevice({ hvac_mode: 'cool', target_temperature: 26 }), presets, 'comfort', null).commands, [{ capability_key: 'target_temperature', value: 24 }]);
  // Déjà bon : aucune commande.
  assert.deepEqual(deviceCommands(acDevice({ hvac_mode: 'cool', target_temperature: 24 }), presets, 'comfort', 'cool').commands, []);
  // Hors-gel en été : pas de froid, la clim s'arrête.
  assert.deepEqual(deviceCommands(acDevice({ hvac_mode: 'cool', target_temperature: 24 }), presets, 'frost', 'cool').commands, [{ capability_key: 'hvac_mode', value: 'off' }]);
  // Hors-gel à 7 °C sur une clim limitée à 16 °C : bornée.
  assert.equal(deviceCommands(acDevice({ hvac_mode: 'heat' }), presets, 'frost', 'heat').target, 16);
  // Appareil sans consigne : ignoré.
  assert.deepEqual(deviceCommands({ state: {}, caps: new Map() }, presets, 'comfort', 'heat').commands, []);
});

test('fenêtre ouverte : détection, coupure par le mode ou en Hors-gel, reprise', async () => {
  const { openWindow, windowOffCommands, windowRestoreCommands } = await import('../src/climate.js');
  const devices = new Map([
    ['w1', { state: { contact: true } }],
    ['w2', { state: { contact: false } }],
    ['t1', { state: { window_open: true } }],
  ]);
  assert.equal(openWindow({ windows: ['w1'], devices: [] }, devices), null);
  assert.equal(openWindow({ windows: ['w1', 'w2'], devices: [] }, devices), 'w2');
  assert.equal(openWindow({ windows: [], devices: ['t1'] }, devices), 't1');
  assert.equal(openWindow({ devices: ['inconnu'] }, devices), null);

  const caps = (withMode) => new Map([
    ['target_temperature', { writable: true, metadata: { min: 5, max: 30, step: 0.5 } }],
    ...(withMode ? [['hvac_mode', { writable: true, metadata: { options: ['off', 'heat', 'cool'] } }]] : []),
  ]);
  assert.deepEqual(windowOffCommands({ caps: caps(true), state: { hvac_mode: 'cool' } }, null), [{ capability_key: 'hvac_mode', value: 'off' }]);
  assert.deepEqual(windowOffCommands({ caps: caps(true), state: { hvac_mode: 'off' } }, null), []);
  // Radiateur sans mode : consigne Hors-gel (jamais de coupure d'alimentation).
  assert.deepEqual(windowOffCommands({ caps: caps(false), state: { target_temperature: 20 } }, { frost: { heat: 8 } }), [{ capability_key: 'target_temperature', value: 8 }]);
  assert.deepEqual(windowOffCommands({ caps: new Map(), state: {} }, null), []);

  assert.deepEqual(windowRestoreCommands({ caps: caps(true), state: { hvac_mode: 'off' } }, 'cool', null), [{ capability_key: 'hvac_mode', value: 'cool' }]);
  assert.deepEqual(windowRestoreCommands({ caps: caps(true), state: { hvac_mode: 'off' } }, 'off', 'heat'), [{ capability_key: 'hvac_mode', value: 'heat' }]);
  assert.deepEqual(windowRestoreCommands({ caps: caps(true), state: { hvac_mode: 'heat' } }, 'cool', null), [], 'déjà remis à la main');
  assert.deepEqual(windowRestoreCommands({ caps: caps(true), state: { hvac_mode: 'off' } }, null, null), []);
});
