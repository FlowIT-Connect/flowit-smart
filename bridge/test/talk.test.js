import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import net from 'node:net';
import { after, describe, test } from 'node:test';

import { setLogLevel } from '../src/log.js';
import { alawToUlaw, g711Converter, g711Decode, g711Encode, parseSdpMedia, rewriteRtp, ulawToAlaw } from '../src/udi/rtsp_session.js';
import { TalkRelay } from '../src/udi/talk.js';

setLogLevel('error');

const md5 = (s) => createHash('md5').update(s).digest('hex');

/** Petit serveur RTSP de test : réponses selon la méthode, paquets entrelacés reçus et envoyés. */
function rtspServer(handler) {
  const servers = [];
  const server = net.createServer((sock) => {
    server.sockets.add(sock);
    let buf = Buffer.alloc(0);
    const ctx = { sock, nonce: Math.random().toString(16).slice(2), rtp: [] };
    sock.on('error', () => {});
    sock.on('data', (chunk) => {
      buf = Buffer.concat([buf, chunk]);
      for (;;) {
        if (buf[0] === 0x24) {
          if (buf.length < 4) return;
          const len = buf.readUInt16BE(2);
          if (buf.length < 4 + len) return;
          server.received.push({ ch: buf[1], pkt: Buffer.from(buf.subarray(4, 4 + len)) });
          buf = buf.subarray(4 + len);
          continue;
        }
        const sep = buf.indexOf('\r\n\r\n');
        if (sep === -1) return;
        const lines = buf.subarray(0, sep).toString().split('\r\n');
        buf = buf.subarray(sep + 4);
        const [method, url] = lines[0].split(' ');
        const headers = {};
        for (const l of lines.slice(1)) headers[l.slice(0, l.indexOf(':')).toLowerCase()] = l.slice(l.indexOf(':') + 1).trim();
        const reply = (status, extra = {}, body = '') => {
          if (sock.writableEnded) return;
          const h = { CSeq: headers.cseq, ...extra, ...(body ? { 'Content-Length': Buffer.byteLength(body) } : {}) };
          sock.write(`RTSP/1.0 ${status} X\r\n${Object.entries(h).map(([k, v]) => `${k}: ${v}`).join('\r\n')}\r\n\r\n${body}`);
        };
        server.requests.push({ method, url, headers });
        handler({ method, url, headers, reply, ctx });
      }
    });
  });
  server.requests = [];
  server.sockets = new Set();
  server.received = [];
  servers.push(server);
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

const rtp = (seq, payload, pt = 0) => {
  const h = Buffer.alloc(12);
  h[0] = 0x80;
  h[1] = pt;
  h.writeUInt16BE(seq, 2);
  h.writeUInt32BE(seq * 160, 4);
  h.writeUInt32BE(0x1234, 8);
  return Buffer.concat([h, payload]);
};

describe('parler à travers la caméra', () => {
  const open = [];
  after(() => open.forEach((s) => (s.sockets.forEach((c) => c.destroy()), s.close())));

  test('G.711 : µ-law → A-law garde le son (comparaison en PCM)', () => {
    const ulaw = (u) => {
      const x = ~u & 0xff;
      const pcm = ((((x & 0x0f) << 3) + 0x84) << ((x >> 4) & 7)) - 0x84;
      return x & 0x80 ? -pcm : pcm;
    };
    const alaw = (a) => {
      const x = a ^ 0x55;
      const seg = (x >> 4) & 7;
      let pcm = seg === 0 ? ((x & 0x0f) << 4) + 8 : (((x & 0x0f) << 4) + 0x108) << (seg - 1);
      return x & 0x80 ? pcm : -pcm;
    };
    for (let u = 0; u < 256; u++) {
      const want = ulaw(u);
      const got = alaw(ulawToAlaw(Buffer.from([u]))[0]);
      assert.ok(Math.abs(got - want) <= Math.max(16, Math.abs(want) * 0.07), `µ-law ${u} : ${want} → ${got}`);
    }
    assert.equal(ulawToAlaw(Buffer.from([0xff]))[0], 0xd5, 'silence → silence');
    for (const u of [0x00, 0x80, 0x10, 0x9a, 0xee]) assert.ok(Math.abs(ulawToAlaw(alawToUlaw(ulawToAlaw(Buffer.from([u]))))[0] - ulawToAlaw(Buffer.from([u]))[0]) === 0, `aller-retour ${u}`);
  });

  test('voix amplifiée : plus forte sans saturer, silence gardé, tables G.711 cohérentes', () => {
    for (const codec of ['PCMA', 'PCMU']) {
      for (let b = 0; b < 256; b++) {
        const pcm = g711Decode(codec, b);
        assert.equal(g711Decode(codec, g711Encode(codec, pcm)), pcm, `${codec} aller-retour ${b}`);
      }
    }
    // Les anciennes tables µ-law ↔ A-law et le nouveau décodeur donnent le même son.
    for (let u = 0; u < 256; u++) {
      const a = ulawToAlaw(Buffer.from([u]))[0];
      assert.ok(Math.abs(g711Decode('PCMA', a) - g711Decode('PCMU', u)) <= Math.max(64, Math.abs(g711Decode('PCMU', u)) / 16), `µ-law ${u}`);
    }
    assert.equal(g711Converter('PCMA', 'PCMA', 1), null, 'rien à faire');
    const boost = g711Converter('PCMU', 'PCMA', 3);
    const quiet = g711Encode('PCMU', 1000);
    const loud = g711Encode('PCMU', 30000);
    const [q, l, z] = boost(Buffer.from([quiet, loud, 0xff]));
    assert.ok(Math.abs(g711Decode('PCMA', q) - 3000) < 200, 'voix faible ×3');
    assert.ok(g711Decode('PCMA', l) > 30000 && g711Decode('PCMA', l) <= 32767, 'voix forte limitée sans débordement');
    assert.equal(g711Decode('PCMA', z), g711Decode('PCMA', 0xd5), 'silence → silence');
    const neg = g711Decode('PCMA', boost(Buffer.from([g711Encode('PCMU', -1000)]))[0]);
    assert.ok(Math.abs(neg + 3000) < 200, 'négatif amplifié aussi');
  });

  test('SDP : voie de retour ONVIF repérée (piste « sendonly » en PCMA)', () => {
    const sdp = 'v=0\r\nm=video 0 RTP/AVP 96\r\na=rtpmap:96 H264/90000\r\na=control:trackID=0\r\na=recvonly\r\nm=audio 0 RTP/AVP 0\r\na=control:trackID=1\r\na=recvonly\r\nm=audio 0 RTP/AVP 8\r\na=control:trackID=5\r\na=sendonly\r\n';
    const { medias } = parseSdpMedia(sdp);
    const back = TalkRelay.backchannelOf(medias);
    assert.deepEqual([back.control, back.codec, back.pt], ['trackID=5', 'PCMA', 8]);
  });

  test('RTP réécrit : type de la caméra, extension retirée, son converti', () => {
    const p = rtp(7, Buffer.from([0xff, 0xff]));
    p[0] |= 0x10; // extension d'en-tête : 4 octets d'en-tête + 1 mot
    const withExt = Buffer.concat([p.subarray(0, 12), Buffer.from([0xbe, 0xde, 0, 1, 1, 2, 3, 4]), p.subarray(12)]);
    const out = rewriteRtp(withExt, { pt: 8, ssrc: 99, convert: ulawToAlaw });
    assert.equal(out[1] & 0x7f, 8);
    assert.equal(out.readUInt16BE(2), 7);
    assert.equal(out.readUInt32BE(8), 99);
    assert.deepEqual([...out.subarray(12)], [0xd5, 0xd5]);
  });

  test('relais : attend la voix du téléphone, puis l\'envoie à la caméra (Digest sur la même connexion)', async () => {
    let describes = 0;
    const source = await rtspServer(({ method, url, reply, ctx }) => {
      if (method === 'DESCRIBE') {
        // Le téléphone n'a pas encore publié : 404, puis la piste arrive.
        if (++describes < 3) return reply(404);
        return reply(200, { 'Content-Base': `${url}/`, 'Content-Type': 'application/sdp' }, 'v=0\r\nm=audio 0 RTP/AVP 0\r\na=rtpmap:0 PCMU/8000\r\na=control:trackID=0\r\n');
      }
      if (method === 'SETUP') return reply(200, { Session: 'src1;timeout=60', Transport: 'RTP/AVP/TCP;interleaved=0-1' });
      if (method === 'PLAY') {
        reply(200, { Session: 'src1' });
        for (let i = 0; i < 3; i++) ctx.sock.write(Buffer.concat([Buffer.from([0x24, 0, 0, 14]), rtp(i, Buffer.from([0xff, 0xff]))]));
        ctx.sock.write(Buffer.concat([Buffer.from([0x24, 1, 0, 8]), Buffer.alloc(8)])); // RTCP : ignoré
        return;
      }
      reply(200);
    });
    const camera = await rtspServer(({ method, url, headers, reply, ctx }) => {
      if (headers.require !== 'www.onvif.org/ver20/backchannel') return reply(551);
      const auth = headers.authorization ?? '';
      const nonce = /nonce="([^"]+)"/.exec(auth)?.[1];
      if (nonce !== ctx.nonce) return reply(401, { 'WWW-Authenticate': `Digest realm="Login to CAM", nonce="${ctx.nonce}"` });
      const uri = /uri="([^"]+)"/.exec(auth)[1];
      const expected = md5(`${md5('admin:Login to CAM:TEST1234')}:${ctx.nonce}:${md5(`${method}:${uri}`)}`);
      if (/response="([^"]+)"/.exec(auth)[1] !== expected) return reply(401, { 'WWW-Authenticate': `Digest realm="Login to CAM", nonce="${ctx.nonce}"` });
      if (method === 'DESCRIBE') {
        return reply(200, { 'Content-Base': `${url}/`, 'Content-Type': 'application/sdp' },
          'v=0\r\nm=video 0 RTP/AVP 96\r\na=rtpmap:96 H264/90000\r\na=control:trackID=0\r\na=recvonly\r\nm=audio 0 RTP/AVP 0\r\na=control:trackID=1\r\na=recvonly\r\nm=audio 0 RTP/AVP 8\r\na=rtpmap:8 PCMA/8000\r\na=control:trackID=5\r\na=sendonly\r\n');
      }
      if (method === 'SETUP') return reply(200, { Session: 'cam9;timeout=60', Transport: 'RTP/AVP/TCP;interleaved=0-1' });
      reply(200, { Session: 'cam9' });
    });
    open.push(source, camera);

    const relay = new TalkRelay({
      cameraUrl: `rtsp://127.0.0.1:${camera.address().port}/cam/realmonitor?channel=1&subtype=0`,
      username: 'admin',
      password: 'TEST1234',
      sourceUrl: `rtsp://127.0.0.1:${source.address().port}/solea_x_talk_1`,
    });
    const info = await relay.start();
    assert.deepEqual(info, { codec: 'PCMA', from: 'PCMU', gain: 3 });
    const until = async (ok) => {
      for (let i = 0; i < 100 && !ok(); i++) await new Promise((r) => setTimeout(r, 10));
    };
    await until(() => camera.received.length >= 3);
    assert.equal(camera.received.length, 3, 'trois paquets de voix arrivés à la caméra, RTCP non relayé');
    for (const { ch, pkt } of camera.received) {
      assert.equal(ch, 0);
      assert.equal(pkt[1] & 0x7f, 8, 'type PCMA de la voie de retour');
      assert.deepEqual([...pkt.subarray(12)], [0xd5, 0xd5], 'son converti en A-law');
    }
    const setup = camera.requests.find((r) => r.method === 'SETUP' && r.headers.authorization);
    assert.match(setup.url, /trackID=5$/, 'seule la voie de retour est demandée à la caméra');
    assert.ok(describes >= 3, 'le relais a attendu que le téléphone publie');
    await relay.stop();
    await until(() => camera.requests.some((r) => r.method === 'TEARDOWN'));
    assert.ok(camera.requests.some((r) => r.method === 'TEARDOWN'), 'session de la caméra fermée proprement');
  });
});
