// Session RTSP complète (DESCRIBE → SETUP → PLAY) sur une seule connexion TCP, avec les
// paquets RTP « entrelacés » ($ canal longueur) dans la même connexion.
//
// Sert à « parler à travers la caméra » : le boîtier lit la voix du téléphone sur le relais
// local (MediaMTX) et la renvoie à la caméra par sa voie de retour audio ONVIF
// (« Require: www.onvif.org/ver20/backchannel »), en G.711, sans jamais sortir de la maison.

import net from 'node:net';

import { basicHeader, digestHeader, parseChallenge } from './auth.js';

export const BACKCHANNEL = 'www.onvif.org/ver20/backchannel';

/** Pistes d'un SDP : type, sens, contrôle, type de charge utile et codec. */
export function parseSdpMedia(sdp) {
  const medias = [];
  let cur = null;
  let sessionControl = null;
  for (const line of String(sdp).split(/\r?\n/)) {
    if (line.startsWith('m=')) {
      const [kind, , , pt] = line.slice(2).split(/\s+/);
      cur = { kind, pt: Number(pt), codec: null, rate: null, control: null, direction: 'sendrecv' };
      medias.push(cur);
    } else if (line.startsWith('a=control:')) {
      if (cur) cur.control = line.slice(10).trim();
      else sessionControl = line.slice(10).trim();
    } else if (cur && /^a=(sendonly|recvonly|sendrecv|inactive)$/.test(line.trim())) {
      cur.direction = line.trim().slice(2);
    } else if (cur && line.startsWith('a=rtpmap:')) {
      const m = /^a=rtpmap:(\d+)\s+([^/\s]+)\/(\d+)/.exec(line);
      if (m && Number(m[1]) === cur.pt && !cur.codec) {
        cur.codec = m[2].toUpperCase();
        cur.rate = Number(m[3]);
      }
    }
  }
  // Types statiques sans rtpmap (RFC 3551) : 0 = PCMU, 8 = PCMA.
  for (const m of medias) {
    if (!m.codec && m.pt === 0) (m.codec = 'PCMU'), (m.rate = 8000);
    if (!m.codec && m.pt === 8) (m.codec = 'PCMA'), (m.rate = 8000);
  }
  return { medias, sessionControl };
}

/** Adresse de contrôle d'une piste, relative à l'adresse de base (Content-Base) si besoin. */
export function controlUrl(base, control) {
  if (!control || control === '*') return base;
  if (/^rtsp:\/\//i.test(control)) return control;
  return base.endsWith('/') ? `${base}${control}` : `${base}/${control}`;
}

export class RtspSession {
  /**
   * @param {string} url adresse rtsp:// (sans identifiants)
   * @param {{username?:string, password?:string, require?:string|null, timeoutMs?:number, connect?:Function}} [opts]
   */
  constructor(url, { username = '', password = '', require = null, timeoutMs = 6000, connect = (o) => net.connect(o) } = {}) {
    this.url = url;
    this.username = username;
    this.password = password;
    this.require = require;
    this.timeoutMs = timeoutMs;
    this.connect = connect;
    this.socket = null;
    this.cseq = 0;
    this.session = null;
    this.auth = null; // défi Digest/Basic retenu pour toute la connexion
    this.buf = Buffer.alloc(0);
    this.waiting = null;
    this.onRtp = null; // (canal, paquet) => void
    this.closed = false;
    this.keepalive = null;
  }

  async open() {
    const u = new URL(this.url);
    this.socket = this.connect({ host: u.hostname, port: Number(u.port) || 554 });
    this.socket.setNoDelay?.(true);
    await new Promise((resolve, reject) => {
      this.socket.once('connect', resolve);
      this.socket.once('error', reject);
    });
    this.socket.on('data', (c) => this.#onData(c));
    const gone = (e) => {
      this.closed = true;
      clearInterval(this.keepalive);
      this.waiting?.reject(e instanceof Error ? e : new Error('connexion fermée'));
      this.waiting = null;
      this.onClose?.();
    };
    this.socket.on('error', gone);
    this.socket.on('close', gone);
  }

  #onData(chunk) {
    this.buf = Buffer.concat([this.buf, chunk]);
    for (;;) {
      if (this.buf.length === 0) return;
      if (this.buf[0] === 0x24) {
        if (this.buf.length < 4) return;
        const len = this.buf.readUInt16BE(2);
        if (this.buf.length < 4 + len) return;
        const ch = this.buf[1];
        const pkt = this.buf.subarray(4, 4 + len);
        this.buf = this.buf.subarray(4 + len);
        this.onRtp?.(ch, pkt);
        continue;
      }
      const sep = this.buf.indexOf('\r\n\r\n');
      if (sep === -1) return;
      const head = this.buf.subarray(0, sep).toString('utf8').split('\r\n');
      const headers = {};
      for (const l of head.slice(1)) {
        const i = l.indexOf(':');
        if (i > 0) headers[l.slice(0, i).trim().toLowerCase()] = l.slice(i + 1).trim();
      }
      const len = Number(headers['content-length'] ?? 0);
      if (this.buf.length < sep + 4 + len) return;
      const body = this.buf.subarray(sep + 4, sep + 4 + len).toString('utf8');
      this.buf = this.buf.subarray(sep + 4 + len);
      const status = Number(/^RTSP\/1\.\d\s+(\d+)/.exec(head[0])?.[1]);
      // Requête de la caméra (rare) ou réponse inattendue : ignorée.
      if (!status) continue;
      const w = this.waiting;
      this.waiting = null;
      w?.resolve({ status, headers, body });
    }
  }

  #send(method, url, headers) {
    return new Promise((resolve, reject) => {
      if (this.closed) return reject(new Error('connexion fermée'));
      const cseq = ++this.cseq;
      const timer = setTimeout(() => {
        this.waiting = null;
        reject(new Error('délai dépassé'));
      }, this.timeoutMs);
      this.waiting = {
        resolve: (r) => (clearTimeout(timer), resolve(r)),
        reject: (e) => (clearTimeout(timer), reject(e)),
      };
      const all = { CSeq: cseq, 'User-Agent': 'Solea-UDI', ...(this.require ? { Require: this.require } : {}), ...(this.session ? { Session: this.session } : {}), ...headers };
      if (this.auth) all.Authorization = this.#authorization(method, url);
      this.socket.write(`${method} ${url} RTSP/1.0\r\n${Object.entries(all).map(([k, v]) => `${k}: ${v}`).join('\r\n')}\r\n\r\n`);
    });
  }

  #authorization(method, url) {
    if (this.auth.scheme === 'digest') {
      this.nc = (this.nc ?? 0) + 1;
      return digestHeader({ method, uri: url, username: this.username, password: this.password, challenge: this.auth, nc: this.nc });
    }
    return basicHeader(this.username, this.password);
  }

  /** Requête avec identification sur la même connexion (la Hero A1 lie son « nonce » à la connexion). */
  async request(method, url, headers = {}) {
    let r = await this.#send(method, url, headers);
    // Premier refus (ou « nonce » périmé) : nouveau défi, un seul nouvel essai.
    if (r.status === 401 && this.username) {
      const challenge = parseChallenge(r.headers['www-authenticate'] ?? '');
      if (challenge) {
        this.auth = challenge;
        this.nc = 0;
        r = await this.#send(method, url, headers);
      }
    }
    return r;
  }

  async describe() {
    const r = await this.request('DESCRIBE', this.url, { Accept: 'application/sdp' });
    if (r.status !== 200) throw Object.assign(new Error(r.status === 401 ? 'Code de sécurité refusé par la caméra' : `RTSP ${r.status}`), { status: r.status });
    const base = (r.headers['content-base'] ?? r.headers['content-location'] ?? this.url).replace(/\/$/, '');
    return { ...parseSdpMedia(r.body), base, sdp: r.body };
  }

  async setup(url, channel) {
    const r = await this.request('SETUP', url, { Transport: `RTP/AVP/TCP;unicast;interleaved=${channel}-${channel + 1}` });
    if (r.status !== 200) throw Object.assign(new Error(`RTSP SETUP ${r.status}`), { status: r.status });
    const s = r.headers.session ?? '';
    this.session = s.split(';')[0] || this.session;
    const timeout = Number(/timeout=(\d+)/.exec(s)?.[1]) || 60;
    return { timeout };
  }

  async play(url, { keepaliveSeconds = 30 } = {}) {
    const r = await this.request('PLAY', url, { Range: 'npt=0.000-' });
    if (r.status !== 200) throw Object.assign(new Error(`RTSP PLAY ${r.status}`), { status: r.status });
    // Sans signe de vie, la caméra ferme la session au bout d'environ une minute.
    this.keepalive = setInterval(() => this.request('GET_PARAMETER', url).catch(() => {}), keepaliveSeconds * 1000);
    this.keepalive.unref?.();
  }

  sendRtp(channel, packet) {
    if (this.closed || !this.socket) return false;
    const head = Buffer.from([0x24, channel, (packet.length >> 8) & 0xff, packet.length & 0xff]);
    this.socket.write(Buffer.concat([head, packet]));
    return true;
  }

  async close() {
    if (this.closed) return;
    clearInterval(this.keepalive);
    if (this.session) await this.request('TEARDOWN', this.url).catch(() => {});
    this.closed = true;
    this.socket?.destroy();
  }
}

// ---------------------------------------------------------------- G.711
/** µ-law → A-law, octet par octet (table de l'UIT-T G.711). */
const ULAW_TO_ALAW = (() => {
  const t = Buffer.alloc(256);
  for (let u = 0; u < 256; u++) {
    // µ-law → PCM 16 bits
    const x = ~u & 0xff;
    const sign = x & 0x80;
    const exp = (x >> 4) & 0x07;
    const mant = x & 0x0f;
    let pcm = (((mant << 3) + 0x84) << exp) - 0x84;
    if (sign) pcm = -pcm;
    // PCM 16 bits → A-law
    let v = pcm;
    let mask = 0xd5;
    if (v < 0) {
      mask = 0x55;
      v = -v - 1;
    }
    v >>= 3; // 13 bits
    let seg = 0;
    for (let lim = 0x1f; v > lim && seg < 7; lim = (lim << 1) | 1) seg++;
    const a = seg === 0 ? (v >> 1) & 0x0f : (seg << 4) | ((v >> seg) & 0x0f);
    t[u] = (a ^ mask) & 0xff;
  }
  return t;
})();

export function ulawToAlaw(buf) {
  const out = Buffer.alloc(buf.length);
  for (let i = 0; i < buf.length; i++) out[i] = ULAW_TO_ALAW[buf[i]];
  return out;
}

const ALAW_TO_ULAW = (() => {
  const t = Buffer.alloc(256);
  for (let u = 0; u < 256; u++) t[ULAW_TO_ALAW[u]] = u;
  return t;
})();

export function alawToUlaw(buf) {
  const out = Buffer.alloc(buf.length);
  for (let i = 0; i < buf.length; i++) out[i] = ALAW_TO_ULAW[buf[i]];
  return out;
}

/**
 * Paquet RTP réécrit pour la caméra : type de charge utile de sa voie de retour, numéro de
 * séquence et horodatage conservés, identifiant de source fixe ; extensions retirées.
 */
export function rewriteRtp(packet, { pt, ssrc, convert = null }) {
  if (packet.length < 12 || packet[0] >> 6 !== 2) return null;
  const cc = packet[0] & 0x0f;
  const ext = (packet[0] & 0x10) !== 0;
  let off = 12 + cc * 4;
  if (ext) {
    if (packet.length < off + 4) return null;
    off += 4 + packet.readUInt16BE(off + 2) * 4;
  }
  let payload = packet.subarray(off);
  if (packet[0] & 0x20) {
    const pad = packet[packet.length - 1];
    payload = payload.subarray(0, Math.max(0, payload.length - pad));
  }
  if (convert) payload = convert(payload);
  const head = Buffer.alloc(12);
  head[0] = 0x80;
  head[1] = (packet[1] & 0x80) | (pt & 0x7f);
  head.writeUInt16BE(packet.readUInt16BE(2), 2);
  head.writeUInt32BE(packet.readUInt32BE(4), 4);
  head.writeUInt32BE(ssrc >>> 0, 8);
  return Buffer.concat([head, payload]);
}

/** Octet G.711 → échantillon PCM 16 bits (UIT-T G.711). */
export function g711Decode(codec, byte) {
  if (codec === 'PCMU') {
    const x = ~byte & 0xff;
    const exp = (x >> 4) & 0x07;
    const pcm = ((((x & 0x0f) << 3) + 0x84) << exp) - 0x84;
    return x & 0x80 && pcm ? -pcm : pcm;
  }
  const a = byte ^ 0x55;
  const seg = (a >> 4) & 0x07;
  let v = (a & 0x0f) << 4;
  v = seg === 0 ? v + 8 : (v + 0x108) << (seg - 1);
  return a & 0x80 ? v : -v;
}

/** Échantillon PCM 16 bits → octet G.711 (UIT-T G.711). */
export function g711Encode(codec, pcm) {
  if (codec === 'PCMU') {
    const sign = pcm < 0 ? 0x80 : 0;
    let v = Math.min(Math.abs(pcm), 32635) + 0x84;
    let exp = 7;
    for (let mask = 0x4000; (v & mask) === 0 && exp > 0; mask >>= 1) exp--;
    return ~(sign | (exp << 4) | ((v >> (exp + 3)) & 0x0f)) & 0xff;
  }
  let mask = 0xd5;
  let v = pcm;
  if (v < 0) {
    mask = 0x55;
    v = -v - 1;
  }
  v = Math.min(v, 32767) >> 3;
  let seg = 0;
  for (let lim = 0x1f; v > lim && seg < 7; lim = (lim << 1) | 1) seg++;
  const a = seg === 0 ? (v >> 1) & 0x0f : (seg << 4) | ((v >> seg) & 0x0f);
  return (a ^ mask) & 0xff;
}

/**
 * Conversion G.711 avec amplification : la voix du téléphone arrive souvent trop faible pour
 * que la caméra (haut-parleur en semi-duplex automatique) bascule sur « parler ». Gain appliqué
 * octet par octet via une table de 256 valeurs, avec un limiteur doux pour ne pas saturer.
 * Renvoie null si rien à faire (même codec, gain 1).
 */
export function g711Converter(from, to, gain = 1) {
  if (from === to && gain === 1) return null;
  const table = Buffer.alloc(256);
  const knee = 24000;
  for (let b = 0; b < 256; b++) {
    let x = g711Decode(from, b) * gain;
    const ax = Math.abs(x);
    // Au-delà du genou, compression douce vers 32767 au lieu d'un écrêtage brutal.
    if (ax > knee) x = Math.sign(x) * (knee + (32767 - knee) * Math.tanh((ax - knee) / (32767 - knee)));
    table[b] = g711Encode(to, Math.round(x));
  }
  return (buf) => {
    const out = Buffer.alloc(buf.length);
    for (let i = 0; i < buf.length; i++) out[i] = table[buf[i]];
    return out;
  };
}
