import assert from 'node:assert/strict';
import { test } from 'node:test';

import { demoHome } from '../src/adapters/fake_home_assistant.js';
import { buildInventory, deviceSnapshot, entityCapabilities, rgbToHex, serviceCall, stateMatches } from '../src/adapters/ha_mapping.js';

const s = (entity_id, state, attributes = {}) => ({ entity_id, state, attributes });
const keys = (caps) => caps.map((c) => c.key);

test('lumière : capacités selon les modes réellement supportés', () => {
  assert.deepEqual(keys(entityCapabilities(s('light.a', 'on', { supported_color_modes: ['onoff'] }))), ['switch']);
  assert.deepEqual(keys(entityCapabilities(s('light.b', 'on', { supported_color_modes: ['brightness'] }))), ['switch', 'brightness']);
  assert.deepEqual(keys(entityCapabilities(s('light.c', 'on', { supported_color_modes: ['color_temp', 'hs'] }))), ['switch', 'brightness', 'color_temp', 'color']);
});

test('volet sans position : ouverture/fermeture uniquement', () => {
  const [cap] = entityCapabilities(s('cover.v', 'closed', { supported_features: 3 }));
  assert.equal(cap.metadata.step, 100);
  assert.equal(cap.read(s('cover.v', 'closed')), 0);
});

test('capteur de porte : contact vrai = fermé', () => {
  const [cap] = entityCapabilities(s('binary_sensor.p', 'on', { device_class: 'door' }));
  assert.equal(cap.key, 'contact');
  assert.equal(cap.read(s('binary_sensor.p', 'on')), false);
  assert.equal(cap.read(s('binary_sensor.p', 'off')), true);
});

test('capteur sans classe connue : ignoré (pas de fonction supposée)', () => {
  assert.deepEqual(entityCapabilities(s('sensor.x', '12', { unit_of_measurement: 'dB' })), []);
  assert.deepEqual(entityCapabilities(s('media_player.tv', 'on')), []);
});

test('inventaire : regroupement par appareil, protocole, serrure sensible, doublons suffixés', () => {
  const { states, devices, entities } = demoHome();
  const inv = buildInventory(states, entities, devices);
  const byName = Object.fromEntries(inv.map((d) => [d.name, d]));
  assert.equal(inv.length, 11);
  assert.deepEqual(byName['Prise café'].capabilities.map((c) => c.capability_key), ['switch', 'power']);
  assert.equal(byName['Plafonnier'].protocol, 'zigbee');
  assert.equal(byName['Ruban LED TV'].connectionSource, 'cloud');
  assert.equal(byName['Serrure'].isSensitive, true);

  const twin = buildInventory(
    [s('switch.r1', 'on'), s('switch.r2', 'off')],
    [{ entity_id: 'switch.r1', device_id: 'd' }, { entity_id: 'switch.r2', device_id: 'd' }],
    [{ id: 'd', name: 'Double relais' }],
  );
  assert.deepEqual(twin[0].capabilities.map((c) => c.capability_key), ['switch', 'switch_2']);
});

test('inventaire : entités de diagnostic et désactivées exclues, filtre appliqué', () => {
  const inv = buildInventory(
    [s('switch.a', 'on'), s('switch.b', 'on'), s('light.c', 'on', { supported_color_modes: ['onoff'] })],
    [{ entity_id: 'switch.a', entity_category: 'config' }, { entity_id: 'switch.b', disabled_by: 'user' }],
    [],
    /^light\./,
  );
  assert.deepEqual(inv.map((d) => d.externalId), ['entity:light.c']);
});

test('disponibilité : indisponible distinct de éteint', () => {
  const { states, devices, entities } = demoHome();
  const inv = buildInventory(states, entities, devices);
  const map = new Map(states.map((x) => [x.entity_id, x]));
  const bulb = inv.find((d) => d.name === 'Ampoule chevet');
  assert.equal(deviceSnapshot(bulb, map).availability, 'unavailable');
  const plug = inv.find((d) => d.name === 'Prise café');
  assert.deepEqual(deviceSnapshot(plug, map), { state: { switch: false, power: 0 }, availability: 'available' });
});

test('appels de service et confirmation', () => {
  const entry = { entityId: 'light.a', base: 'brightness', read: (x) => Math.round((x.attributes.brightness / 255) * 100) };
  assert.deepEqual(serviceCall(entry, 40), { domain: 'light', service: 'turn_on', target: { entity_id: 'light.a' }, data: { brightness_pct: 40 } });
  assert.equal(stateMatches(entry, s('light.a', 'on', { brightness: 102 }), 40), true);
  assert.equal(stateMatches(entry, s('light.a', 'on', { brightness: 200 }), 40), false);
  assert.equal(serviceCall({ entityId: 'lock.x', base: 'lock' }, false), null, 'serrure jamais pilotée');
  assert.equal(serviceCall({ entityId: 'cover.v', base: 'cover_position' }, 100).service, 'open_cover');
  assert.equal(rgbToHex([255, 196, 107]), '#FFC46B');
});
