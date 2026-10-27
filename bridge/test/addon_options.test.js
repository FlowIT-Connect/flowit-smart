import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

import { applyAddonOptions, DEFAULT_SUPABASE_URL, envFromAddonOptions } from '../src/addon_options.js';
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
