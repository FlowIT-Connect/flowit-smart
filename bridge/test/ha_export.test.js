import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import net from 'node:net';
import { afterEach, beforeEach, describe, test } from 'node:test';

import { buildLockDevice } from '../src/adapters/ttlock.js';
import { addYeedi, buildVacuumDevice, YeediClient } from '../src/adapters/yeedi.js';
import { Bridge } from '../src/bridge.js';
import { loadConfig } from '../src/config.js';
import { commandFromHa, entitiesFor, HaExporter } from '../src/ha_export.js';
import { setLogLevel } from '../src/log.js';
import { encodeLength, MqttClient, packet, readPackets } from '../src/mqtt_client.js';
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

const devOf = (desc, state = {}) => ({
  name: desc.name, vendor: desc.vendor, model: desc.model, isSensitive: desc.isSensitive, state, availability: 'available',
  caps: new Map(desc.capabilities.map((c) => [c.capability_key, c])),
});

/** Broker MQTT minimal (QoS 0, retenus, jokers +) pour les tests. */
class FakeBroker {
  constructor() {
    this.retained = new Map();
    this.clients = new Set();
    this.connects = [];
    this.server = net.createServer((sock) => {
      const c = { sock, subs: [] };
      this.clients.add(c);
      let buf = Buffer.alloc(0);
      sock.on('data', (chunk) => {
        buf = Buffer.concat([buf, chunk]);
        const { packets, rest } = readPackets(buf);
        buf = Buffer.from(rest);
        for (const p of packets) this.#handle(c, p);
      });
      sock.on('close', () => this.clients.delete(c));
      sock.on('error', () => {});
    });
  }
  listen() {
    return new Promise((r) => this.server.listen(0, '127.0.0.1', () => r(this.server.address().port)));
  }
  close() {
    for (const c of this.clients) c.sock.destroy();
    return new Promise((r) => this.server.close(r));
  }
  #handle(c, { type, flags, body }) {
    if (type === 1) {
      const user = body.includes(Buffer.from('solea')) ? 'solea' : null;
      this.connects.push({ user });
      c.sock.write(packet(2, 0, Buffer.from([0, 0])));
    } else if (type === 8) {
      const len = body.readUInt16BE(2);
      c.subs.push(body.subarray(4, 4 + len).toString());
      c.sock.write(packet(9, 0, Buffer.from([body[0], body[1], 0])));
    } else if (type === 3) {
      const len = body.readUInt16BE(0);
      const topic = body.subarray(2, 2 + len).toString();
      const payload = body.subarray(2 + len).toString();
      if (flags & 1) payload === '' ? this.retained.delete(topic) : this.retained.set(topic, payload);
      this.deliver(topic, payload, c);
    } else if (type === 12) c.sock.write(packet(13, 0, Buffer.alloc(0)));
  }
  deliver(topic, payload, from = null) {
    for (const c of this.clients) {
      if (c === from) continue;
      if (c.subs.some((s) => new RegExp(`^${s.replace(/\+/g, '[^/]+')}$`).test(topic))) {
        const len = Buffer.alloc(2);
        len.writeUInt16BE(Buffer.byteLength(topic));
        c.sock.write(packet(3, 0, Buffer.concat([len, Buffer.from(topic), Buffer.from(payload)])));
      }
    }
  }
}

describe('export vers Home Assistant (MQTT)', () => {
  test('longueurs MQTT et découpage des paquets', () => {
    assert.deepEqual([...encodeLength(0)], [0]);
    assert.deepEqual([...encodeLength(321)], [0xc1, 0x02]);
    const big = packet(3, 0, Buffer.alloc(200, 1));
    const { packets, rest } = readPackets(Buffer.concat([big, big.subarray(0, 5)]));
    assert.equal(packets.length, 1);
    assert.equal(packets[0].body.length, 200);
    assert.equal(rest.length, 5);
  });

  test('robot : aspirateur HA avec vitesses, débit d\'eau et batterie ; la carte reste dans Solea', () => {
    const dev = devOf(buildVacuumDevice({ id: 'E1', name: 'Idir' }), { vacuum_state: 'charging', suction: 'standard', battery: 90 });
    const ents = entitiesFor({ ...dev, id: 'd1' }, 'solea');
    const by = Object.fromEntries(ents.map((e) => [e.key, e]));
    assert.equal(by.vacuum.component, 'vacuum');
    assert.deepEqual(by.vacuum.config.fan_speed_list, ['quiet', 'standard', 'strong', 'max']);
    assert.deepEqual(JSON.parse(by.vacuum.state(dev.state)), { state: 'docked', fan_speed: 'standard' });
    assert.equal(by.water_level.component, 'select');
    assert.equal(by.battery.component, 'sensor');
    assert.equal(by.battery.state(dev.state), '90');
    assert.ok(!by.vacuum_map && !by.vacuum_clean && !by.suction && !by.vacuum_state);
    assert.deepEqual(commandFromHa(dev, 'vacuum', 'return_to_base'), { key: 'vacuum_action', value: 'charge' });
    assert.equal(commandFromHa(dev, 'vacuum', 'locate'), null);
  });

  test('serrure TTLock : batterie et dernière ouverture, aucune commande', () => {
    const dev = devOf(buildLockDevice({ lockId: 7, lockAlias: 'Barrière', hasGateway: 0 }), { battery: 100, access_log: [{ at: '2026-11-02T14:48:56.000Z', ok: true }] });
    const ents = entitiesFor({ ...dev, id: 'd2' }, 'solea');
    assert.deepEqual(ents.map((e) => e.component).sort(), ['sensor', 'sensor']);
    assert.equal(ents.find((e) => e.key === 'last_access').state(dev.state), '2026-11-02T14:48:56.000Z');
    assert.ok(ents.every((e) => !e.config.command_topic));
  });

  test('capteur de présence Zigbee : présence, réglages et luminosité', () => {
    const dev = devOf({
      name: 'Présence', vendor: 'Tuya', isSensitive: false,
      capabilities: [
        { capability_key: 'motion', type: 'sensor', writable: false, metadata: { kind: 'binary' } },
        { capability_key: 'sensitivity', type: 'number', writable: true, metadata: { min: 0, max: 9, step: 1, setting: true } },
        { capability_key: 'illuminance', type: 'sensor', writable: false, metadata: { unit: 'lx' } },
        { capability_key: 'switch', type: 'boolean', writable: true, metadata: {} },
      ],
    }, { motion: true, sensitivity: 7, illuminance: 120, switch: false });
    const by = Object.fromEntries(entitiesFor({ ...dev, id: 'd3' }, 'solea').map((e) => [e.key, e]));
    assert.equal(by.motion.component, 'binary_sensor');
    assert.equal(by.motion.config.device_class, 'occupancy');
    assert.equal(by.motion.state(dev.state), 'ON');
    assert.equal(by.sensitivity.component, 'number');
    assert.equal(by.sensitivity.config.entity_category, 'config');
    assert.equal(by.illuminance.config.device_class, 'illuminance');
    assert.equal(by.switch.component, 'switch');
    assert.equal(by.switch.state(dev.state), 'OFF');
    assert.deepEqual(commandFromHa(dev, 'switch', 'ON'), { key: 'switch', value: true });
    assert.deepEqual(commandFromHa(dev, 'sensitivity', '5'), { key: 'sensitivity', value: 5 });
    assert.equal(commandFromHa(dev, 'motion', 'ON'), null, 'capteur en lecture seule');
  });

  test('configuration : HA_MQTT_URL active l\'export', () => {
    const env = { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'k', INTEGRATION_ID: 'i', ADAPTER: 'simulator' };
    assert.equal(loadConfig(env).haMqtt, null);
    assert.deepEqual(loadConfig({ ...env, HA_MQTT_URL: 'mqtt://solea:mot%40passe@192.168.1.50:1883' }).haMqtt, {
      host: '192.168.1.50', port: 1883, username: 'solea', password: 'mot@passe', prefix: 'homeassistant', base: 'solea',
    });
    assert.throws(() => loadConfig({ ...env, HA_MQTT_URL: 'http://192.168.1.50' }), /mqtt:\/\//);
  });

  describe('avec un broker', () => {
    let broker, port, store, bridge, exporter, robots;

    beforeEach(async () => {
      broker = new FakeBroker();
      port = await broker.listen();
      robots = [{ id: 'E1', name: 'Idir', model: 'yeedi 2 hybrid', online: true, state: { status: 'charging', battery: 92, suction: 'standard' } }];
      const fetchImpl = async (url, init = {}) => {
        const u = new URL(url);
        if (u.pathname === '/robots') return Response.json(robots);
        const body = JSON.parse(init.body);
        if (body.action === 'start') robots[0].state.status = 'cleaning';
        if (body.suction) robots[0].state.suction = body.suction;
        return Response.json({ status: 'confirmed', robot: robots[0] });
      };
      const base = new (class extends EventEmitter {
        async start() {}
        stop() {}
        devices() { return []; }
        snapshot() { return { state: {}, availability: 'unavailable' }; }
        async execute() { return { status: 'failed' }; }
      })();
      const adapter = addYeedi(base, new YeediClient({ url: 'http://y', token: 't', fetchImpl }), { pollMs: 40 });
      store = new MemoryStore();
      bridge = new Bridge({ store, adapter, config: { integrationId: 'integ-1', commandTimeoutMs: 500, pendingMaxAgeMs: 30_000, pollIntervalMs: 30, automationRefreshMs: 60_000, runAutomations: false } });
      exporter = new HaExporter({
        client: new MqttClient({ host: '127.0.0.1', port, username: 'solea', password: 'x', will: { topic: 'solea/bridge/status', payload: 'offline', retain: true } }),
        devices: () => bridge.devices.entries(),
        execute: (id, key, value) => bridge.executeLocal(id, key, value),
      });
      bridge.exporter = exporter;
      exporter.start();
      await bridge.start();
    });

    afterEach(async () => {
      exporter.stop();
      await bridge.stop();
      await broker.close();
    });

    test('le robot est publié pour HA, et HA peut le lancer', async () => {
      const robot = store.deviceByName('Idir');
      const cfgTopic = `homeassistant/vacuum/solea_${robot.id.replace(/-/g, '')}/vacuum/config`;
      assert.ok(await until(() => broker.retained.has(cfgTopic)), 'configuration publiée');
      const cfg = JSON.parse(broker.retained.get(cfgTopic));
      assert.equal(cfg.device.name, 'Idir');
      assert.equal(cfg.device.manufacturer, 'yeedi');
      assert.equal(broker.retained.get('solea/bridge/status'), 'online');
      assert.equal(broker.retained.get(`solea/${robot.id}/availability`), 'online');
      assert.deepEqual(JSON.parse(broker.retained.get(`solea/${robot.id}/vacuum/state`)), { state: 'docked', fan_speed: 'standard' });
      assert.equal(broker.connects[0].user, 'solea');

      broker.deliver(cfg.command_topic, 'start');
      assert.ok(await until(() => JSON.parse(broker.retained.get(`solea/${robot.id}/vacuum/state`)).state === 'cleaning'), 'état renvoyé à HA');
      assert.equal(store.devices.get(robot.id).state.vacuum_state, 'cleaning', 'Solea à jour aussi');

      broker.deliver(cfg.set_fan_speed_topic, 'max');
      assert.ok(await until(() => JSON.parse(broker.retained.get(`solea/${robot.id}/vacuum/state`)).fan_speed === 'max'));
    });

    test('appareil sensible : ordre de HA refusé', async () => {
      const r = await bridge.executeLocal('inconnu', 'switch', true);
      assert.equal(r.status, 'rejected');
      const robot = store.deviceByName('Idir');
      bridge.devices.get(robot.id).isSensitive = true;
      assert.match((await bridge.executeLocal(robot.id, 'vacuum_action', 'start')).error, /sensible/);
    });
  });
});
