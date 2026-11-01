import assert from 'node:assert/strict';
import { afterEach, beforeEach, test } from 'node:test';

import { FakeHomeAssistant } from '../src/adapters/fake_home_assistant.js';
import { HomeAssistantAdapter } from '../src/adapters/home_assistant.js';
import { Bridge } from '../src/bridge.js';
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

let fake, store, bridge, clockNow = null;

beforeEach(async () => {
  fake = new FakeHomeAssistant(undefined, { latencyMs: 10 });
  store = new MemoryStore();
  const adapter = new HomeAssistantAdapter({ url: 'http://ha.local:8123', token: 'simulateur', wsFactory: () => fake.socket() });
  bridge = new Bridge({
    store,
    adapter,
    clock: () => clockNow ?? new Date(),
    config: { integrationId: 'integ-1', commandTimeoutMs: 300, pendingMaxAgeMs: 30_000, pollIntervalMs: 50, automationRefreshMs: 60_000, runAutomations: true, runTimeTriggers: false },
  });
  await bridge.start();
});

afterEach(async () => {
  await bridge.stop();
});

test('ambiance par pièce : programme appliqué une fois, Absence pour la maison, réglage manuel respecté', async () => {
  const thermo = store.deviceByName('Thermostat');
  store.climateZones.push({
    id: 'z1', home_id: 'home-1', room_id: 'r1', enabled: true, devices: [thermo.id],
    schedule: [{ days: [1, 2, 3, 4, 5, 6, 7], at: '06:00', preset: 'comfort' }, { days: [1, 2, 3, 4, 5, 6, 7], at: '22:00', preset: 'sleep' }],
  });
  store.homeModes.set('home-1', { season: 'winter', vacation: false });
  await bridge.refreshModes();
  // Lundi 7 janvier 2030, 23 h à Alger : Nuit (18 °C par défaut).
  clockNow = new Date('2030-01-07T22:00:00Z');
  await bridge.tickClimate();
  assert.ok(await until(() => thermo.state.target_temperature === 18), `consigne ${thermo.state.target_temperature}`);
  assert.equal(store.climateZones[0].active_preset, 'sleep');
  assert.equal(store.climateZones[0].active_source, 'schedule');

  // Réglage manuel : la minute suivante ne le change pas (ambiance inchangée).
  await store.insertCommand({ home_id: 'home-1', device_id: thermo.id, capability_key: 'target_temperature', value: 20, idempotency_key: 'manuel', requested_by: 'u1' });
  assert.ok(await until(() => thermo.state.target_temperature === 20));
  clockNow = new Date('2030-01-07T22:01:00Z');
  await bridge.tickClimate();
  await sleep(100);
  assert.equal(thermo.state.target_temperature, 20, 'réglage manuel respecté');

  // Absence pour toute la maison : 16 °C.
  store.climateSettings.set('home-1', { home_id: 'home-1', enabled: true, presets: { away: { heat: 16, cool: 29 } }, home_preset: 'away', home_preset_until: null });
  clockNow = new Date('2030-01-07T22:02:00Z');
  await bridge.tickClimate();
  assert.ok(await until(() => thermo.state.target_temperature === 16), `consigne ${thermo.state.target_temperature}`);
  assert.equal(store.climateZones[0].active_source, 'home');

  // Chauffage désactivé pour le logement : plus rien n'est envoyé.
  store.climateSettings.get('home-1').enabled = false;
  store.climateSettings.get('home-1').home_preset = 'comfort';
  const before = store.commands.length;
  await bridge.tickClimate();
  assert.equal(store.commands.length, before);
});

test('fenêtre ouverte : coupure après le délai, une notification, reprise du mode et de l\'ambiance', async () => {
  const thermo = store.deviceByName('Thermostat');
  const porte = store.deviceByName('Porte d\'entrée');
  store.climateZones.push({
    id: 'z1', home_id: 'home-1', room_id: 'r1', enabled: true, devices: [thermo.id], windows: [porte.id], window_delay: 2,
    schedule: [{ days: [1, 2, 3, 4, 5, 6, 7], at: '06:00', preset: 'comfort' }],
  });
  clockNow = new Date('2030-01-07T10:00:00Z');
  await bridge.tickClimate();
  assert.ok(await until(() => thermo.state.target_temperature === 21));

  fake.setState('binary_sensor.porte_entree', 'on', { friendly_name: 'Porte d\'entrée', device_class: 'door' });
  assert.ok(await until(() => bridge.devices.get(porte.id).state.contact === false));
  await bridge.tickClimate();
  await sleep(100);
  assert.equal(thermo.state.hvac_mode, 'heat', 'pas encore coupé avant 2 minutes');
  assert.equal(store.notifications.filter((n) => n.type === 'window_open').length, 0);

  clockNow = new Date('2030-01-07T10:02:00Z');
  await bridge.tickClimate();
  assert.ok(await until(() => thermo.state.hvac_mode === 'off'), `mode ${thermo.state.hvac_mode}`);
  assert.equal(store.climateZones[0].active_window, true);
  assert.equal(store.notifications.filter((n) => n.type === 'window_open').length, 1);
  clockNow = new Date('2030-01-07T10:03:00Z');
  await bridge.tickClimate();
  assert.equal(store.notifications.filter((n) => n.type === 'window_open').length, 1, 'une seule notification');

  fake.setState('binary_sensor.porte_entree', 'off', { friendly_name: 'Porte d\'entrée', device_class: 'door' });
  assert.ok(await until(() => bridge.devices.get(porte.id).state.contact === true));
  clockNow = new Date('2030-01-07T10:04:00Z');
  await bridge.tickClimate();
  assert.ok(await until(() => thermo.state.hvac_mode === 'heat'), `mode ${thermo.state.hvac_mode}`);
  assert.equal(store.climateZones[0].active_window, false);
  assert.equal(thermo.state.target_temperature, 21);
});

test('préchauffage : la pièce est chauffée avant l\'heure prévue, puis le programme reprend', async () => {
  const thermo = store.deviceByName('Thermostat');
  store.climateZones.push({
    id: 'z1', home_id: 'home-1', room_id: 'r1', enabled: true, devices: [thermo.id],
    schedule: [{ days: [1, 2, 3, 4, 5, 6, 7], at: '07:00', preset: 'comfort' }, { days: [1, 2, 3, 4, 5, 6, 7], at: '22:00', preset: 'sleep' }],
  });
  fake.setState('climate.thermostat', 'heat', { current_temperature: 16 });
  assert.ok(await until(() => bridge.devices.get(thermo.id).state.current_temperature === 16));
  clockNow = new Date('2030-01-07T04:00:00Z'); // 5 h : Nuit
  await bridge.tickClimate();
  assert.ok(await until(() => thermo.state.target_temperature === 18), `consigne ${thermo.state.target_temperature}`);
  clockNow = new Date('2030-01-07T05:00:00Z'); // 6 h : 5 °C d'écart, on commence
  await bridge.tickClimate();
  assert.ok(await until(() => thermo.state.target_temperature === 21), `consigne ${thermo.state.target_temperature}`);
  assert.equal(store.climateZones[0].active_source, 'preheat');
  fake.setState('climate.thermostat', 'heat', { current_temperature: 20.5 });
  assert.ok(await until(() => bridge.devices.get(thermo.id).state.current_temperature === 20.5));
  clockNow = new Date('2030-01-07T05:40:00Z');
  await bridge.tickClimate();
  assert.equal(store.climateZones[0].active_source, 'preheat', 'le préchauffage continue');
  clockNow = new Date('2030-01-07T06:01:00Z');
  await bridge.tickClimate();
  assert.equal(store.climateZones[0].active_source, 'schedule');
  assert.equal(thermo.state.target_temperature, 21);

  // Préchauffage désactivé : rien avant l'heure.
  store.climateSettings.set('home-1', { home_id: 'home-1', enabled: true, preheat: false });
  fake.setState('climate.thermostat', 'heat', { current_temperature: 16 });
  clockNow = new Date('2030-01-08T05:00:00Z');
  await bridge.tickClimate();
  assert.equal(store.climateZones[0].active_preset, 'sleep');
});
