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
import { DahuaDriver, dahuaPlayback, dahuaTime } from '../src/udi/drivers/dahua_driver.js';
import { RtspDriver } from '../src/udi/drivers/rtsp_driver.js';
import { discoverDahua, parseDhipReply, sameSerial, searchPacket } from '../src/udi/dahua/dhip.js';
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
  function startServer({ user = 'admin', pass = 'S3cret!', sdp, closeAfter401 = false, resetAll = false } = {}) {
    return new Promise((resolve) => {
      server = net.createServer((sock) => {
        sock.on('data', (buf) => {
          if (resetAll) return sock.resetAndDestroy();
          if (sock.writableEnded) return; // connexion déjà fermée après 401 : demande ignorée
          const req = buf.toString();
          const cseq = /CSeq: (\d+)/.exec(req)[1];
          const auth = /Authorization: Digest (.*)\r\n/.exec(req)?.[1];
          const md5 = (s) => createHash('md5').update(s).digest('hex');
          const uri = /uri="([^"]+)"/.exec(auth ?? '')?.[1];
          const valid = auth && md5(`${md5(`${user}:cam:${pass}`)}:n1:${md5(`DESCRIBE:${uri}`)}`) === /response="([^"]+)"/.exec(auth)[1];
          if (!valid) {
            sock.write(`RTSP/1.0 401 Unauthorized\r\nCSeq: ${cseq}\r\nWWW-Authenticate: Digest realm="cam", nonce="n1"\r\n\r\n`);
            if (closeAfter401) sock.end();
            return;
          }
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

  test('caméra qui ferme la connexion après 401 (Dahua) : nouvelle connexion identifiée', async () => {
    const port = await startServer({ sdp: SDP, closeAfter401: true });
    const r = await probeRtsp(`rtsp://127.0.0.1:${port}/cam/realmonitor?channel=1&subtype=0`, { username: 'admin', password: 'S3cret!' });
    assert.equal(r.ok, true);
  });

  test('porte 554 (Hero A1) : nonce valable seulement sur sa connexion, demande identifiée sur la même', async () => {
    let conns = 0;
    let n = 0;
    await new Promise((resolve) => {
      server = net.createServer((sock) => {
        conns += 1;
        const nonce = `n${++n}`;
        sock.on('data', (buf) => {
          const req = buf.toString();
          const cseq = /CSeq: (\d+)/.exec(req)[1];
          const auth = /Authorization: Digest (.*)\r\n/.exec(req)?.[1];
          const md5 = (x) => createHash('md5').update(x).digest('hex');
          const uri = /uri="([^"]+)"/.exec(auth ?? '')?.[1];
          const ok = auth && auth.includes(`nonce="${nonce}"`) && md5(`${md5('admin:cam:S3cret!')}:${nonce}:${md5(`DESCRIBE:${uri}`)}`) === /response="([^"]+)"/.exec(auth)[1];
          if (!ok) return sock.write(`RTSP/1.0 401 Unauthorized\r\nCSeq: ${cseq}\r\nWWW-Authenticate: Digest realm="cam", nonce="${nonce}"\r\n\r\n`);
          sock.write(`RTSP/1.0 200 OK\r\nCSeq: ${cseq}\r\nContent-Type: application/sdp\r\nContent-Length: ${Buffer.byteLength(SDP)}\r\n\r\n${SDP}`);
        });
      }).listen(0, '127.0.0.1', resolve);
    });
    const r = await probeRtsp(`rtsp://127.0.0.1:${server.address().port}/cam/realmonitor?channel=1&subtype=0`, { username: 'admin', password: 'S3cret!' });
    assert.equal(r.ok, true);
    assert.equal(conns, 1);
  });

  test('connexion coupée dès la première demande : RTSP désactivé expliqué', async () => {
    const port = await startServer({ sdp: SDP, resetAll: true });
    const r = await probeRtsp(`rtsp://127.0.0.1:${port}/x`, { username: 'admin', password: 'S3cret!' });
    assert.equal(r.ok, false);
    assert.match(r.error, /dès la première demande/);
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

  test('RTSP tunnelé dans HTTP (rtsp+http, porte 80) avec Digest', async () => {
    const md5 = (x) => createHash('md5').update(x).digest('hex');
    const gets = new Map();
    const nonces = new Map(); // nonce propre à chaque tunnel, comme la Hero A1
    let tunnels = 0;
    server = net.createServer((sock) => {
      let buf = Buffer.alloc(0);
      let role = null;
      let cookie = null;
      sock.on('data', (chunk) => {
        buf = Buffer.concat([buf, chunk]);
        if (!role) {
          const sep = buf.indexOf('\r\n\r\n');
          if (sep === -1) return;
          const head = buf.subarray(0, sep).toString();
          cookie = /x-sessioncookie: (\S+)/i.exec(head)[1];
          role = head.startsWith('GET') ? 'get' : 'post';
          buf = buf.subarray(sep + 4);
          if (role === 'get') {
            assert.match(head, /Accept: application\/x-rtsp-tunnelled/);
            tunnels++;
            gets.set(cookie, sock);
            sock.write('HTTP/1.0 200 OK\r\nContent-Type: application/x-rtsp-tunnelled\r\n\r\n');
          }
        }
        if (role !== 'post') return;
        const req = Buffer.from(buf.toString(), 'base64').toString();
        if (!req.endsWith('\r\n\r\n')) return;
        buf = Buffer.alloc(0);
        const out = gets.get(cookie);
        const cseq = /CSeq: (\d+)/.exec(req)[1];
        assert.match(req, /^DESCRIBE rtsp:\/\/127\.0\.0\.1:\d+\/cam\/realmonitor\?channel=1&subtype=0&unicast=true&proto=Onvif RTSP/);
        const auth = /Authorization: Digest (.*)\r\n/.exec(req)?.[1];
        const uri = /uri="([^"]+)"/.exec(auth ?? '')?.[1];
        if (!nonces.has(cookie)) nonces.set(cookie, `n-${cookie}`);
        const nonce = nonces.get(cookie);
        const ok = auth && /nonce="([^"]+)"/.exec(auth)[1] === nonce && md5(`${md5('admin:cam:S3cret!')}:${nonce}:${md5(`DESCRIBE:${uri}`)}`) === /response="([^"]+)"/.exec(auth)[1];
        if (!ok) out.write(`RTSP/1.0 401 Unauthorized\r\nCSeq: ${cseq}\r\nWWW-Authenticate: Digest realm="cam", nonce="${nonce}"\r\n\r\n`);
        else out.write(`RTSP/1.0 200 OK\r\nCSeq: ${cseq}\r\nContent-Length: ${Buffer.byteLength(SDP)}\r\n\r\n${SDP}`);
      });
    });
    const port = await new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));
    const url = `rtsp+http://127.0.0.1:${port}/cam/realmonitor?channel=1&subtype=0&unicast=true&proto=Onvif`;
    const r = await probeRtsp(url, { username: 'admin', password: 'S3cret!' });
    assert.deepEqual(r, { ok: true, status: 200, video: { codec: 'H264' }, audio: { codec: 'MPEG4-GENERIC' } });
    assert.equal(tunnels, 1, 'demande identifiée dans le même tunnel');
    assert.equal((await probeRtsp(url, { username: 'admin', password: 'faux' })).status, 401);
    assert.equal(withCredentials('rtsp+http://192.168.1.2:80/cam?x=1', 'admin', 'p@ss'), 'rtsp+http://admin:p%40ss@192.168.1.2:80/cam?x=1');
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
      if (u.pathname.startsWith('/v3/config/paths/add/')) {
        const conf = JSON.parse(init.body);
        // Comme le vrai MediaMTX avec pathDefaults.sourceOnDemand: yes (config/mediamtx.yml).
        if (conf.source === 'publisher' && conf.sourceOnDemand !== false) return Response.json({ error: "'sourceOnDemand' is useless when source is 'publisher'" }, { status: 400 });
        return paths.set(name, conf), new Response('', { status: 200 });
      }
      if (u.pathname.startsWith('/v3/config/paths/patch/')) return paths.set(name, { ...paths.get(name), ...JSON.parse(init.body) }), new Response('', { status: 200 });
      if (u.pathname.startsWith('/v3/config/paths/delete/')) return paths.delete(name), new Response('', { status: 200 });
      if (u.pathname === '/v3/config/global/patch') return new Response('', { status: 200 });
      if (u.pathname === '/v3/paths/list') return Response.json({ items: [] });
      if (u.pathname.endsWith('/whep') || u.pathname.endsWith('/whip')) {
        const p = u.pathname.split('/')[1];
        const kind = u.pathname.split('/')[2];
        if (!paths.has(p)) return new Response('', { status: 404 });
        return new Response(kind === "whep" ? "v=0 réponse" : "v=0 réponse whip", { status: 201, headers: { location: `/${p}/${kind}/sess-1` } });
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
  test('boîtier : parler à travers la caméra (voix du téléphone relayée, chemin supprimé à la fin)', async () => {
    const store = new MemoryStore();
    store.videoSources = [{ id: 'tk-1', home_id: 'home-1', name: 'Salon', category: 'camera', driver: 'dahua', host: '192.168.1.45', username: 'admin', password: 'TEST1234' }];
    const { mtx, paths } = globalThis.__fakeMtx();
    const soap = (inner) => new Response(`<?xml version="1.0"?><s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body>${inner}</s:Body></s:Envelope>`, { status: 200 });
    const fetchImpl = async (url, opts = {}) => {
      const body = String(opts.body ?? '');
      if (body.includes('GetCapabilities')) return soap('<GetCapabilitiesResponse><Capabilities><Media><XAddr>http://192.168.1.45/onvif/media_service</XAddr></Media><DeviceIO><AudioOutputs>1</AudioOutputs></DeviceIO></Capabilities></GetCapabilitiesResponse>');
      if (body.includes('GetSystemDateAndTime')) return soap('<R/>');
      return new Response('', { status: 404 });
    };
    const relays = [];
    const hub = new UdiHub({
      mediamtx: mtx,
      allowedSubnet: subnetFilter(''),
      driverFactory: (s, deps) => new DahuaDriver(s, { ...deps, probe: async () => ({ ok: true, status: 200, video: { codec: 'H264' }, audio: { codec: 'PCMU' } }), fetchImpl }),
      talkRelayFactory: (opts) => {
        const relay = { opts, stopped: false, packets: 0, start: async () => ({ codec: 'PCMA', from: 'PCMA' }), stop: async () => void (relay.stopped = true) };
        relays.push(relay);
        return relay;
      },
      clock: () => new Date(2026, 10, 4, 12, 30).getTime(),
      retryMinMs: 30,
      retryMaxMs: 100,
    });
    const adapter = addUdi(new VideoOnlyAdapter(), hub);
    bridge = new Bridge({ store, adapter, config: { integrationId: 'integ-1', commandTimeoutMs: 300, pendingMaxAgeMs: 30_000, pollIntervalMs: 50, automationRefreshMs: 60_000, runAutomations: false, runTimeTriggers: false } });
    await bridge.start();
    assert.ok(await until(() => store.videoSources[0].status === 'online' && store.devices.size === 1));
    const deviceId = [...store.devices.keys()][0];
    assert.equal([...hub.runners.values()][0].flags.audio_output, true, 'haut-parleur annoncé par ONVIF');
    store.videoSessions.push({ id: 'talk-sess-1', home_id: 'home-1', device_id: deviceId, quality: 'talk', offer: 'v=0 voix', status: 'offer', created_at: new Date(2026, 10, 4, 12, 30).toISOString() });
    await hub.processSessions();
    assert.ok(await until(() => store.videoSessions[0].status === 'answered'));
    assert.equal(store.videoSessions[0].answer, 'v=0 réponse whip', 'le téléphone publie sa voix (WHIP)');
    const path = [...paths.keys()].find((k) => k.includes('_talk_'));
    assert.deepEqual(paths.get(path), { source: 'publisher', sourceOnDemand: false }, 'chemin accepté malgré sourceOnDemand: yes par défaut');
    assert.equal(relays.length, 1);
    assert.equal(relays[0].opts.cameraUrl, 'rtsp://192.168.1.45:554/cam/realmonitor?channel=1&subtype=0', 'adresse de la caméra sans identifiants');
    assert.equal(relays[0].opts.sourceUrl, `rtsp://127.0.0.1:8554/${path}`, 'voix lue sur le relais local seulement');
    store.videoSessions[0].status = 'closed';
    await hub.processSessions();
    assert.equal(relays[0].stopped, true, 'relais arrêté');
    assert.equal(paths.has(path), false, 'chemin de la voix supprimé');
  });

  test('boîtier : orientation de la caméra (PTZ ONVIF), ordres dépassés ignorés', async () => {
    const store = new MemoryStore();
    store.videoSources = [{ id: 'ptz-1', home_id: 'home-1', name: 'Salon', category: 'camera', driver: 'dahua', host: '192.168.1.45', username: 'admin', password: 'TEST1234' }];
    const { mtx } = globalThis.__fakeMtx();
    const sent = [];
    const soap = (inner) => new Response(`<?xml version="1.0"?><s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope" xmlns:tt="http://www.onvif.org/ver10/schema"><s:Body>${inner}</s:Body></s:Envelope>`, { status: 200 });
    const fetchImpl = async (url, opts = {}) => {
      const body = String(opts.body ?? '');
      if (!body.includes('Envelope')) return new Response('', { status: 404 });
      if (body.includes('GetSystemDateAndTime')) return soap('<GetSystemDateAndTimeResponse/>');
      if (body.includes('GetCapabilities')) return soap('<GetCapabilitiesResponse><Capabilities><Media><XAddr>http://192.168.1.45/onvif/media_service</XAddr></Media><PTZ><XAddr>http://192.168.1.45/onvif/ptz_service</XAddr></PTZ></Capabilities></GetCapabilitiesResponse>');
      if (body.includes('GetProfiles')) return soap('<GetProfilesResponse><Profiles token="MediaProfile000"><Name>Main</Name><PTZConfiguration token="PTZ000"/></Profiles></GetProfilesResponse>');
      for (const op of ['ContinuousMove', 'Stop', 'GotoPreset']) {
        if (body.includes(`<tptz:${op}`)) {
          sent.push({ op, url, body });
          return soap(`<${op}Response/>`);
        }
      }
      return new Response('', { status: 500 });
    };
    let now = new Date(2026, 10, 4, 12, 30).getTime();
    const hub = new UdiHub({
      mediamtx: mtx,
      allowedSubnet: subnetFilter(''),
      driverFactory: (s, deps) => new DahuaDriver(s, { ...deps, probe: async () => ({ ok: true, status: 200, video: { codec: 'H264' } }), fetchImpl }),
      clock: () => now,
      retryMinMs: 30,
      retryMaxMs: 100,
    });
    const adapter = addUdi(new VideoOnlyAdapter(), hub);
    bridge = new Bridge({ store, adapter, config: { integrationId: 'integ-1', commandTimeoutMs: 300, pendingMaxAgeMs: 30_000, pollIntervalMs: 50, automationRefreshMs: 60_000, runAutomations: false, runTimeTriggers: false } });
    await bridge.start();
    assert.ok(await until(() => store.videoSources[0].status === 'online' && store.devices.size === 1));
    const deviceId = [...store.devices.keys()][0];
    const iso = (ms) => new Date(ms).toISOString();
    store.ptzCommands.push(
      { id: 'p1', home_id: 'home-1', device_id: deviceId, action: 'move', pan: -0.5, tilt: 0, status: 'pending', created_at: iso(now - 9000) },
      { id: 'p2', home_id: 'home-1', device_id: deviceId, action: 'move', pan: 0.5, tilt: 0, status: 'pending', created_at: iso(now - 300) },
      { id: 'p3', home_id: 'home-1', device_id: deviceId, action: 'move', pan: 0, tilt: 0.8, status: 'pending', created_at: iso(now - 100) },
    );
    await hub.processPtz();
    assert.deepEqual(store.ptzCommands.map((c) => c.status), ['failed', 'failed', 'done'], 'seul le dernier déplacement récent est envoyé');
    assert.equal(sent.length, 1);
    assert.match(sent[0].url, /ptz_service/);
    assert.match(sent[0].body, /MediaProfile000/);
    assert.match(sent[0].body, /<tt:PanTilt x="0.00" y="0.80"\/>/);
    assert.match(sent[0].body, /<tptz:Timeout>PT1S<\/tptz:Timeout>/, 'la caméra s\'arrête seule si l\'ordre d\'arrêt se perd');
    store.ptzCommands.push(
      { id: 'p4', home_id: 'home-1', device_id: deviceId, action: 'stop', status: 'pending', created_at: iso(now) },
      { id: 'p5', home_id: 'home-1', device_id: deviceId, action: 'preset', preset: '1', status: 'pending', created_at: iso(now) },
    );
    await hub.processPtz();
    assert.deepEqual(sent.slice(1).map((x) => x.op), ['Stop', 'GotoPreset']);
    assert.match(sent[2].body, /<tptz:PresetToken>1<\/tptz:PresetToken>/);
    // Appui court : « move » puis « stop » déjà en attente → le mouvement part quand même.
    store.ptzCommands.push(
      { id: 'p6', home_id: 'home-1', device_id: deviceId, action: 'move', pan: 0.5, tilt: 0, status: 'pending', created_at: iso(now) },
      { id: 'p7', home_id: 'home-1', device_id: deviceId, action: 'stop', status: 'pending', created_at: iso(now) },
    );
    await hub.processPtz();
    assert.deepEqual(sent.slice(3).map((x) => x.op), ['ContinuousMove', 'Stop']);
  });

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

describe('Dahua : ajout par QR code', () => {
  const REPLY = (info) => {
    const body = Buffer.from(JSON.stringify({ mac: 'aa:bb:cc:00:11:22', method: 'client.notifyDevInfo', params: { deviceInfo: info } }));
    const head = Buffer.alloc(32);
    head.writeUInt32LE(0x20, 0);
    head.write('DHIP', 4, 'ascii');
    head.writeUInt32LE(body.length, 16);
    head.writeUInt32LE(body.length, 24);
    return Buffer.concat([head, body]);
  };
  const HERO = { DeviceType: 'DH-H5A', SerialNo: '9K00AB1CDEF2345', Mac: 'AA:BB:CC:00:11:22', HttpPort: 80, IPv4Address: { IPAddress: '192.168.1.45' } };

  test('paquet de recherche DHIP : en-tête de 32 octets et JSON', () => {
    const p = searchPacket();
    assert.equal(p.toString('ascii', 4, 8), 'DHIP');
    assert.equal(p.readUInt32LE(16), p.length - 32);
    assert.equal(p.readUInt32LE(24), p.length - 32);
    assert.deepEqual(JSON.parse(p.subarray(32).toString()), { method: 'DHDiscover.search', params: { mac: '', uni: 1 } });
  });

  test('réponse : adresse, numéro de série, MAC, modèle ; datagrammes étrangers ignorés', () => {
    assert.deepEqual(parseDhipReply(REPLY(HERO)), { host: '192.168.1.45', serial: '9K00AB1CDEF2345', mac: 'aa:bb:cc:00:11:22', model: 'DH-H5A', httpPort: 80, name: 'DH-H5A', vendor: 'Dahua' });
    assert.equal(parseDhipReply(searchPacket()), null, 'notre propre recherche renvoyée par le multicast');
    assert.equal(parseDhipReply(Buffer.from('bonjour')), null);
    assert.equal(sameSerial(' 9k00ab1cdef2345', '9K00AB1CDEF2345'), true);
  });

  test('recherche : multicast + diffusion, dédoublonnée, sous-réseaux respectés', async () => {
    const sent = [];
    const sock = new EventEmitter();
    sock.bind = (port, cb) => {
      assert.equal(port, 37810);
      setImmediate(cb);
    };
    sock.setBroadcast = () => {};
    sock.addMembership = () => {};
    sock.send = (_b, _o, _l, port, address) => {
      sent.push(`${address}:${port}`);
      setImmediate(() => {
        sock.emit('message', REPLY(HERO), { address: '192.168.1.45' });
        sock.emit('message', REPLY({ ...HERO, SerialNo: 'X2', IPv4Address: { IPAddress: '8.8.8.8' } }), { address: '8.8.8.8' });
      });
    };
    sock.close = () => {};
    const found = await discoverDahua({ timeoutMs: 80, allowed: subnetFilter(''), socketFactory: () => sock });
    assert.deepEqual(sent, ['239.255.255.251:37810', '255.255.255.255:37810']);
    assert.deepEqual(found.map((f) => f.serial), ['9K00AB1CDEF2345']);
  });

  test('pilote : caméra retrouvée par son numéro de série, flux Dahua, code de sécurité', async () => {
    const probes = [];
    const probe = async (url, creds) => {
      probes.push({ url, creds });
      return { ok: true, status: 200, video: { codec: 'H264' }, audio: { codec: 'PCMA' } };
    };
    const fetchImpl = async () => new Response('', { status: 404 });
    const d = new DahuaDriver(
      { id: 'q1', serial: '9K00AB1CDEF2345', model: 'DH-H5A', username: 'admin', password: 'TEST1234' },
      { locate: async (sn) => (sn === '9K00AB1CDEF2345' ? { host: '192.168.1.45', model: 'DH-H5A', mac: 'aa:bb:cc:00:11:22' } : null), probe, fetchImpl },
    );
    await d.connect();
    assert.equal(probes[0].url, 'rtsp://192.168.1.45:554/cam/realmonitor?channel=1&subtype=0');
    assert.deepEqual(probes[0].creds, { username: 'admin', password: 'TEST1234' });
    assert.deepEqual(d.streams(), { main: probes[0].url, sub: 'rtsp://192.168.1.45:554/cam/realmonitor?channel=1&subtype=1' });
    assert.equal(d.capabilities().video_stream, true);
    assert.equal(d.capabilities().audio_input, true);
    assert.equal(d.capabilities().snapshot, false, 'pas d\'image fixe annoncée sans preuve');
    assert.deepEqual(d.located(), { host: '192.168.1.45', mac: 'aa:bb:cc:00:11:22' });
  });

  test('pilote : introuvable, code refusé, adresse changée', async () => {
    const lost = new DahuaDriver({ id: 'q2', serial: 'NOPE', password: 'x' }, { locate: async () => null });
    await assert.rejects(lost.connect(), (e) => e.kind === 'unreachable' && /introuvable/.test(e.message));
    const diag = await lost.diagnose();
    assert.equal(diag.steps[0].step, 'réseau');
    assert.equal(diag.steps[0].ok, false);

    const refused = new DahuaDriver({ id: 'q3', serial: 'S1', password: 'faux' }, { locate: async () => ({ host: '192.168.1.45' }), probe: async () => ({ ok: false, status: 401, error: 'Identifiants refusés' }) });
    await assert.rejects(refused.connect(), (e) => e.kind === 'auth');

    // La box a donné une nouvelle adresse : la caméra est retrouvée par son numéro de série.
    const moved = new DahuaDriver(
      { id: 'q4', serial: 'S1', host: '192.168.1.45', password: 'ok' },
      {
        locate: async () => ({ host: '192.168.1.77' }),
        probe: async (url) => (url.includes('192.168.1.77') ? { ok: true, status: 200, video: { codec: 'H265' } } : { ok: false, error: 'Hôte injoignable' }),
        fetchImpl: async () => new Response('', { status: 404 }),
      },
    );
    await moved.connect();
    assert.equal(moved.located().host, '192.168.1.77');
  });

  test('pilote : Hero qui coupe sans identifiants, flux « authbasic » avec Basic d\'emblée', async () => {
    const seen = [];
    const probe = async (url, opts) => {
      seen.push({ url, basicFirst: opts.basicFirst === true });
      return opts.basicFirst && url.includes('&authbasic=') ? { ok: true, status: 200, video: { codec: 'H265' } } : { ok: false, error: 'La caméra coupe le flux RTSP dès la première demande' };
    };
    const d = new DahuaDriver({ id: 'q7', serial: 'S1', host: '192.168.1.45', password: 'TEST1234' }, { probe, fetchImpl: async () => new Response('', { status: 404 }), onvif: () => assert.fail('ONVIF inutile') });
    await d.connect();
    const b64 = Buffer.from('admin:TEST1234').toString('base64');
    assert.equal(d.streams().main, `rtsp://192.168.1.45:554/cam/realmonitor?channel=1&subtype=0&authbasic=${b64}`);
    assert.equal(seen[1].basicFirst, true);
    await d.ping();
    assert.equal(seen.at(-1).basicFirst, true);
  });

  test('pilote : porte 554 fermée (Hero A1), flux tunnelé sur la porte 80 et image ONVIF', async () => {
    const tunnel = 'rtsp+http://192.168.1.45:80/cam/realmonitor?channel=1&subtype=0&unicast=true&proto=Onvif';
    const probe = async (url) => (url === tunnel ? { ok: true, status: 200, video: { codec: 'H265' }, audio: { codec: 'MPEG4-GENERIC' } } : { ok: false, error: 'La caméra coupe le flux RTSP dès la première demande' });
    const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xd9]);
    const asked = [];
    const fetchImpl = async (url) => {
      asked.push(url);
      return url.includes('onvifsnapshot') ? new Response(jpeg, { status: 200, headers: { 'content-type': 'image/jpeg' } }) : new Response('', { status: 404 });
    };
    const d = new DahuaDriver({ id: 'q9', serial: 'S1', host: '192.168.1.45', password: 'TEST1234' }, { probe, fetchImpl, onvif: () => assert.fail('ONVIF inutile') });
    await d.connect();
    assert.equal(d.streams().main, tunnel);
    assert.match(d.streams().sub, /^rtsp\+http:\/\/192\.168\.1\.45:80\/.*subtype=1/);
    assert.equal(d.capabilities().video_stream, true);
    assert.equal(d.capabilities().snapshot, true);
    asked.length = 0;
    await d.snapshot();
    assert.deepEqual(asked, ['http://192.168.1.45/onvifsnapshot/media_service/snapshot?channel=1&subtype=0']);
    await d.ping();
  });

  test('pilote : vidéo refusée partout, images fixes quand même', async () => {
    const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xd9]);
    const d = new DahuaDriver(
      { id: 'q8', serial: 'S1', host: '192.168.1.45', password: 'TEST1234' },
      {
        probe: async () => ({ ok: false, error: 'La caméra coupe le flux RTSP dès la première demande' }),
        onvif: () => ({ connect: async () => {}, rtspCheck: { ok: false, error: 'coupé aussi' }, streams: () => ({}) }),
        fetchImpl: async () => new Response(jpeg, { status: 200, headers: { 'content-type': 'image/jpeg' } }),
      },
    );
    await d.connect();
    assert.equal(d.capabilities().video_stream, false);
    assert.equal(d.capabilities().snapshot, true);
    const diag = await d.diagnose();
    assert.deepEqual(diag.steps.map((x) => [x.step, x.ok]), [['rtsp', false], ['image', true], ['identification', true]]);
    await d.ping();
  });

  test('pilote : adresse Dahua standard coupée, flux trouvé par ONVIF', async () => {
    const onvifUrl = 'rtsp://192.168.1.45:554/cam/realmonitor?channel=1&subtype=0&unicast=true&proto=Onvif';
    const probe = async (url) => (url === onvifUrl ? { ok: true, status: 200, video: { codec: 'H264' } } : { ok: false, error: 'La caméra coupe le flux RTSP dès la première demande' });
    let asked = null;
    const d = new DahuaDriver(
      { id: 'q5', serial: 'S1', host: '192.168.1.45', password: 'TEST1234' },
      {
        probe,
        fetchImpl: async () => new Response('', { status: 404 }),
        onvif: (src) => {
          asked = src;
          return { connect: async () => {}, rtspCheck: { ok: true, status: 200, video: { codec: 'H264' } }, streams: () => ({ main: onvifUrl, sub: null }) };
        },
      },
    );
    await d.connect();
    assert.deepEqual([asked.host, asked.port, asked.username, asked.password], ['192.168.1.45', 80, 'admin', 'TEST1234']);
    assert.equal(d.streams().main, onvifUrl);
    assert.equal(d.capabilities().video_stream, true);

    const both = new DahuaDriver(
      { id: 'q6', serial: 'S1', host: '192.168.1.45', password: 'x' },
      { probe, onvif: () => ({ connect: async () => { throw new Error('Identifiants refusés par l\'appareil'); } }) },
    );
    await assert.rejects(both.connect(), (e) => /Essai ONVIF : Identifiants refusés/.test(e.message));
  });

  test('boîtier : adresse trouvée enregistrée, recherche réseau avec les caméras Dahua', async () => {
    const store = new MemoryStore();
    store.videoSources = [{ id: 'qr-1', home_id: 'home-1', name: 'Salon', category: 'camera', driver: 'dahua', serial: '9K00AB1CDEF2345', host: null, username: 'admin', password: 'TEST1234' }];
    const { mtx, paths } = globalThis.__fakeMtx();
    let searches = 0;
    const hub = new UdiHub({
      mediamtx: mtx,
      allowedSubnet: subnetFilter(''),
      discoverDahua: async () => {
        searches++;
        return [{ host: '192.168.1.45', serial: '9K00AB1CDEF2345', mac: 'aa:bb:cc:00:11:22', model: 'DH-H5A', httpPort: 80, name: 'DH-H5A' }, { host: '192.168.1.46', serial: 'OTHER', model: 'IPC-HFW1230S', httpPort: 80, name: 'IPC' }];
      },
      driverFactory: (s, deps) =>
        new DahuaDriver(s, { ...deps, probe: async () => ({ ok: true, status: 200, video: { codec: 'H264' } }), fetchImpl: async () => new Response('', { status: 404 }) }),
      retryMinMs: 30,
      retryMaxMs: 100,
    });
    const adapter = addUdi(new VideoOnlyAdapter(), hub);
    bridge = new Bridge({ store, adapter, config: { integrationId: 'integ-1', commandTimeoutMs: 300, pendingMaxAgeMs: 30_000, pollIntervalMs: 50, automationRefreshMs: 60_000, runAutomations: false, runTimeTriggers: false } });
    await bridge.start();
    assert.ok(await until(() => store.videoSources[0].status === 'online'));
    assert.equal(store.videoSources[0].host, '192.168.1.45');
    assert.equal(store.videoSources[0].manufacturer, 'Dahua');
    assert.equal(store.videoSources[0].diagnostic.steps[0].detail, "Trouvée à l'adresse 192.168.1.45");
    assert.equal(paths.get('solea_qr1_main').source, 'rtsp://admin:TEST1234@192.168.1.45:554/cam/realmonitor?channel=1&subtype=0');
    // L'adresse enregistrée ne relance pas le pilote.
    const runner = hub.runners.get('qr-1');
    await hub.refreshSources();
    assert.equal(hub.runners.get('qr-1'), runner);

    store.videoScans.push({ id: 'scan-d', home_id: 'home-1', status: 'pending' });
    assert.ok(await until(() => store.videoScans[0].status === 'done', 8000));
    assert.deepEqual(store.videoScans[0].results.map((r) => [r.host, r.protocol, r.serial, r.already_added]), [
      ['192.168.1.45', 'dahua', '9K00AB1CDEF2345', true],
      ['192.168.1.46', 'dahua', 'OTHER', false],
    ]);
    assert.ok(searches >= 1);
  });

  test('carte mémoire : adresse de relecture au format Dahua, même porte que le direct', () => {
    const start = new Date(2026, 10, 4, 17, 20, 0);
    const end = new Date(2026, 10, 4, 17, 25, 5);
    assert.equal(dahuaTime(start), '2026_11_04_17_20_00');
    assert.equal(dahuaPlayback('rtsp://h:554/cam/realmonitor?channel=1&subtype=0', 'h', start, end), 'rtsp://h:554/cam/playback?channel=1&starttime=2026_11_04_17_20_00&endtime=2026_11_04_17_25_05');
    assert.equal(dahuaPlayback('rtsp+http://h:80/cam/realmonitor?channel=1', 'h', start, end), 'rtsp+http://h:80/cam/playback?channel=1&starttime=2026_11_04_17_20_00&endtime=2026_11_04_17_25_05');
    assert.match(dahuaPlayback('rtsp://h:554/cam/realmonitor?channel=1&subtype=0&authbasic=QUJD', 'h', start, end), /&authbasic=QUJD$/);
  });

  test('carte mémoire : heures enregistrées d\'une journée (404 = rien), codec lu', async () => {
    const probe = async (url) => {
      if (url.includes('realmonitor')) return { ok: true, status: 200, video: { codec: 'H264' } };
      const h = Number(/starttime=\d{4}_\d\d_\d\d_(\d\d)/.exec(url)[1]);
      if (h === 9) return { ok: true, status: 200, video: { codec: 'H265' }, audio: { codec: 'MPEG4-GENERIC' } };
      if (h === 14) return { ok: true, status: 200, video: { codec: 'H264' }, audio: { codec: 'PCMU' } };
      return { ok: false, status: 404, error: 'Le flux RTSP répond 404' };
    };
    const d = new DahuaDriver({ id: 'pb1', host: '192.168.1.45', password: 'x' }, { probe, fetchImpl: async () => new Response('', { status: 404 }) });
    await d.connect();
    const slots = await d.recordedSlots(new Date(2026, 10, 4), { now: new Date(2026, 10, 4, 20, 30) });
    assert.deepEqual(slots.map((x) => [new Date(x.start).getHours(), x.codec]), [[9, 'H265'], [14, 'H264']]);
    // Les heures pas encore arrivées ne sont pas demandées.
    let asked = 0;
    const d2 = new DahuaDriver({ id: 'pb2', host: 'h', password: 'x' }, { probe: async (u) => (u.includes('playback') && asked++, { ok: false, status: 404 }), fetchImpl: async () => new Response('', { status: 404 }) });
    assert.deepEqual(await d2.recordedSlots(new Date(2026, 10, 4), { now: new Date(2026, 10, 4, 2, 10) }), []);
    assert.equal(asked, 3);
  });

  test('boîtier : historique demandé, puis relecture d\'un passage en WebRTC (chemin supprimé à la fin)', async () => {
    const store = new MemoryStore();
    store.videoSources = [{ id: 'sd-1', home_id: 'home-1', name: 'Salon', category: 'camera', driver: 'dahua', host: '192.168.1.45', username: 'admin', password: 'TEST1234' }];
    const { mtx, paths } = globalThis.__fakeMtx();
    const probe = async (url) => {
      if (url.includes('realmonitor')) return { ok: true, status: 200, video: { codec: 'H264' }, audio: { codec: 'PCMU' } };
      if (url.includes('starttime=2026_11_04_10')) return { ok: true, status: 200, video: { codec: 'H264' } };
      if (url.includes('starttime=2026_11_04_11')) return { ok: true, status: 200, video: { codec: 'H265' } };
      return { ok: false, status: 404, error: 'Le flux RTSP répond 404' };
    };
    const hub = new UdiHub({
      mediamtx: mtx,
      allowedSubnet: subnetFilter(''),
      driverFactory: (s, deps) => new DahuaDriver(s, { ...deps, probe, fetchImpl: async () => new Response('', { status: 404 }) }),
      clock: () => new Date(2026, 10, 4, 12, 30).getTime(),
      retryMinMs: 30,
      retryMaxMs: 100,
    });
    const adapter = addUdi(new VideoOnlyAdapter(), hub);
    bridge = new Bridge({ store, adapter, config: { integrationId: 'integ-1', commandTimeoutMs: 300, pendingMaxAgeMs: 30_000, pollIntervalMs: 50, automationRefreshMs: 60_000, runAutomations: false, runTimeTriggers: false } });
    await bridge.start();
    assert.ok(await until(() => store.videoSources[0].status === 'online' && store.devices.size === 1));
    const deviceId = [...store.devices.keys()][0];
    assert.ok(await until(() => store.capabilities.some((c) => c.device_id === deviceId && c.metadata?.playback === 'sd')));

    store.recordingQueries.push({ id: 'rq-1', home_id: 'home-1', device_id: deviceId, day: '2026-11-04', status: 'pending' });
    await hub.processRecordings();
    assert.equal(store.recordingQueries[0].status, 'done');
    assert.deepEqual(store.recordingQueries[0].slots.map((x) => [new Date(x.start).getHours(), x.codec]), [[10, 'H264'], [11, 'H265']]);

    const created = new Date(2026, 10, 4, 12, 30).toISOString();
    const at = (h, m = 0) => new Date(2026, 10, 4, h, m).toISOString();
    store.videoSessions.push({ id: 'pb-sess-1', home_id: 'home-1', device_id: deviceId, quality: 'playback', playback_start: at(10, 15), offer: 'v=0 offre', status: 'offer', created_at: created });
    await hub.processSessions();
    assert.ok(await until(() => store.videoSessions[0].status === 'answered'));
    const path = [...paths.keys()].find((k) => k.includes('_pb_'));
    assert.equal(paths.get(path).source, 'rtsp://admin:TEST1234@192.168.1.45:554/cam/playback?channel=1&starttime=2026_11_04_10_15_00&endtime=2026_11_04_11_15_00');
    store.videoSessions[0].status = 'closed';
    await hub.processSessions();
    assert.equal(paths.has(path), false, 'chemin de relecture supprimé');

    // Rien d'enregistré, ou format H.265 : refus expliqué.
    store.videoSessions.push({ id: 'pb-sess-2', home_id: 'home-1', device_id: deviceId, quality: 'playback', playback_start: at(8), offer: 'v=0', status: 'offer', created_at: created });
    store.videoSessions.push({ id: 'pb-sess-3', home_id: 'home-1', device_id: deviceId, quality: 'playback', playback_start: at(11), offer: 'v=0', status: 'offer', created_at: created });
    await hub.processSessions();
    assert.ok(await until(() => store.videoSessions[1].status === 'failed' && store.videoSessions[2].status === 'failed'));
    assert.match(store.videoSessions[1].error, /Rien n'est enregistré/);
    assert.match(store.videoSessions[2].error, /H\.265/);
  });

  let bridge;
  afterEach(async () => {
    await bridge?.stop();
    bridge = null;
  });
});
