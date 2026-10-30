import assert from 'node:assert/strict';
import { afterEach, beforeEach, test } from 'node:test';

import { FakeHomeAssistant } from '../src/adapters/fake_home_assistant.js';
import { HomeAssistantAdapter } from '../src/adapters/home_assistant.js';
import { Bridge } from '../src/bridge.js';
import { localTime } from '../src/automations.js';
import { setLogLevel } from '../src/log.js';
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

let fake, store, bridge, clockNow;

beforeEach(async () => {
  fake = new FakeHomeAssistant(undefined, { latencyMs: 30 });
  store = new MemoryStore();
  clockNow = null;
  const adapter = new HomeAssistantAdapter({ url: 'http://ha.local:8123', token: 'simulateur', wsFactory: () => fake.socket() });
  bridge = new Bridge({
    store,
    adapter,
    clock: () => clockNow ?? new Date(),
    config: { integrationId: 'integ-1', commandTimeoutMs: 300, pendingMaxAgeMs: 30_000, pollIntervalMs: 50, automationRefreshMs: 60_000, runAutomations: true },
  });
  await bridge.start();
});

afterEach(async () => {
  await bridge.stop();
});

const cmd = (device, capability_key, value, extra = {}) =>
  store.insertCommand({ home_id: 'home-1', device_id: device.id, capability_key, value, idempotency_key: Math.random().toString(), requested_by: 'u1', ...extra });

test('synchronisation : appareils, capacités, disponibilité, intégration connectée', () => {
  assert.equal(store.devices.size, 11);
  assert.equal(store.integrations.get('integ-1').status, 'connected');
  const lock = store.deviceByName('Serrure');
  assert.equal(lock.is_sensitive, true);
  assert.equal(store.deviceByName('Ampoule chevet').availability, 'unavailable');
  assert.equal(store.deviceByName('Plafonnier').protocol, 'zigbee');
  assert.deepEqual(store.caps(store.deviceByName('Thermostat').id).map((c) => c.capability_key), ['target_temperature', 'hvac_mode', 'current_temperature']);
});

test('commande confirmée seulement après retour d\'état réel', async () => {
  const plug = store.deviceByName('Prise café');
  const c = await cmd(plug, 'switch', true);
  assert.ok(await until(() => c.status === 'confirmed'), `statut ${c.status}`);
  assert.equal(fake.states.get('switch.prise_cafe').state, 'on');
  assert.ok(await until(() => plug.state.power === 1180), 'mesure de puissance mise à jour en temps réel');
  assert.equal(plug.state.switch, true);
});

test('appareil injoignable : délai dépassé, pas de faux succès', async () => {
  const bulb = store.deviceByName('Ampoule chevet');
  const c = await cmd(bulb, 'switch', true);
  assert.ok(await until(() => !['pending', 'sent'].includes(c.status)));
  assert.equal(c.status, 'failed');
  assert.match(c.error, /indisponible/);
});

test('aucun retour d\'état : timeout', async () => {
  const plug = store.deviceByName('Prise café');
  fake.latencyMs = 5_000; // l'appareil ne répond pas dans le délai (300 ms)
  const c = await cmd(plug, 'switch', true);
  assert.ok(await until(() => c.status === 'timeout'), `statut ${c.status}`);
});

test('serrure (sensible) : refusée sans appel à Home Assistant', async () => {
  const lock = store.deviceByName('Serrure');
  const c = await cmd(lock, 'lock', false);
  assert.ok(await until(() => c.status === 'rejected'));
  assert.equal(fake.calls.filter((x) => x.entityId.startsWith('lock.')).length, 0);
});

test('valeur hors limites ou capacité inconnue : refusée', async () => {
  const light = store.deviceByName('Plafonnier');
  const a = await cmd(light, 'brightness', 500);
  const b = await cmd(store.deviceByName('Prise café'), 'brightness', 50);
  assert.ok(await until(() => a.status === 'rejected' && b.status === 'rejected'));
  assert.equal(fake.calls.length, 0);
});

test('scène : actions exécutées dans l\'ordre, une à la fois', async () => {
  const light = store.deviceByName('Plafonnier');
  const cover = store.deviceByName('Volet salon');
  const first = await cmd(light, 'brightness', 20, { scene_run_id: 'run-1' });
  const second = await cmd(cover, 'cover_position', 40, { scene_run_id: 'run-1' });
  assert.ok(await until(() => first.status === 'confirmed' && second.status === 'confirmed'));
  assert.deepEqual(fake.calls.map((c) => c.entityId), ['light.salon_plafonnier', 'cover.volet_salon']);
  assert.ok(first.completed_at <= second.completed_at);
});

test('commande trop ancienne : expirée', async () => {
  const plug = store.deviceByName('Prise café');
  const c = await cmd(plug, 'switch', true, { not_before: new Date(Date.now() + 60_000).toISOString() });
  clockNow = new Date(Date.now() + 120_000);
  await bridge.sweepStale();
  assert.equal(c.status, 'timeout');
});

test('automatisation sur état : porte ouverte → ruban allumé (exécution locale)', async () => {
  const door = store.deviceByName('Porte d\'entrée');
  const strip = store.deviceByName('Ruban LED TV');
  store.automations.push({
    id: 'a1', home_id: 'home-1', name: 'Porte', enabled: true, run_locally: true,
    trigger: { type: 'device_state', device_id: door.id, capability_key: 'contact', op: 'eq', value: false },
    conditions: [],
    actions: [{ device_id: strip.id, capability_key: 'switch', value: true }],
  });
  await bridge.refreshAutomations();
  fake.setState('binary_sensor.porte_entree', 'on');
  assert.ok(await until(() => strip.state.switch === true), 'ruban allumé');
  const c = store.commands.find((x) => x.automation_id === 'a1');
  assert.equal(c.status, 'confirmed');
  assert.ok(store.events.some((e) => e.event_type === 'automation_run'));
  assert.ok(store.automations[0].last_run_at);
});

test('automatisation horaire avec condition fausse : pas d\'exécution', async () => {
  const plug = store.deviceByName('Prise café');
  clockNow = new Date('2026-10-26T05:45:00Z');
  const now = localTime(clockNow, 'Africa/Algiers');
  store.automations.push({
    id: 'a2', home_id: 'home-1', name: 'Café', enabled: true, run_locally: true,
    trigger: { type: 'time', at: now.hhmm, days: [now.weekday] },
    conditions: [{ type: 'device_state', device_id: plug.id, capability_key: 'switch', op: 'eq', value: true }],
    actions: [{ device_id: plug.id, capability_key: 'switch', value: true }],
  });
  store.automations.push({
    id: 'a3', home_id: 'home-1', name: 'Scène', enabled: true, run_locally: true,
    trigger: { type: 'time', at: now.hhmm, days: [now.weekday] },
    conditions: [],
    actions: [{ scene_id: 'scene-1' }],
  });
  await bridge.refreshAutomations();
  await bridge.tickTimeTriggers();
  await bridge.tickTimeTriggers(); // une seule exécution par minute
  assert.equal(store.commands.filter((c) => c.automation_id === 'a2').length, 0);
  assert.deepEqual(store.scenesExecuted, [{ sceneId: 'scene-1', automationId: 'a3' }]);
});

test('intégration désactivée : commandes refusées', async () => {
  store.integrations.get('integ-1').status = 'disabled';
  await bridge.refreshAutomations();
  const c = await cmd(store.deviceByName('Prise café'), 'switch', true);
  assert.ok(await until(() => c.status === 'rejected'));
  assert.match(c.error, /désactivée/);
});

test('limite d\'appareils : les appareils en trop attendent le déblocage puis arrivent seuls', async () => {
  store.devices.clear();
  store.bindings = [];
  store.deviceLimit = 5;
  assert.deepEqual(await bridge.syncInventory(), { waiting: 6 });
  assert.equal(store.devices.size, 5);
  assert.equal(store.waiting.get('home-1'), 6);
  assert.equal(store.integrations.get('integ-1').status, 'connected');
  store.deviceLimit = 20; // paiement confirmé
  assert.deepEqual(await bridge.syncInventory(), { waiting: 0 });
  assert.equal(store.devices.size, 11);
  assert.equal(store.waiting.get('home-1'), 0);
});
