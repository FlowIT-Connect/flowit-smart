import assert from 'node:assert/strict';
import { afterEach, beforeEach, test } from 'node:test';

import { FakeHomeAssistant } from '../src/adapters/fake_home_assistant.js';
import { HomeAssistantAdapter } from '../src/adapters/home_assistant.js';
import { activeModes, closedCovers, conditionsHold, exceptionHolds, isNight, localTime, modeTriggerFired, presencePlan, sunTriggerDue } from '../src/automations.js';
import { Bridge } from '../src/bridge.js';
import { setLogLevel } from '../src/log.js';
import { fetchWeather } from '../src/weather.js';
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

test('lecture Open-Meteo : vent, rafales, soleil en heure locale', async () => {
  let url = '';
  const fetchImpl = async (u) => {
    url = u;
    return {
      ok: true,
      json: async () => ({
        utc_offset_seconds: 3600,
        current: { time: '2026-11-01T15:00', temperature_2m: 18.4, precipitation: 0.2, wind_speed_10m: 86.3, wind_gusts_10m: 104, is_day: 1 },
        daily: { sunrise: ['2026-11-01T07:02'], sunset: ['2026-11-01T17:41'] },
      }),
    };
  };
  const w = await fetchWeather({ latitude: 36.7538, longitude: 3.0588, fetchImpl });
  assert.match(url, /^https:\/\/api\.open-meteo\.com\/v1\/forecast\?latitude=36\.7538/);
  assert.match(url, /wind_speed_unit=kmh/);
  assert.equal(w.wind_speed, 86.3);
  assert.equal(w.wind_gust, 104);
  assert.equal(w.is_day, true);
  assert.equal(w.sunset.toISOString(), '2026-11-01T16:41:00.000Z');
  const pro = await fetchWeather({ latitude: 1, longitude: 2, apiKey: 'cle', fetchImpl });
  assert.match(url, /^https:\/\/customer-api\.open-meteo\.com\/.*apikey=cle/);
  assert.equal(pro.source, 'open-meteo-pro');
});

test('conditions météo, soleil, SAUF SI et volets fermés', () => {
  const weather = { wind_speed: 90, sunrise: new Date('2026-11-01T06:02:00Z'), sunset: new Date('2026-11-01T16:41:00Z') };
  const now = localTime(new Date('2026-11-01T18:00:00Z'), 'Africa/Algiers');
  const ctx = { weather, date: new Date('2026-11-01T18:00:00Z') };
  assert.equal(isNight(ctx, ctx.date), true);
  assert.ok(conditionsHold([{ type: 'weather', metric: 'wind_speed', op: 'gt', value: 80 }, { type: 'sun', is: 'night' }], {}, now, ctx));
  assert.ok(!conditionsHold([{ type: 'sun', is: 'day' }], {}, now, ctx));
  assert.ok(!conditionsHold([{ type: 'weather', metric: 'wind_speed', op: 'gt', value: 80 }], {}, now, {}), 'sans météo : prudence');
  assert.ok(exceptionHolds([{ type: 'device_state', device_id: 'f', capability_key: 'contact', op: 'eq', value: false }], { f: { contact: false } }, now, ctx));
  assert.ok(!exceptionHolds([], {}, now, ctx));
  const at = localTime(new Date('2026-11-01T16:26:00Z'), 'Africa/Algiers');
  assert.ok(sunTriggerDue({ type: 'sun', event: 'sunset', offset_minutes: -15 }, at, weather, 'Africa/Algiers'));
  assert.ok(!sunTriggerDue({ type: 'sun', event: 'sunrise' }, at, weather, 'Africa/Algiers'));
  assert.equal(closedCovers([{ capability_key: 'cover_position', value: 0 }, { capability_key: 'cover_control', value: 'close' }, { capability_key: 'switch', value: true }]), 2);
});

let fake, store, bridge, weather, clockNow;

beforeEach(async () => {
  fake = new FakeHomeAssistant(undefined, { latencyMs: 20 });
  store = new MemoryStore();
  Object.assign(store.homes.get('home-1'), { latitude: 36.75, longitude: 3.06 });
  weather = { wind_speed: 30, wind_gust: 40, temperature: 18, is_day: true, observed_at: new Date() };
  clockNow = null;
  const adapter = new HomeAssistantAdapter({ url: 'http://ha.local:8123', token: 'simulateur', wsFactory: () => fake.socket() });
  bridge = new Bridge({
    store,
    adapter,
    clock: () => clockNow ?? new Date(),
    weatherFetcher: async () => ({ ...weather }),
    config: { integrationId: 'integ-1', commandTimeoutMs: 300, pendingMaxAgeMs: 30_000, pollIntervalMs: 50, automationRefreshMs: 60_000, runAutomations: true, weather: false, followUpRetryMs: 40 },
  });
  await bridge.start();
});

afterEach(async () => {
  await bridge.stop();
});

function windRule(extra = {}) {
  const volet = store.deviceByName('Volet salon');
  return {
    id: 'w1', home_id: 'home-1', name: 'Vents forts', enabled: true, run_locally: true, priority: 'security',
    trigger: { type: 'weather', metric: 'wind_speed', op: 'gt', value: 80, for_minutes: 2 },
    conditions: [],
    exceptions: [],
    actions: [{ device_id: volet.id, capability_key: 'cover_position', value: 0 }],
    follow_up: { after_minutes: 0, actions: [{ device_id: volet.id, capability_key: 'cover_position', value: 100 }], conditions: [{ type: 'weather', metric: 'wind_speed', op: 'lt', value: 50 }] },
    ...extra,
  };
}

test('vent fort confirmé après le délai : volets fermés, notifications, historique, réouverture quand le vent retombe', async () => {
  store.automations.push(windRule());
  await bridge.refreshAutomations();
  const volet = store.deviceByName('Volet salon');
  const t0 = Date.now();
  clockNow = new Date(t0);
  weather.wind_speed = 92;
  weather.wind_gust = 110;
  await bridge.refreshWeather();
  assert.equal(store.commands.length, 0, 'pas avant la fin du délai de confirmation');
  clockNow = new Date(t0 + 60_000);
  await bridge.refreshWeather();
  assert.equal(store.commands.length, 0);
  clockNow = new Date(t0 + 125_000);
  await bridge.refreshWeather();
  assert.ok(await until(() => volet.state.cover_position === 0), 'volet fermé');
  assert.deepEqual(store.notifications.map((n) => n.type), ['high_wind', 'shutters_auto_closed']);
  assert.deepEqual(store.notifications[0].data, { wind: 92, gust: 110 });
  assert.equal(store.automationRuns[0].status, 'success');
  assert.equal(store.automationRuns[0].details.weather.wind_speed, 92);
  assert.ok(store.weatherReadings.length >= 3);

  // Encore du vent : une seule exécution, et le PUIS attend.
  clockNow = new Date(t0 + 400_000);
  await bridge.refreshWeather();
  await sleep(150);
  assert.equal(store.commands.filter((c) => c.automation_id === 'w1').length, 1);
  weather.wind_speed = 35;
  await bridge.refreshWeather();
  assert.ok(await until(() => volet.state.cover_position === 100), 'volet rouvert après la tempête');
  assert.equal(store.automationRuns.at(-1).phase, 'follow_up');
});

test('SAUF SI : fenêtre ouverte, rien n\'est fermé', async () => {
  const porte = store.deviceByName('Porte d\'entrée');
  store.automations.push(windRule({ trigger: { type: 'weather', metric: 'wind_speed', op: 'gt', value: 80 }, exceptions: [{ type: 'device_state', device_id: porte.id, capability_key: 'contact', op: 'eq', value: false }] }));
  await bridge.refreshAutomations();
  fake.setState('binary_sensor.porte_entree', 'on');
  assert.ok(await until(() => porte.state.contact === false));
  weather.wind_speed = 95;
  await bridge.refreshWeather();
  assert.equal(store.commands.length, 0);
  assert.equal(store.automationRuns[0].status, 'skipped');
});

test('détecteur de présence : lumière allumée, éteinte après le délai sans mouvement, délai relancé à chaque passage', async () => {
  const motion = store.deviceByName('Détecteur couloir');
  const strip = store.deviceByName('Ruban LED TV');
  store.automations.push({
    id: 'p1', home_id: 'home-1', name: 'Couloir', enabled: true, run_locally: true,
    trigger: { type: 'device_state', device_id: motion.id, capability_key: 'motion', op: 'eq', value: true },
    conditions: [],
    actions: [{ device_id: strip.id, capability_key: 'switch', value: true }],
    follow_up: { after_minutes: 0, restart_on_trigger: true, actions: [{ device_id: strip.id, capability_key: 'switch', value: false }], conditions: [{ type: 'device_state', device_id: motion.id, capability_key: 'motion', op: 'eq', value: false }] },
  });
  await bridge.refreshAutomations();
  fake.setState('binary_sensor.couloir_motion', 'on');
  assert.ok(await until(() => strip.state.switch === true), 'lumière allumée');
  await sleep(200);
  assert.equal(strip.state.switch, true, 'reste allumée tant qu\'il y a du mouvement');
  fake.setState('binary_sensor.couloir_motion', 'off');
  assert.ok(await until(() => strip.state.switch === false), 'éteinte quand plus personne');
});

test('coupe-circuit : 30 exécutions par heure au plus', async () => {
  const plug = store.deviceByName('Prise café');
  const a = { id: 'l1', home_id: 'home-1', name: 'Boucle', enabled: true, run_locally: true, trigger: { type: 'manual' }, conditions: [], actions: [{ device_id: plug.id, capability_key: 'switch', value: true }] };
  const t0 = Date.now();
  const now = localTime(new Date(t0), 'Africa/Algiers');
  for (let i = 0; i < 32; i++) {
    clockNow = new Date(t0 + i * 11_000);
    await bridge.runAutomation(a, now, `r${i}`);
  }
  assert.equal(store.commands.filter((c) => c.automation_id === 'l1').length, 30);
  assert.equal(store.automationRuns.filter((r) => r.status === 'skipped').length, 1);
});

test('modes : saison, vacances entre les dates, déclencheurs début / fin, plan de simulation', () => {
  const row = { season: 'summer', vacation: true, vacation_from: '2026-12-20T00:00:00Z', vacation_to: '2027-01-03T00:00:00Z' };
  assert.deepEqual(activeModes(row, new Date('2026-12-01T00:00:00Z')), ['summer']);
  assert.deepEqual(activeModes(row, new Date('2026-12-25T00:00:00Z')), ['summer', 'vacation']);
  assert.deepEqual(activeModes(null, new Date()), []);
  assert.ok(modeTriggerFired({ type: 'mode', mode: 'vacation' }, ['summer'], ['summer', 'vacation']));
  assert.ok(modeTriggerFired({ type: 'mode', mode: 'vacation', event: 'end' }, ['vacation'], []));
  assert.ok(!modeTriggerFired({ type: 'mode', mode: 'winter' }, [], ['summer']));
  const plan = presencePlan(['a', 'b'], 18 * 60, () => 0.5);
  for (const p of plan) {
    assert.ok(p.on >= 18 * 60 && p.on <= 22 * 60);
    assert.ok(p.off > p.on && p.off <= 23 * 60 + 30);
  }
  const ctx = { modes: ['vacation'] };
  assert.ok(conditionsHold([{ type: 'mode', mode: 'vacation' }], {}, localTime(new Date(), 'Africa/Algiers'), ctx));
});

test('vacances : simulation de présence le soir, tout éteint au retour ; déclencheur « départ en vacances »', async () => {
  const strip = store.deviceByName('Ruban LED TV');
  const plug = store.deviceByName('Prise café');
  store.automations.push({
    id: 'm1', home_id: 'home-1', name: 'Départ', enabled: true, run_locally: true,
    trigger: { type: 'mode', mode: 'vacation', event: 'start' }, conditions: [],
    actions: [{ device_id: plug.id, capability_key: 'switch', value: false }],
  });
  await bridge.refreshAutomations(); // premier relevé : aucun mode
  store.homeModes.set('home-1', { season: 'none', vacation: true, presence_simulation: true, simulation_devices: [strip.id] });
  // 19 h 10 à Alger, dans le futur : les commandes créées à l'heure réelle sont déjà dues.
  clockNow = new Date('2030-01-07T18:10:00Z');
  bridge.random = () => 0; // allumage dès le début de soirée
  await bridge.refreshAutomations();
  assert.ok(store.commands.some((c) => c.automation_id === 'm1'), 'déclencheur de départ exécuté');
  await bridge.tickPresenceSimulation();
  assert.ok(await until(() => strip.state.switch === true), 'lumière allumée par la simulation');
  store.homeModes.set('home-1', { season: 'none', vacation: false });
  await bridge.refreshAutomations();
  assert.ok(await until(() => strip.state.switch === false), 'éteinte au retour');
});
