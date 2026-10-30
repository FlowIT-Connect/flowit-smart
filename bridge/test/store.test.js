import assert from 'node:assert/strict';
import { test } from 'node:test';

import { SupabaseStore } from '../src/store.js';

/** Capture les requêtes PostgREST émises par le store (sans serveur). */
function recorder(responses = {}) {
  const calls = [];
  const fetch = async (url, init = {}) => {
    const u = new URL(url);
    calls.push({ method: init.method ?? 'GET', path: u.pathname, query: decodeURIComponent(u.search), body: init.body ? JSON.parse(init.body) : null });
    const body = responses[`${init.method ?? 'GET'} ${u.pathname}`] ?? [];
    return new Response(JSON.stringify(body), { status: 200, headers: { 'content-type': 'application/json' } });
  };
  return { calls, fetch };
}

test('remplacement des capacités : upsert puis suppression des clés disparues', async () => {
  const r = recorder();
  const store = new SupabaseStore('http://db.local', 'service', { fetch: r.fetch });
  await store.replaceCapabilities('dev-1', [
    { capability_key: 'switch', type: 'boolean', writable: true, metadata: {} },
    { capability_key: 'brightness', type: 'number', writable: true, metadata: { min: 1 } },
  ]);
  assert.equal(r.calls[0].method, 'POST');
  assert.match(r.calls[0].query, /on_conflict=device_id,capability_key/);
  assert.equal(r.calls[0].body[0].device_id, 'dev-1');
  assert.equal(r.calls[1].method, 'DELETE');
  assert.match(r.calls[1].query, /device_id=eq\.dev-1/);
  assert.match(r.calls[1].query, /capability_key=not\.in\.\("switch","brightness"\)/);
});

test('réservation atomique d\'une commande : filtre sur status=pending', async () => {
  const r = recorder({ 'PATCH /rest/v1/device_commands': [{ id: 'c1' }] });
  const store = new SupabaseStore('http://db.local', 'service', { fetch: r.fetch });
  assert.equal(await store.claimCommand('c1'), true);
  assert.equal(r.calls[0].method, 'PATCH');
  assert.match(r.calls[0].query, /id=eq\.c1/);
  assert.match(r.calls[0].query, /status=eq\.pending/);
  assert.deepEqual(r.calls[0].body, { status: 'sent' });
});

test('commandes dues : bornées à la maison et aux appareils de la passerelle', async () => {
  const r = recorder();
  const store = new SupabaseStore('http://db.local', 'service', { fetch: r.fetch });
  await store.fetchDueCommands('h1', ['d1', 'd2'], '2026-10-26T10:00:00.000Z');
  const q = r.calls[0].query;
  assert.match(q, /home_id=eq\.h1/);
  assert.match(q, /status=eq\.pending/);
  assert.match(q, /device_id=in\.\(d1,d2\)/);
  assert.match(q, /not_before=lte\.2026-10-26T10:00:00\.000Z/);
});

test('exécution de scène par automatisation : RPC execute_scene', async () => {
  const r = recorder({ 'POST /rest/v1/rpc/execute_scene': 'run-1' });
  const store = new SupabaseStore('http://db.local', 'service', { fetch: r.fetch });
  assert.equal(await store.executeScene('s1', 'a1'), 'run-1');
  assert.deepEqual(r.calls[0].body, { p_scene_id: 's1', p_automation_id: 'a1' });
});

test('image de caméra : dépôt dans le bucket privé camera-frames, écrasée à chaque image', async () => {
  const calls = [];
  const fetch = async (url, init = {}) => {
    const u = new URL(url);
    calls.push({ method: init.method, path: u.pathname, upsert: new Headers(init.headers).get('x-upsert') });
    return new Response(JSON.stringify({ Key: 'camera-frames/h1/d1.jpg' }), { status: 200, headers: { 'content-type': 'application/json' } });
  };
  const store = new SupabaseStore('http://db.local', 'service', { fetch });
  assert.equal(await store.uploadCameraFrame('h1', 'd1', Buffer.from('jpeg'), 'image/jpeg'), 'h1/d1.jpg');
  assert.equal(calls[0].method, 'POST');
  assert.equal(calls[0].path, '/storage/v1/object/camera-frames/h1/d1.jpg');
  assert.equal(calls[0].upsert, 'true');
});

test('ajout d\'appareils : demande réservée une seule fois, clé de serrure effacée à la fin', async () => {
  const r = recorder({ 'PATCH /rest/v1/pairing_requests': [{ id: 'p1' }] });
  const store = new SupabaseStore('http://db.local', 'service', { fetch: r.fetch });
  await store.fetchPairings('h1');
  assert.match(r.calls[0].query, /home_id=eq\.h1/);
  assert.match(r.calls[0].query, /status=eq\.pending/);
  assert.equal(await store.claimPairing('p1'), true);
  assert.match(r.calls[1].query, /status=eq\.pending/);
  assert.deepEqual(r.calls[1].body, { status: 'working' });
  await store.completePairing('p1', 'done', null, 'd9');
  assert.equal(r.calls[2].body.lock_data, null);
  assert.equal(r.calls[2].body.device_id, 'd9');
  await store.findNewDevice('i1', '2026-10-31T10:00:00.000Z', ['d9']);
  assert.match(r.calls[3].query, /integration_id=eq\.i1/);
  assert.match(r.calls[3].query, /created_at=gt\.2026-10-31T10:00:00\.000Z/);
  assert.match(r.calls[3].query, /id=not\.in\.\(d9\)/);
});
