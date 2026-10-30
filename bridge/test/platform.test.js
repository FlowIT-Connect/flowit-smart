import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { afterEach, beforeEach, test } from 'node:test';

import { PlatformSupervisor } from '../src/platform.js';
import { INSTALLER_ONLY_MESSAGE } from '../src/bridge.js';
import { setLogLevel } from '../src/log.js';
import { MemoryStore } from './memory_store.js';

setLogLevel('error');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function until(fn, ms = 2000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (await fn()) return true;
    await sleep(10);
  }
  return false;
}

/** Compte installateur simulé : trois prises Wi-Fi. */
class FakeAccount extends EventEmitter {
  constructor() {
    super();
    this.state = new Map(['a', 'b', 'c'].map((k) => [`tuya:${k}`, false]));
    this.executed = [];
  }
  async start() { this.started = (this.started ?? 0) + 1; }
  stop() {}
  devices() {
    return [...this.state.keys()].map((id) => ({
      externalId: id,
      name: `Prise ${id.slice(5).toUpperCase()}`,
      vendor: 'Tuya',
      protocol: 'tuya',
      connectionSource: 'cloud',
      capabilities: [{ capability_key: 'switch', type: 'boolean', writable: true, metadata: {} }],
    }));
  }
  snapshot(id) { return { state: { switch: this.state.get(id) }, availability: 'available' }; }
  async execute(id, key, value) {
    this.executed.push(id);
    this.state.set(id, value);
    this.emit('device', id, this.snapshot(id));
    return { status: 'confirmed' };
  }
}

let store, account, platform;

beforeEach(async () => {
  store = new MemoryStore({ homeId: 'unused', integrationId: 'unused' });
  account = new FakeAccount();
  platform = new PlatformSupervisor({
    store,
    adapter: account,
    config: { commandTimeoutMs: 300, pendingMaxAgeMs: 30_000, pollIntervalMs: 30, automationRefreshMs: 60_000, runAutomations: false, platformRefreshMs: 60_000 },
  });
  await platform.start();
});

afterEach(async () => {
  await platform.stop();
});

const devicesOf = (homeId) => [...store.devices.values()].filter((d) => d.home_id === homeId);

test('inventaire inscrit, rien d\'installé tant que l\'exploitant n\'a pas attribué', () => {
  assert.equal(store.platformDevices.size, 3);
  assert.equal(store.devices.size, 0);
  assert.equal(account.started, 1);
});

test('attribution : chaque logement ne voit et ne pilote que ses appareils', async () => {
  store.assign('tuya:a', 'home-A');
  store.assign('tuya:b', 'home-A');
  store.assign('tuya:c', 'home-B');
  await platform.refresh();
  assert.deepEqual(devicesOf('home-A').map((d) => d.name).sort(), ['Prise A', 'Prise B']);
  assert.deepEqual(devicesOf('home-B').map((d) => d.name), ['Prise C']);
  assert.equal(platform.homes.size, 2);

  const c = devicesOf('home-B')[0];
  const cmd = await store.insertCommand({ home_id: 'home-B', device_id: c.id, capability_key: 'switch', value: true, idempotency_key: 'k1', requested_by: 'u1' });
  assert.ok(await until(() => cmd.status === 'confirmed'), `statut ${cmd.status}`);
  assert.deepEqual(account.executed, ['tuya:c']);
  assert.equal(store.devices.get(c.id).state.switch, true);

  // Commande déposée dans le logement A pour l'appareil du logement B : jamais exécutée.
  const intrus = await store.insertCommand({ home_id: 'home-A', device_id: c.id, capability_key: 'switch', value: false, idempotency_key: 'k2', requested_by: 'u1' });
  await sleep(150);
  assert.equal(intrus.status, 'pending');
  assert.deepEqual(account.executed, ['tuya:c']);
});

test('nouvel appareil attribué à un logement déjà servi : ajouté sans redémarrer', async () => {
  store.assign('tuya:a', 'home-A');
  await platform.refresh();
  const bridge = platform.homes.get('home-A').bridge;
  store.assign('tuya:b', 'home-A');
  await platform.refresh();
  assert.ok(await until(() => devicesOf('home-A').length === 2));
  assert.equal(platform.homes.get('home-A').bridge, bridge);
});

test('logement sans appareil : sa passerelle s\'arrête', async () => {
  store.assign('tuya:a', 'home-A');
  await platform.refresh();
  store.assign('tuya:a', null);
  await platform.refresh();
  assert.equal(platform.homes.size, 0);
});

test('ajout par le résident : refusé, c\'est l\'installateur qui pose les appareils', async () => {
  store.assign('tuya:a', 'home-A');
  await platform.refresh();
  store.pairings.push({ id: 'p1', home_id: 'home-A', kind: 'scan', status: 'pending', created_at: new Date().toISOString() });
  assert.ok(await until(() => store.pairings[0].status === 'failed'));
  assert.equal(store.pairings[0].error, INSTALLER_ONLY_MESSAGE);
});
