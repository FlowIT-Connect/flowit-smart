import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { afterEach, describe, test } from 'node:test';

import { addDirectCameras, parseCameras, snapshotRequest } from '../src/adapters/direct_cameras.js';
import { FakeHomeAssistant } from '../src/adapters/fake_home_assistant.js';
import { buildInventory, entityCapabilities } from '../src/adapters/ha_mapping.js';
import { HomeAssistantAdapter } from '../src/adapters/home_assistant.js';
import { productImageUrl } from '../src/adapters/tuya_mapping.js';
import { Bridge } from '../src/bridge.js';
import { loadConfig } from '../src/config.js';
import { setLogLevel } from '../src/log.js';
import { encodePng, simulatedFrame } from '../src/png.js';
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
const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const imageResponse = (bytes = simulatedFrame(), type = 'image/png') => new Response(bytes, { headers: { 'content-type': type } });

describe('Caméras Home Assistant', () => {
  test('entité camera : capacité « camera » en lecture seule, regroupée avec le détecteur de mouvement', () => {
    const caps = entityCapabilities({ entity_id: 'camera.entree', state: 'idle', attributes: {} });
    assert.deepEqual(caps.map((c) => [c.key, c.type, c.writable, c.metadata.kind]), [['camera', 'string', false, 'camera']]);
    const { states, devices, entities } = new FakeHomeAssistant();
    const cam = buildInventory([...states.values()], entities, devices).find((d) => d.name === 'Caméra entrée');
    assert.deepEqual(cam.capabilities.map((c) => c.capability_key), ['camera', 'motion']);
    assert.equal(cam.protocol, 'wifi');
  });

  test('image lue par camera_proxy avec le jeton, adresse REST déduite du WebSocket du module', async () => {
    const fake = new FakeHomeAssistant(undefined, { latencyMs: 5 });
    const calls = [];
    const adapter = new HomeAssistantAdapter({
      wsUrl: 'ws://supervisor/core/websocket',
      token: 'simulateur',
      wsFactory: () => fake.socket(),
      fetchImpl: async (url, opts) => {
        calls.push({ url, auth: opts.headers.Authorization });
        return imageResponse(Buffer.from('jpeg'), 'image/jpeg');
      },
    });
    await adapter.start();
    const cam = adapter.devices().find((d) => d.name === 'Caméra entrée');
    const frame = await adapter.cameraSnapshot(cam.externalId, 'camera');
    assert.equal(frame.contentType, 'image/jpeg');
    assert.deepEqual(calls, [{ url: 'http://supervisor/core/api/camera_proxy/camera.entree', auth: 'Bearer simulateur' }]);
    const plug = adapter.devices().find((d) => d.name === 'Prise café');
    assert.equal(await adapter.cameraSnapshot(plug.externalId, 'switch'), null, 'pas d\'image pour une prise');
    adapter.stop();
  });
});

describe('Images en direct via la passerelle', () => {
  let bridge;
  afterEach(async () => bridge?.stop());

  async function start(fetchImpl) {
    const fake = new FakeHomeAssistant(undefined, { latencyMs: 5 });
    const store = new MemoryStore();
    const adapter = new HomeAssistantAdapter({ url: 'http://ha.local:8123', token: 'simulateur', wsFactory: () => fake.socket(), fetchImpl });
    bridge = new Bridge({
      store,
      adapter,
      config: { integrationId: 'integ-1', commandTimeoutMs: 300, pendingMaxAgeMs: 30_000, pollIntervalMs: 50, automationRefreshMs: 60_000, runAutomations: false, cameraIntervalMs: 30 },
    });
    await bridge.start();
    bridge.cameras.watchTtlMs = 200;
    bridge.cameras.retryMs = 20;
    return store;
  }

  test('images envoyées seulement pendant qu\'un membre regarde', async () => {
    let fetches = 0;
    const store = await start(async () => {
      fetches++;
      return imageResponse();
    });
    const cam = store.deviceByName('Caméra entrée');
    await sleep(100);
    assert.equal(fetches, 0, 'aucune image sans spectateur');
    store.watchCamera(cam.id);
    assert.ok(await until(() => store.frameNotices.length >= 3), 'plusieurs images successives');
    const frame = store.frames.get(`home-1/${cam.id}.jpg`);
    assert.ok(frame.bytes.subarray(0, 8).equals(PNG_SIGNATURE));
    assert.equal(frame.contentType, 'image/png');
    assert.equal(store.frameNotices[0].deviceId, cam.id);
    await sleep(400); // plus de « watch » : la boucle s'arrête
    const n = fetches;
    await sleep(150);
    assert.equal(fetches, n, 'arrêt quand plus personne ne regarde');
  });

  test('appareil sans caméra ou inconnu : ignoré', async () => {
    let fetches = 0;
    const store = await start(async () => {
      fetches++;
      return imageResponse();
    });
    store.watchCamera(store.deviceByName('Prise café').id);
    store.watchCamera('00000000-0000-0000-0000-000000000000');
    await sleep(150);
    assert.equal(fetches, 0);
    assert.equal(store.frames.size, 0);
  });

  test('caméra en erreur : réessaie sans planter', async () => {
    let fail = true;
    const store = await start(async () => (fail ? new Response('non', { status: 503 }) : imageResponse()));
    const cam = store.deviceByName('Caméra entrée');
    store.watchCamera(cam.id);
    await sleep(80);
    assert.equal(store.frames.size, 0);
    fail = false;
    store.watchCamera(cam.id);
    assert.ok(await until(() => store.frames.size === 1));
  });
});

describe('Caméras directes (CAMERAS)', () => {
  test('lecture de la variable et identifiants passés en en-tête Basic', () => {
    assert.deepEqual(parseCameras(''), []);
    const cams = parseCameras('Entrée=http://admin:p%40ss@192.168.1.20/snapshot.jpg ; Garage=https://192.168.1.21/cgi-bin/snap');
    assert.deepEqual(cams.map((c) => c.name), ['Entrée', 'Garage']);
    const req = snapshotRequest(cams[0].url);
    assert.equal(req.url, 'http://192.168.1.20/snapshot.jpg');
    assert.equal(req.headers.Authorization, `Basic ${Buffer.from('admin:p@ss').toString('base64')}`);
    assert.deepEqual(snapshotRequest(cams[1].url).headers, {});
    assert.throws(() => parseCameras('sans-adresse'), /Nom=adresse/);
    assert.throws(() => parseCameras('X=rtsp://192.168.1.2/live'), /http/);
  });

  test('ajoutées à l\'inventaire d\'un autre adaptateur, disponibilité selon la réponse', async () => {
    const base = Object.assign(new EventEmitter(), {
      start: async () => {},
      stop: () => {},
      devices: () => [{ externalId: 'tuya:1', name: 'Prise' }],
      snapshot: () => ({ state: { switch: true }, availability: 'available' }),
      execute: async () => ({ status: 'confirmed' }),
    });
    let ok = true;
    const urls = [];
    const adapter = addDirectCameras(base, parseCameras('Portail=http://u:p@10.0.0.5/snap.jpg'), {
      fetchImpl: async (url) => {
        urls.push(url);
        return ok ? imageResponse(Buffer.from('jpeg'), 'image/jpeg') : new Response('', { status: 401 });
      },
    });
    await adapter.start();
    const cam = adapter.devices().find((d) => d.name === 'Portail');
    assert.equal(adapter.devices().length, 2);
    assert.equal(adapter.snapshot(cam.externalId).availability, 'available');
    assert.equal(adapter.snapshot('tuya:1').state.switch, true);
    assert.equal((await adapter.execute(cam.externalId, 'camera', true)).status, 'failed');
    assert.equal((await adapter.cameraSnapshot(cam.externalId, 'camera')).contentType, 'image/jpeg');
    assert.ok(!urls.some((u) => u.includes('u:p')), 'identifiants jamais dans l\'URL');
    const events = [];
    adapter.on('device', (id, snap) => events.push([id, snap.availability]));
    ok = false;
    await assert.rejects(adapter.cameraSnapshot(cam.externalId, 'camera'), /401/);
    assert.deepEqual(events, [[cam.externalId, 'unavailable']]);
    adapter.stop();
  });

  test('configuration', () => {
    const env = { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'k', INTEGRATION_ID: 'i', ADAPTER: 'simulator' };
    assert.deepEqual(loadConfig(env).cameras, []);
    assert.equal(loadConfig({ ...env, CAMERAS: 'A=http://1.2.3.4/a.jpg' }).cameras.length, 1);
    assert.equal(loadConfig({ ...env, CAMERA_INTERVAL_MS: '2000' }).cameraIntervalMs, 2000);
  });
});

describe('Photos produits et PNG', () => {
  test('photo Tuya : chemin relatif complété avec le CDN de la région, https imposé', () => {
    assert.equal(productImageUrl('smart/icon/clim.png', 'https://images.tuyaeu.com'), 'https://images.tuyaeu.com/smart/icon/clim.png');
    assert.equal(productImageUrl('http://images.tuyaeu.com/a.png', null), 'https://images.tuyaeu.com/a.png');
    assert.equal(productImageUrl('', 'https://images.tuyaeu.com'), null);
    assert.equal(productImageUrl('smart/icon/a.png', null), null);
    assert.equal(productImageUrl('../../x', 'https://images.tuyaeu.com'), null);
  });

  test('encodeur PNG : signature et dimensions', () => {
    const png = encodePng(3, 2, () => [255, 128, 0]);
    assert.ok(png.subarray(0, 8).equals(PNG_SIGNATURE));
    assert.equal(png.readUInt32BE(16), 3);
    assert.equal(png.readUInt32BE(20), 2);
    assert.ok(simulatedFrame(0).length > 100);
  });
});
