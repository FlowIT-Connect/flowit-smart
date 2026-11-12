import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

import { EventEmitter } from 'node:events';

import { applyAddonMqtt, applyAddonOptions, DEFAULT_SUPABASE_URL, envFromAddonOptions, startAddonYeedi, yeediFromAddonOptions } from '../src/addon_options.js';
import { loadConfig } from '../src/config.js';

test('options du module -> configuration Home Assistant via le Supervisor', () => {
  const env = envFromAddonOptions({ service_role_key: ' cle ', integration_id: 'abc', run_automations: true }, 'tok');
  const config = loadConfig(env);
  assert.equal(config.supabaseUrl, DEFAULT_SUPABASE_URL);
  assert.equal(config.supabaseServiceKey, 'cle');
  assert.equal(config.adapter, 'home_assistant');
  assert.equal(config.haWsUrl, 'ws://supervisor/core/websocket');
  assert.equal(config.haUrl, null);
  assert.equal(config.haToken, 'tok');
  assert.equal(env.RUN_AUTOMATIONS, 'true');
});

test('mode simulateur sans jeton Home Assistant', () => {
  const config = loadConfig(envFromAddonOptions({ service_role_key: 'k', integration_id: 'i', simulator: true, run_automations: false }));
  assert.equal(config.adapter, 'simulator');
  assert.equal(config.haToken, null);
});

test('option manquante : message clair', () => {
  assert.throws(() => loadConfig(envFromAddonOptions({ integration_id: 'i' }, 't')), /SUPABASE_SERVICE_ROLE_KEY/);
});

test('sans fichier d\'options, rien ne change', () => {
  const env = {};
  assert.equal(applyAddonOptions(env, join(tmpdir(), 'absent-flowit.json')), false);
  assert.deepEqual(env, {});
  const dir = mkdtempSync(join(tmpdir(), 'flowit-'));
  const file = join(dir, 'options.json');
  writeFileSync(file, JSON.stringify({ service_role_key: 'k', integration_id: 'i' }));
  const env2 = { SUPERVISOR_TOKEN: 's' };
  assert.equal(applyAddonOptions(env2, file), true);
  assert.equal(env2.HA_TOKEN, 's');
});

const FULL = {
  mode: 'tuya_cloud', service_role_key: 'k', integration_id: 'i', run_automations: true, ha_mqtt: true,
  tuya_access_id: 'tid', tuya_access_secret: 'tsec', tuya_region: 'eu',
  ttlock_client_id: 'cid', ttlock_client_secret: 'csec', ttlock_username: 'baziz', ttlock_password_md5: 'a'.repeat(32),
  yeedi_email: 'b@x.dz', yeedi_password_md5: 'B'.repeat(32), yeedi_country: 'DZ',
};

test('mode tuya_cloud : passerelle complète (Smart Life + TTLock) sur la box', () => {
  const config = loadConfig(envFromAddonOptions(FULL, 'tok'));
  assert.equal(config.adapter, 'tuya_cloud');
  assert.equal(config.tuyaAccessId, 'tid');
  assert.equal(config.haToken, null, 'pas d\'import de toutes les entités HA dans ce mode');
  // Seulement les télécommandes Broadlink de HA, avec leurs touches apprises.
  assert.deepEqual([...config.haImport.platforms], ['broadlink']);
  assert.equal(config.haImport.wsUrl, 'ws://supervisor/core/websocket');
  assert.equal(config.haImport.token, 'tok');
  assert.equal(config.haConfigDir, '/homeassistant');
  assert.equal(loadConfig(envFromAddonOptions({ ...FULL, ha_integrations: '' }, 'tok')).haImport, null);
  assert.deepEqual([...loadConfig(envFromAddonOptions({ ...FULL, ha_integrations: 'broadlink, xiaomi_miio' }, 'tok')).haImport.platforms], ['broadlink', 'xiaomi_miio']);
  assert.equal(config.ttlock.username, 'baziz');
  assert.deepEqual(yeediFromAddonOptions(FULL), {
    YEEDI_EMAIL: 'b@x.dz', YEEDI_PASSWORD_MD5: 'b'.repeat(32), YEEDI_COUNTRY: 'DZ', YEEDI_HOST: '127.0.0.1', YEEDI_PORT: '8790',
  });
  assert.equal(yeediFromAddonOptions({}), null);
});

test('broker MQTT fourni par le Supervisor', async () => {
  const env = { SUPERVISOR_TOKEN: 'sup' };
  let auth;
  const fetchImpl = async (url, init) => {
    auth = init.headers.authorization;
    assert.equal(url, 'http://supervisor/services/mqtt');
    return Response.json({ data: { host: 'core-mosquitto', port: 1883, username: 'addons', password: 'p@ss' } });
  };
  assert.equal(await applyAddonMqtt(FULL, env, fetchImpl), true);
  assert.equal(auth, 'Bearer sup');
  assert.equal(env.HA_MQTT_URL, 'mqtt://addons:p%40ss@core-mosquitto:1883');
  assert.deepEqual(loadConfig({ ...envFromAddonOptions(FULL), HA_MQTT_URL: env.HA_MQTT_URL }).haMqtt.password, 'p@ss');
  // Mosquitto absent : la passerelle démarre quand même.
  const env2 = {};
  assert.equal(await applyAddonMqtt(FULL, env2, async () => new Response('', { status: 400 })), false);
  assert.equal(env2.HA_MQTT_URL, undefined);
  // Mode home_assistant : pas d'export (les appareils sont déjà dans HA).
  assert.equal(await applyAddonMqtt({ ...FULL, mode: 'home_assistant' }, {}, fetchImpl), false);
});

test('module yeedi lancé à côté, avec un jeton partagé', () => {
  const dir = mkdtempSync(join(tmpdir(), 'yeedi-'));
  const entry = join(dir, 'index.js');
  writeFileSync(entry, '');
  const calls = [];
  const spawnImpl = (cmd, args, opts) => {
    calls.push({ args, env: opts.env });
    const child = new EventEmitter();
    child.kill = () => {};
    return child;
  };
  const env = {};
  const handle = startAddonYeedi(FULL, env, { spawnImpl, entry });
  assert.equal(env.YEEDI_URL, 'http://127.0.0.1:8790');
  assert.equal(calls[0].args[0], entry);
  assert.equal(calls[0].env.YEEDI_TOKEN, env.YEEDI_TOKEN);
  assert.equal(calls[0].env.YEEDI_EMAIL, 'b@x.dz');
  handle.stop();
  assert.equal(startAddonYeedi({ ...FULL, yeedi_email: '' }, {}, { spawnImpl, entry }), null);
});

test('mode video : boîtier vidéo sur la box, relais local, relance si le relais se fige', () => {
  const env = envFromAddonOptions({ mode: 'video', service_role_key: 'k', integration_id: 'i-video', log_level: 'info' }, 'tok');
  assert.equal(env.ADAPTER, 'video');
  assert.equal(env.MEDIAMTX, 'true');
  assert.equal(env.RELAY_RESTART_EXIT, '1');
  assert.equal(env.HA_TOKEN, undefined, 'aucun accès à Home Assistant nécessaire');
  const config = loadConfig(env);
  assert.equal(config.adapter, 'video');
  assert.equal(config.video.relay, true);
  assert.equal(config.video.mediamtxApiUrl, 'http://127.0.0.1:9997');
});
