import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { afterEach, beforeEach, describe, test } from 'node:test';

import { addYeedi, buildVacuumDevice, vacuumState, YeediClient } from '../src/adapters/yeedi.js';
import { Bridge } from '../src/bridge.js';
import { loadConfig } from '../src/config.js';
import { setLogLevel } from '../src/log.js';
import { validateValue } from '../src/validate.js';
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

/** Module « Solea Yeedi » simulé : même API HTTP que yeedi/src/server.js. */
class FakeYeediModule {
  constructor() {
    this.token = 'jeton-test';
    this.down = false;
    this.calls = [];
    this.robots = [{ id: 'E0001', name: 'Yeedi salon', model: 'yeedi 2 hybrid', online: true, state: { status: 'charging', battery: 92, suction: 'standard', error: null } }];
    this.fetch = async (url, init = {}) => {
      if (this.down) throw new TypeError('fetch failed');
      const u = new URL(url);
      this.calls.push({ method: init.method ?? 'GET', path: u.pathname, body: init.body ? JSON.parse(init.body) : null });
      if (init.headers?.authorization !== `Bearer ${this.token}`) return Response.json({ error: 'Jeton invalide' }, { status: 401 });
      if (u.pathname === '/robots') return Response.json(this.robots);
      const m = u.pathname.match(/^\/robots\/([^/]+)\/command$/);
      const robot = m && this.robots.find((r) => r.id === decodeURIComponent(m[1]));
      if (!robot) return Response.json({ status: 'failed', error: 'Robot inconnu' });
      const body = JSON.parse(init.body);
      if (body.suction) robot.state.suction = body.suction;
      else if (body.action === 'start') robot.state.status = 'cleaning';
      else if (body.action === 'charge') robot.state.status = 'returning';
      else if (body.action === 'pause') return Response.json({ status: 'timeout', error: 'Le robot n\'a pas confirmé' });
      return Response.json({ status: 'confirmed', robot });
    };
  }
}

class EmptyAdapter extends EventEmitter {
  async start() {}
  stop() {}
  devices() { return []; }
  snapshot() { return { state: {}, availability: 'unavailable' }; }
  async execute() { return { status: 'failed', error: 'aucun appareil' }; }
}

describe('Robots aspirateurs yeedi', () => {
  test('descripteur : actions, puissance, état et batterie', () => {
    const d = buildVacuumDevice({ id: 'E1', name: 'Robot', model: 'yeedi 2 hybrid' });
    assert.equal(d.externalId, 'yeedi:E1');
    assert.equal(d.protocol, 'wifi');
    assert.equal(d.model, '2 hybrid', 'marque retirée du modèle');
    assert.equal(d.isSensitive, false);
    const action = d.capabilities.find((c) => c.capability_key === 'vacuum_action');
    assert.equal(validateValue(action, 'start'), null);
    assert.equal(validateValue(action, 'charge'), null);
    assert.notEqual(validateValue(action, 'demonter'), null);
    assert.equal(validateValue(d.capabilities.find((c) => c.capability_key === 'suction'), 'max'), null);
    assert.notEqual(validateValue(d.capabilities.find((c) => c.capability_key === 'battery'), 50), null, 'batterie en lecture seule');
    assert.deepEqual(vacuumState({ state: { status: 'error', battery: 10, suction: null, error: 'Roue bloquée' } }), { vacuum_state: 'error', battery: 10, vacuum_error: 'Roue bloquée' });
  });

  test('configuration : YEEDI_URL active le module, le jeton est obligatoire', () => {
    const env = { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'k', INTEGRATION_ID: 'i', ADAPTER: 'simulator' };
    assert.equal(loadConfig(env).yeedi, null);
    assert.throws(() => loadConfig({ ...env, YEEDI_URL: 'http://127.0.0.1:8790' }), /YEEDI_TOKEN/);
    assert.deepEqual(loadConfig({ ...env, YEEDI_URL: 'http://127.0.0.1:8790', YEEDI_TOKEN: ' t ' }).yeedi, { url: 'http://127.0.0.1:8790', token: 't', pollMs: 15_000 });
  });

  describe('dans la passerelle', () => {
    let mod, store, bridge;

    beforeEach(async () => {
      mod = new FakeYeediModule();
      store = new MemoryStore();
      const client = new YeediClient({ url: 'http://127.0.0.1:8790/', token: mod.token, fetchImpl: mod.fetch });
      const adapter = addYeedi(new EmptyAdapter(), client, { pollMs: 40 });
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

    const cmd = (device, capability_key, value) =>
      store.insertCommand({ home_id: 'home-1', device_id: device.id, capability_key, value, idempotency_key: Math.random().toString(), requested_by: 'owner-1' });

    test('le robot apparaît avec son état', () => {
      const robot = store.deviceByName('Yeedi salon');
      assert.equal(robot.vendor, 'yeedi');
      assert.equal(robot.availability, 'available');
      assert.deepEqual(robot.state, { vacuum_state: 'charging', battery: 92, suction: 'standard' });
    });

    test('démarrer, puissance : confirmés et état mis à jour ; pause non confirmée', async () => {
      const robot = store.deviceByName('Yeedi salon');
      const start = await cmd(robot, 'vacuum_action', 'start');
      assert.ok(await until(() => start.status === 'confirmed'));
      assert.equal(store.devices.get(robot.id).state.vacuum_state, 'cleaning');
      assert.deepEqual(mod.calls.find((c) => c.method === 'POST').body, { action: 'start' });
      const speed = await cmd(robot, 'suction', 'max');
      assert.ok(await until(() => speed.status === 'confirmed'));
      assert.equal(store.devices.get(robot.id).state.suction, 'max');
      const pause = await cmd(robot, 'vacuum_action', 'pause');
      assert.ok(await until(() => pause.status === 'timeout'));
      const bad = await cmd(robot, 'vacuum_action', 'voler');
      assert.ok(await until(() => bad.status === 'rejected'));
    });

    test('module arrêté : robot hors ligne, puis de retour', async () => {
      const robot = store.deviceByName('Yeedi salon');
      mod.down = true;
      assert.ok(await until(() => store.devices.get(robot.id).availability === 'unavailable'));
      mod.down = false;
      assert.ok(await until(() => store.devices.get(robot.id).availability === 'available'));
    });

    test('robot déconnecté du Wi-Fi : indisponible', async () => {
      const robot = store.deviceByName('Yeedi salon');
      mod.robots[0].online = false;
      assert.ok(await until(() => store.devices.get(robot.id).availability === 'unavailable'));
    });
  });
});
