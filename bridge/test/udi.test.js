import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import net from 'node:net';
import { createHash, createHmac } from 'node:crypto';
import { afterEach, describe, test } from 'node:test';

import { VideoOnlyAdapter } from '../src/adapters/video_only.js';
import { Bridge } from '../src/bridge.js';
import { loadConfig } from '../src/config.js';
import { setLogLevel } from '../src/log.js';
import { digestHeader, fetchWithAuth, parseChallenge } from '../src/udi/auth.js';
import { capabilityFlags, UDI_CAPABILITIES } from '../src/udi/contract.js';
import { OnvifDriver } from '../src/udi/drivers/onvif_driver.js';
import { RtspDriver } from '../src/udi/drivers/rtsp_driver.js';
import { addUdi, UdiHub } from '../src/udi/index.js';
import { iceServers, MediaMtx, pathName, turnCredentials } from '../src/udi/media/mediamtx.js';
import { motionFromNotification, OnvifClient, parseNotifications } from '../src/udi/onvif/client.js';
import { discoverOnvif, parseProbeMatches, subnetFilter } from '../src/udi/onvif/discovery.js';
import { parseSdp, probeRtsp, withCredentials } from '../src/udi/rtsp.js';
import { find, parseXml, textOf } from '../src/udi/xml.js';
import { FakeOnvifCamera, okProbe } from './fake_onvif.js';
import { MemoryStore } from './memory_store.js';

setLogLevel('error');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function until(fn, ms = 3000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (await fn()) return true;
    await sleep(15);
  }
  return false;
}

describe('UDI : outils', () => {
  test('XML : noms locaux sans préfixe, entités et attributs', () => {
    const doc = parseXml('<?xml version="1.0"?><s:Env xmlns:s="x"><!-- c --><a:B t="1&amp;2"><a:C>x &lt; y</a:C><a:D/></a:B></s:Env>');
    const b = find(doc, 'B');
    assert.equal(b.attrs.t, '1&2');
    assert.equal(textOf(doc, 'C'), 'x < y');
    assert.ok(find(doc, 'D'));
  });

  test('Digest : exemple de la RFC 2617', () => {
    const h = digestHeader({
      method: 'GET',
      uri: '/dir/index.html',
      username: 'Mufasa',
      password: 'Circle Of Life',
      challenge: { realm: 'testrealm@host.com', nonce: 'dcd98b7102dd2f0e8b11d0f600bfb0c093', qop: 'auth,auth-int', opaque: '5ccc069c403ebaf9f0171e9517f40e41' },
      cnonce: '0a4f113b',
    });
    assert.match(h, /response="6629fae49393a05397450978507c4ef1"/);
    assert.match(h, /qop=auth, nc=00000001, cnonce="0a4f113b"/);
    assert.equal(parseChallenge('Basic realm="x", Digest realm="cam", nonce="n1", qop="auth"').scheme, 'digest');
  });

  test('fetchWithAuth : réessaie en Digest après un 401', async () => {
    const cam = new FakeOnvifCamera();
    const res = await fetchWithAuth(cam.fetch, 'http://192.168.1.20/snapshot.jpg', {}, { username: 'admin', password: 'x' });
    assert.equal(res.status, 200);
  });

  test('capacités : liste fermée, tout faux par défaut', () => {
    const f = capabilityFlags({ video_stream: true, inconnu: true });
    assert.deepEqual(Object.keys(f), [...UDI_CAPABILITIES]);
    assert.equal(f.video_stream, true);
    assert.equal(f.door_relay, false);
    assert.equal('inconnu' in f, false);
  });
});

describe('ONVIF', () => {
  test('connexion : identification, flux principal et secondaire, image, adresses corrigées', async () => {
    const cam = new FakeOnvifCamera();
    const d = new OnvifDriver({ id: 's1', name: 'Entrée', host: '192.168.1.20', port: 80, username: 'admin', password: 'S3cret!' }, { fetchImpl: cam.fetch, probe: okProbe, events: false });
    await d.connect();
    assert.deepEqual(d.identity(), { manufacturer: 'HIKVISION', model: 'DS-2CD1043G2-I', firmware: 'V5.7.1 build 220715', serial: 'DS-2CD1043G2-I20220801' });
    const { main, sub } = d.streams();
    assert.equal(main, 'rtsp://192.168.1.20:554/Streaming/Channels/101?transportmode=unicast&profile=Profile_1');
    assert.match(sub, /Channels\/102/);
    const caps = d.capabilities();
    assert.equal(caps.video_stream, true);
    assert.equal(caps.snapshot, true);
    assert.equal(caps.audio_input, true, 'G.711 lisible en WebRTC');
    // Le relais est détecté mais pas encore piloté : jamais annoncé comme disponible.
    assert.equal(caps.door_relay, false);
    assert.equal(caps.audio_output, false);
    assert.equal(d.detected.relay_outputs, 1);
    const img = await d.snapshot();
    assert.ok(img.bytes.length > 50);
  });

  test('mauvais mot de passe : erreur « auth »', async () => {
    const cam = new FakeOnvifCamera();
    const d = new OnvifDriver({ id: 's1', host: '192.168.1.20', username: 'admin', password: 'faux' }, { fetchImpl: cam.fetch, probe: okProbe, events: false });
    await assert.rejects(d.connect(), (e) => e.kind === 'auth');
  });

  test('horloge de la caméra décalée de 2 h : le jeton suit l\'heure de la caméra', async () => {
    const cam = new FakeOnvifCamera({ clockSkewMs: 2 * 3600_000 });
    const client = new OnvifClient({ host: '192.168.1.20', username: 'admin', password: 'S3cret!', fetchImpl: cam.fetch });
    await assert.rejects(client.getDeviceInformation());
    await client.syncClock();
    assert.equal((await client.getDeviceInformation()).manufacturer, 'HIKVISION');
  });

  test('appareil éteint : erreur « injoignable »', async () => {
    const cam = new FakeOnvifCamera();
    cam.online = false;
    const d = new OnvifDriver({ id: 's1', host: '192.168.1.20', username: 'admin', password: 'S3cret!' }, { fetchImpl: cam.fetch, probe: okProbe, events: false });
    await assert.rejects(d.connect(), (e) => e.kind === 'unreachable');
  });

  test('événements : mouvement remonté par « pull point »', async () => {
    const cam = new FakeOnvifCamera();
    const d = new OnvifDriver({ id: 's1', host: '192.168.1.20', username: 'admin', password: 'S3cret!' }, { fetchImpl: cam.fetch, probe: okProbe, pullTimeoutSeconds: 1 });
    const seen = [];
    d.onEvent((e) => seen.push(e));
    await d.connect();
    cam.motion(true);
    assert.ok(await until(() => seen.some((e) => e.type === 'motion' && e.value === true)));
    assert.equal(d.capabilities().motion_detection, true);
    cam.motion(false);
    assert.ok(await until(() => seen.at(-1).value === false));
    await d.disconnect();
  });

  test('événements : sujets de mouvement des différents fabricants', () => {
    const doc = parseXml(
      '<r><wsnt:NotificationMessage><wsnt:Topic>tns1:VideoSource/MotionAlarm</wsnt:Topic><wsnt:Message><tt:Message UtcTime="2026-10-31T10:00:00Z"><tt:Data><tt:SimpleItem Name="State" Value="true"/></tt:Data></tt:Message></wsnt:Message></wsnt:NotificationMessage>' +
        '<wsnt:NotificationMessage><wsnt:Topic>tns1:Device/Trigger/DigitalInput</wsnt:Topic><wsnt:Message><tt:Message><tt:Data><tt:SimpleItem Name="LogicalState" Value="true"/></tt:Data></tt:Message></wsnt:Message></wsnt:NotificationMessage></r>',
    );
    const [motion, input] = parseNotifications(doc);
    assert.equal(motion.time, '2026-10-31T10:00:00Z');
    assert.equal(motionFromNotification(motion), true);
    assert.equal(motionFromNotification(input), null);
  });

  test('diagnostic : étapes lisibles, relais signalé comme prévu en phase B', async () => {
    const cam = new FakeOnvifCamera();
    const d = new OnvifDriver({ id: 's1', host: '192.168.1.20', username: 'admin', password: 'S3cret!' }, { fetchImpl: cam.fetch, probe: okProbe, events: false });
    const { steps } = await d.diagnose();
    assert.deepEqual(steps.map((s) => [s.step, s.ok]), [['connexion', true], ['identification', true], ['onvif', true], ['rtsp', true], ['image', true], ['événements', true], ['relais', true]]);
    assert.match(steps.find((s) => s.step === 'relais').detail, /phase B/);
  });
});

describe('Découverte ONVIF', () => {
  const MATCH =
    '<?xml version="1.0"?><SOAP-ENV:Envelope xmlns:SOAP-ENV="http://www.w3.org/2003/05/soap-envelope" xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery" xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing"><SOAP-ENV:Body><d:ProbeMatches><d:ProbeMatch>' +
    '<wsa:EndpointReference><wsa:Address>urn:uuid:aaaa-1</wsa:Address></wsa:EndpointReference><d:Types>dn:NetworkVideoTransmitter</d:Types>' +
    '<d:Scopes>onvif://www.onvif.org/type/video_encoder onvif://www.onvif.org/name/HIKVISION%20DS-KV6113 onvif://www.onvif.org/hardware/DS-KV6113-WPE1</d:Scopes>' +
    '<d:XAddrs>http://[fe80::1]/onvif/device_service http://192.168.1.50:8000/onvif/device_service</d:XAddrs></d:ProbeMatch></d:ProbeMatches></SOAP-ENV:Body></SOAP-ENV:Envelope>';

  test('réponse ProbeMatch : adresse IPv4, nom et modèle', () => {
    const [m] = parseProbeMatches(MATCH);
    assert.equal(m.host, '192.168.1.50');
    assert.equal(m.port, 8000);
    assert.equal(m.name, 'HIKVISION DS-KV6113');
    assert.equal(m.hardware, 'DS-KV6113-WPE1');
  });

  test('sous-réseaux autorisés', () => {
    const allow = subnetFilter('192.168.1.0/24');
    assert.equal(allow('192.168.1.50'), true);
    assert.equal(allow('192.168.2.50'), false);
    assert.equal(subnetFilter('')('8.8.8.8'), false, 'par défaut : réseaux privés uniquement');
    assert.throws(() => subnetFilter('abc/24'));
  });

  test('sonde multicast : réponses dédoublonnées, hors sous-réseau ignorées', async () => {
    const sent = [];
    const sock = new EventEmitter();
    sock.bind = (_port, cb) => setImmediate(cb);
    sock.send = (buf, _o, _l, port, address) => {
      sent.push({ port, address, xml: buf.toString() });
      setImmediate(() => {
        sock.emit('message', Buffer.from(MATCH), { address: '192.168.1.50' });
        sock.emit('message', Buffer.from(MATCH.replace('192.168.1.50', '10.9.9.9').replace('aaaa-1', 'bbbb-2')), { address: '10.9.9.9' });
        sock.emit('message', Buffer.from('pas du xml <'), { address: '192.168.1.60' });
      });
    };
    sock.close = () => {};
    const found = await discoverOnvif({ timeoutMs: 100, allowed: subnetFilter('192.168.0.0/16'), socketFactory: () => sock });
    assert.equal(sent.length, 2);
    assert.equal(sent[0].address, '239.255.255.250');
    assert.equal(sent[0].port, 3702);
    assert.match(sent[0].xml, /NetworkVideoTransmitter/);
    assert.deepEqual(found.map((f) => f.host), ['192.168.1.50']);
  });
});

describe('RTSP', () => {
  let server;
  afterEach(() => server?.close());

  /** Petit serveur RTSP protégé par Digest. */
  function startServer({ user = 'admin', pass = 'S3cret!', sdp } = {}) {
    return new Promise((resolve) => {
      server = net.createServer((sock) => {
        sock.on('data', (buf) => {
          const req = buf.toString();
          const cseq = /CSeq: (\d+)/.exec(req)[1];
          const auth = /Authorization: Digest (.*)\r\n/.exec(req)?.[1];
          const md5 = (s) => createHash('md5').update(s).digest('hex');
          const uri = /uri="([^"]+)"/.exec(auth ?? '')?.[1];
          const valid = auth && md5(`${md5(`${user}:cam:${pass}`)}:n1:${md5(`DESCRIBE:${uri}`)}`) === /response="([^"]+)"/.exec(auth)[1];
          if (!valid) return sock.write(`RTSP/1.0 401 Unauthorized\r\nCSeq: ${cseq}\r\nWWW-Authenticate: Digest realm="cam", nonce="n1"\r\n\r\n`);
          sock.write(`RTSP/1.0 200 OK\r\nCSeq: ${cseq}\r\nContent-Type: application/sdp\r\nContent-Length: ${Buffer.byteLength(sdp)}\r\n\r\n${sdp}`);
        });
      }).listen(0, '127.0.0.1', () => resolve(server.address().port));
    });
  }
  const SDP = 'v=0\r\no=- 0 0 IN IP4 0.0.0.0\r\ns=cam\r\nm=video 0 RTP/AVP 96\r\na=rtpmap:96 H264/90000\r\nm=audio 0 RTP/AVP 97\r\na=rtpmap:97 MPEG4-GENERIC/16000/1\r\n';

  test('DESCRIBE avec Digest : codecs lus dans le SDP', async () => {
    const port = await startServer({ sdp: SDP });
    const r = await probeRtsp(`rtsp://admin:S3cret!@127.0.0.1:${port}/Streaming/Channels/101`);
    assert.deepEqual(r, { ok: true, status: 200, video: { codec: 'H264' }, audio: { codec: 'MPEG4-GENERIC' } });
  });

  test('mauvais mot de passe : 401 expliqué', async () => {
    const port = await startServer({ sdp: SDP });
    const r = await probeRtsp(`rtsp://127.0.0.1:${port}/stream`, { username: 'admin', password: 'faux' });
    assert.equal(r.ok, false);
    assert.equal(r.status, 401);
  });

  test('hôte injoignable et adresse invalide', async () => {
    assert.equal((await probeRtsp('rtsp://127.0.0.1:1/x', { timeoutMs: 500 })).ok, false);
    assert.equal((await probeRtsp('http://x')).error, 'Adresse rtsp:// attendue');
  });

  test('pilote RTSP : l\'audio AAC n\'est pas annoncé (illisible en WebRTC)', async () => {
    const port = await startServer({ sdp: SDP });
    const d = new RtspDriver({ id: 'r1', rtsp_url: `rtsp://127.0.0.1:${port}/s`, username: 'admin', password: 'S3cret!' });
    await d.connect();
    assert.equal(d.capabilities().video_stream, true);
    assert.equal(d.capabilities().audio_input, false);
    assert.equal(d.capabilities().snapshot, false);
  });

  test('SDP et identifiants', () => {
    assert.deepEqual(parseSdp('m=video 0 RTP/AVP 96\na=rtpmap:96 H265/90000\nm=audio 0 RTP/AVP 0\na=rtpmap:0 PCMU/8000'), { video: { codec: 'H265' }, audio: { codec: 'PCMU' } });
    assert.equal(withCredentials('rtsp://192.168.1.2/s', 'ad min', 'p@ss'), 'rtsp://ad%20min:p%40ss@192.168.1.2/s');
  });
});

describe('MediaMTX', () => {
  function fakeMtx() {
    const paths = new Map();
    const calls = [];
    const fetchImpl = async (url, init = {}) => {
      const u = new URL(url);
      calls.push([init.method ?? 'GET', u.pathname, init.body]);
      const name = decodeURIComponent(u.pathname.split('/').pop());
      if (u.pathname.startsWith('/v3/config/paths/get/')) return paths.has(name) ? Response.json(paths.get(name)) : new Response('{"error":"path not found"}', { status: 404 });
      if (u.pathname.startsWith('/v3/config/paths/add/')) return paths.set(name, JSON.parse(init.body)), new Response('', { status: 200 });
      if (u.pathname.startsWith('/v3/config/paths/patch/')) return paths.set(name, { ...paths.get(name), ...JSON.parse(init.body) }), new Response('', { status: 200 });
      if (u.pathname.startsWith('/v3/config/paths/delete/')) return paths.delete(name), new Response('', { status: 200 });
      if (u.pathname === '/v3/config/global/patch') return new Response('', { status: 200 });
      if (u.pathname === '/v3/paths/list') return Response.json({ items: [] });
      if (u.pathname.endsWith('/whep')) {
        const p = u.pathname.split('/')[1];
        if (!paths.has(p)) return new Response('', { status: 404 });
        return new Response('v=0 réponse', { status: 201, headers: { location: `/${p}/whep/sess-1` } });
      }
      if (init.method === 'DELETE') return new Response('', { status: 200 });
      return new Response('', { status: 404 });
    };
    return { paths, calls, mtx: new MediaMtx({ apiUrl: 'http://127.0.0.1:9997', webrtcUrl: 'http://127.0.0.1:8889', fetchImpl }) };
  }

  test('chemins à la demande, mise à jour seulement si la source change', async () => {
    const { mtx, paths } = fakeMtx();
    assert.equal(await mtx.ensurePath('solea_x_main', 'rtsp://a:b@1.2.3.4/s'), 'added');
    assert.deepEqual(paths.get('solea_x_main'), { source: 'rtsp://a:b@1.2.3.4/s', sourceOnDemand: true, rtspTransport: 'tcp' });
    assert.equal(await mtx.ensurePath('solea_x_main', 'rtsp://a:b@1.2.3.4/s'), 'unchanged');
    assert.equal(await mtx.ensurePath('solea_x_main', 'rtsp://a:c@1.2.3.4/s'), 'updated');
    assert.equal(await mtx.health(), true);
  });

  test('WHEP : réponse SDP et adresse de session absolue', async () => {
    const { mtx } = fakeMtx();
    await mtx.ensurePath('solea_x_main', 'rtsp://1.2.3.4/s');
    const r = await mtx.whep('solea_x_main', 'v=0 offre');
    assert.equal(r.answer, 'v=0 réponse');
    assert.equal(r.location, 'http://127.0.0.1:8889/solea_x_main/whep/sess-1');
    await assert.rejects(mtx.whep('inconnu', 'v=0'), /introuvable/);
  });

  test('serveurs ICE : TURN temporaire, jamais le secret', async () => {
    const c = turnCredentials('secret', { now: 1_800_000_000_000, ttlSeconds: 3600 });
    assert.equal(c.username, '1800003600:solea');
    assert.equal(c.credential, createHmac('sha1', 'secret').update('1800003600:solea').digest('base64'));
    const servers = iceServers({ stun: ['stun:s:3478'], turn: ['turn:t:3478'], turnSecret: 'secret', now: 1_800_000_000_000 });
    assert.equal(JSON.stringify(servers).includes('"secret"'), false);
    assert.equal(servers.length, 2);
    assert.deepEqual(iceServers({ stun: ['stun:s'], turn: ['turn:t'] }), [{ urls: ['stun:s'] }], 'TURN sans secret : ignoré');
    const { mtx, calls } = fakeMtx();
    await mtx.setIceServers(servers);
    const body = JSON.parse(calls.at(-1)[2]);
    assert.deepEqual(body.webrtcICEServers2.map((s) => s.url), ['stun:s:3478', 'turn:t:3478']);
    assert.equal(body.webrtcICEServers2[1].username, '1800021600:solea', 'valable 6 h par défaut');
  });

  test('noms de chemins', () => {
    assert.equal(pathName('1b2c-3d', 'sub'), 'solea_1b2c3d_sub');
    assert.equal(pathName('x', 'autre'), 'solea_x_main');
  });

  // Exposé pour les autres tests de ce fichier.
  globalThis.__fakeMtx = fakeMtx;
});


describe('Boîtier vidéo : passerelle + UDI', () => {
  let bridge;
  afterEach(async () => {
    await bridge?.stop();
    bridge = null;
  });

  async function setup({ sources, driverFactory, discover, automations = [] } = {}) {
    const store = new MemoryStore();
    store.videoSources = sources;
    store.automations = automations;
    const { mtx, paths } = globalThis.__fakeMtx();
    const hub = new UdiHub({ driverFactory, mediamtx: mtx, discover, allowedSubnet: subnetFilter(''), retryMinMs: 30, retryMaxMs: 100 });
    const adapter = addUdi(new VideoOnlyAdapter(), hub);
    bridge = new Bridge({
      store,
      adapter,
      config: { integrationId: 'integ-1', commandTimeoutMs: 300, pendingMaxAgeMs: 30_000, pollIntervalMs: 50, automationRefreshMs: 60_000, runAutomations: true, runTimeTriggers: false },
    });
    await bridge.start();
    return { store, hub, paths, adapter };
  }

  const cam = new FakeOnvifCamera();
  const goodSource = { id: 'src-1', home_id: 'home-1', name: 'Portail', category: 'intercom', driver: 'onvif', host: '192.168.1.20', port: 80, username: 'admin', password: 'S3cret!' };
  const onvifFactory = (s) => new OnvifDriver(s, { fetchImpl: cam.fetch, probe: okProbe, pullTimeoutSeconds: 1 });

  test('équipement ajouté : appareil créé, diagnostic, capacités réelles, flux préparé', async () => {
    const { store, paths } = await setup({ sources: [{ ...goodSource }], driverFactory: onvifFactory });
    assert.ok(await until(() => store.videoSources[0].status === 'online'));
    const src = store.videoSources[0];
    assert.equal(src.manufacturer, 'HIKVISION');
    assert.equal(src.capabilities.video_stream, true);
    assert.ok(src.diagnostic.steps.length >= 5);
    assert.ok(await until(() => [...store.devices.values()].some((d) => d.vendor === 'HIKVISION')));
    const device = [...store.devices.values()][0];
    assert.equal(store.bindings[0].external_id, 'udi:src-1');
    assert.ok(await until(() => store.capabilities.some((c) => c.device_id === device.id && c.capability_key === 'motion')));
    const camCap = store.capabilities.find((c) => c.device_id === device.id && c.capability_key === 'camera');
    assert.equal(camCap.metadata.live, 'webrtc');
    assert.equal(camCap.metadata.udi.door_relay, false);
    assert.equal(device.availability, 'available');
    // MediaMTX reçoit l'adresse RTSP avec identifiants ; la base ne la voit jamais.
    assert.equal(paths.get('solea_src1_main').source, 'rtsp://admin:S3cret!@192.168.1.20:554/Streaming/Channels/101?transportmode=unicast&profile=Profile_1');
    assert.equal(JSON.stringify(store.videoSources).includes('rtsp://admin'), false);
    assert.equal(store.mediaGateways.get('home-1').relay_ok, true);
  });

  test('vidéo en direct : offre de l\'application → réponse du relais, fermeture propre', async () => {
    const { store } = await setup({ sources: [{ ...goodSource }], driverFactory: onvifFactory });
    assert.ok(await until(() => store.videoSources[0].status === 'online' && store.devices.size === 1));
    const deviceId = [...store.devices.keys()][0];
    store.videoSessions.push({ id: 'sess-1', home_id: 'home-1', device_id: deviceId, quality: 'sub', offer: 'v=0 offre', status: 'offer', created_at: new Date().toISOString() });
    assert.ok(await until(() => store.videoSessions[0].status === 'answered'));
    assert.equal(store.videoSessions[0].answer, 'v=0 réponse');
    assert.equal(store.videoSessions[0].quality, 'sub');
    store.videoSessions[0].status = 'closed';
    await bridge.adapter.udi.processSessions();
    assert.equal(bridge.adapter.udi.sessions.size, 0);
    // Appareil inconnu et demande trop ancienne : refusés avec une raison.
    store.videoSessions.push({ id: 'sess-2', home_id: 'home-1', device_id: 'autre', offer: 'v=0', status: 'offer', created_at: new Date().toISOString() });
    store.videoSessions.push({ id: 'sess-3', home_id: 'home-1', device_id: deviceId, offer: 'v=0', status: 'offer', created_at: new Date(Date.now() - 120_000).toISOString() });
    assert.ok(await until(() => store.videoSessions[1].status === 'failed' && store.videoSessions[2].status === 'failed'));
    assert.match(store.videoSessions[1].error, /inconnu/);
    assert.match(store.videoSessions[2].error, /expirée/);
  });

  test('mouvement : état de l\'appareil mis à jour en temps réel', async () => {
    const { store } = await setup({ sources: [{ ...goodSource }], driverFactory: onvifFactory });
    assert.ok(await until(() => store.devices.size === 1 && [...store.devices.values()][0].availability === 'available'));
    cam.motion(true);
    assert.ok(await until(() => [...store.devices.values()][0].state?.motion === true));
    cam.motion(false);
    assert.ok(await until(() => [...store.devices.values()][0].state?.motion === false));
  });

  test('automatisation : mouvement de la caméra → commande pour un appareil d\'une autre passerelle', async () => {
    const automations = [
      { id: 'a-motion', home_id: 'home-1', enabled: true, name: 'Lumière entrée', trigger: { type: 'device_state', device_id: null, capability_key: 'motion', op: 'eq', value: true },
        conditions: [], actions: [{ device_id: 'lampe-autre-passerelle', capability_key: 'switch', value: true }] },
      { id: 'a-time', home_id: 'home-1', enabled: true, name: 'Horaire', trigger: { type: 'time', at: '00:00', days: [0, 1, 2, 3, 4, 5, 6] }, conditions: [], actions: [{ device_id: 'x', capability_key: 'switch', value: true }] },
    ];
    const { store } = await setup({ sources: [{ ...goodSource }], driverFactory: onvifFactory, automations });
    assert.ok(await until(() => store.devices.size === 1 && [...store.devices.values()][0].availability === 'available'));
    automations[0].trigger.device_id = [...store.devices.keys()][0];
    cam.motion(true);
    assert.ok(await until(() => store.commands.some((c) => c.automation_id === 'a-motion')));
    assert.equal(store.commands.find((c) => c.automation_id === 'a-motion').device_id, 'lampe-autre-passerelle');
    assert.equal(bridge.timers.length > 0, true);
    await bridge.tickTimeTriggers(); // appel direct possible, mais jamais programmé sur le boîtier
    cam.motion(false);
  });

  test('isolation : un appareil en panne n\'empêche pas les autres', async () => {
    const sources = [
      { ...goodSource },
      { id: 'src-2', home_id: 'home-1', name: 'Garage', category: 'camera', driver: 'onvif', host: '192.168.1.21', port: 80, username: 'admin', password: 'faux' },
      { id: 'src-3', home_id: 'home-1', name: 'Inconnu', category: 'camera', driver: 'xyz', host: '192.168.1.22' },
    ];
    const factory = (s) => {
      if (s.driver === 'xyz') throw new Error('Pilote inconnu : xyz');
      return s.id === 'src-2' ? new OnvifDriver(s, { fetchImpl: new FakeOnvifCamera({ host: '192.168.1.21' }).fetch, probe: okProbe, events: false }) : onvifFactory(s);
    };
    const { store } = await setup({ sources, driverFactory: factory });
    assert.ok(await until(() => store.videoSources[0].status === 'online' && store.videoSources[1].status === 'auth_error' && store.videoSources[2].status === 'error'));
    assert.match(store.videoSources[1].last_error, /Identifiants refusés/);
    assert.ok(await until(() => store.devices.size === 3));
    const byName = Object.fromEntries([...store.devices.values()].map((d) => [d.name, d.availability]));
    assert.equal(byName.Portail, 'available');
    assert.equal(byName.Garage, 'unavailable');
  });

  test('équipement supprimé ou désactivé : pilote arrêté et flux retiré', async () => {
    const { store, hub, paths } = await setup({ sources: [{ ...goodSource }], driverFactory: onvifFactory });
    assert.ok(await until(() => paths.has('solea_src1_main')));
    store.videoSources = [];
    await hub.refreshSources();
    assert.equal(hub.runners.size, 0);
    assert.equal(paths.has('solea_src1_main'), false);
  });

  test('recherche sur le réseau : résultats et équipements déjà ajoutés', async () => {
    const discover = async ({ allowed }) => [
      { host: '192.168.1.20', port: 80, name: 'HIKVISION', hardware: 'DS-2CD1043G2-I' },
      { host: '192.168.1.40', port: 8000, name: 'Dahua VTO', hardware: 'VTO2202F-P' },
    ].filter((d) => allowed(d.host));
    const { store } = await setup({ sources: [{ ...goodSource }], driverFactory: onvifFactory, discover });
    store.videoScans.push({ id: 'scan-1', home_id: 'home-1', status: 'pending' });
    assert.ok(await until(() => store.videoScans[0].status === 'done', 8000));
    assert.deepEqual(store.videoScans[0].results.map((r) => [r.host, r.already_added]), [['192.168.1.20', true], ['192.168.1.40', false]]);
  });
});

describe('Configuration du boîtier', () => {
  const base = { SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'k', INTEGRATION_ID: 'i' };
  test('ADAPTER=video active l\'UDI, STUN par défaut', () => {
    const c = loadConfig({ ...base, ADAPTER: 'video', VIDEO_TURN_URLS: 'turn:turn.solea-dz.com:3478', VIDEO_TURN_SECRET: 's' });
    assert.equal(c.video.relay, true);
    assert.deepEqual(c.video.turn, ['turn:turn.solea-dz.com:3478']);
    assert.deepEqual(c.video.stun, ['stun:stun.l.google.com:19302']);
    assert.equal(loadConfig({ ...base, ADAPTER: 'simulator' }).video, null);
    assert.ok(loadConfig({ ...base, ADAPTER: 'simulator', VIDEO: 'true' }).video);
  });
  test('jamais sur la passerelle de la plateforme', () => {
    assert.throws(() => loadConfig({ ...base, ADAPTER: 'tuya_cloud', PLATFORM: 'true', TUYA_ACCESS_ID: 'a', TUYA_ACCESS_SECRET: 'b', VIDEO: 'true' }), /boîtier/);
  });
});
