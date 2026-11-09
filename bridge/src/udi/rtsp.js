// Vérification d'un flux RTSP sans lecteur vidéo : requête DESCRIBE (avec Digest/Basic si
// besoin) et lecture du SDP pour connaître les codecs vidéo et audio réellement proposés.
// Sert au diagnostic : « le flux répond », « H.264 », « avec micro ».
// Le canal audio retour (parler à la caméra) n'est pas testé ici : il viendra avec la phase SIP.

import { randomBytes } from 'node:crypto';
import net from 'node:net';
import { PassThrough } from 'node:stream';

import { basicHeader, digestHeader, parseChallenge } from './auth.js';

/** Codecs d'un SDP : { video: {codec}|null, audio: {codec}|null }. */
export function parseSdp(sdp) {
  const medias = [];
  let current = null;
  for (const line of String(sdp).split(/\r?\n/)) {
    if (line.startsWith('m=')) {
      const [kind, , , pt] = line.slice(2).split(/\s+/);
      current = { kind, pt, codec: null };
      medias.push(current);
    } else if (current && line.startsWith('a=rtpmap:')) {
      const m = /^a=rtpmap:(\d+)\s+([^/\s]+)/.exec(line);
      if (m && m[1] === current.pt && !current.codec) current.codec = m[2].toUpperCase();
    }
  }
  const first = (kind) => {
    const m = medias.find((x) => x.kind === kind);
    return m ? { codec: m.codec } : null;
  };
  return { video: first('video'), audio: first('audio') };
}

/** Une requête RTSP sur une connexion ouverte → { status, headers, body }. */
function rtspRequest(socket, { method, url, cseq, headers = {} }, write = (text) => socket.write(text)) {
  return new Promise((resolve, reject) => {
    let buf = Buffer.alloc(0);
    const onData = (chunk) => {
      buf = Buffer.concat([buf, chunk]);
      const sep = buf.indexOf('\r\n\r\n');
      if (sep === -1) return;
      const head = buf.subarray(0, sep).toString('utf8').split('\r\n');
      const status = Number(/^RTSP\/1\.\d\s+(\d+)/.exec(head[0])?.[1]);
      const hdrs = {};
      for (const l of head.slice(1)) {
        const i = l.indexOf(':');
        if (i > 0) hdrs[l.slice(0, i).trim().toLowerCase()] = l.slice(i + 1).trim();
      }
      const len = Number(hdrs['content-length'] ?? 0);
      if (buf.length < sep + 4 + len) return;
      socket.off('data', onData);
      socket.off('error', reject);
      resolve({ status, headers: hdrs, body: buf.subarray(sep + 4, sep + 4 + len).toString('utf8') });
    };
    socket.on('data', onData);
    socket.once('error', reject);
    const lines = [`${method} ${url} RTSP/1.0`, `CSeq: ${cseq}`, 'User-Agent: Solea-UDI', ...Object.entries(headers).map(([k, v]) => `${k}: ${v}`)];
    write(`${lines.join('\r\n')}\r\n\r\n`);
  });
}

function connected(socket) {
  return new Promise((resolve, reject) => (socket.once('connect', resolve), socket.once('error', reject)));
}

/**
 * Canal RTSP « tunnelé » dans HTTP (méthode Apple QuickTime, adresses rtsp+http://) :
 * une connexion GET reçoit les réponses, une connexion POST porte les demandes en base64.
 * Certaines caméras (Dahua Hero A1) ferment la porte 554 mais acceptent ce tunnel sur la porte 80.
 * @returns {Promise<{read:PassThrough, write:(text:string)=>void, destroy:()=>void}>}
 */
async function openTunnel({ host, port, path, connect }) {
  const cookie = randomBytes(11).toString('hex');
  const read = new PassThrough();
  read.on('error', () => {}); // erreurs relayées aux demandes en cours, jamais fatales
  const get = connect({ host, port });
  let post = null;
  const destroy = () => {
    get.destroy();
    post?.destroy();
    read.destroy();
  };
  let head = Buffer.alloc(0);
  let open = false;
  get.on('data', (chunk) => {
    if (open) return read.write(chunk);
    head = Buffer.concat([head, chunk]);
    const sep = head.indexOf('\r\n\r\n');
    if (sep === -1) return;
    const status = Number(/^HTTP\/1\.\d\s+(\d+)/.exec(head.subarray(0, sep).toString('utf8'))?.[1]);
    if (status !== 200) return read.emit('error', new Error(`le tunnel HTTP répond ${status || 'mal'}`));
    open = true;
    if (head.length > sep + 4) read.write(head.subarray(sep + 4));
  });
  get.on('error', (e) => read.emit('error', e));
  get.on('close', () => read.emit('error', new Error('socket hang up')));
  try {
    await connected(get);
    get.write(
      [`GET ${path} HTTP/1.0`, 'User-Agent: Solea-UDI', `x-sessioncookie: ${cookie}`, 'Accept: application/x-rtsp-tunnelled', 'Pragma: no-cache', 'Cache-Control: no-cache'].join('\r\n') + '\r\n\r\n',
    );
    post = connect({ host, port });
    post.on('error', (e) => read.emit('error', e));
    await connected(post);
    post.write(
      [`POST ${path} HTTP/1.0`, 'User-Agent: Solea-UDI', `x-sessioncookie: ${cookie}`, 'Content-Type: application/x-rtsp-tunnelled', 'Pragma: no-cache', 'Cache-Control: no-cache', 'Content-Length: 32767', 'Expires: Sun, 9 Jan 1972 00:00:00 GMT'].join('\r\n') + '\r\n\r\n',
    );
  } catch (e) {
    destroy();
    throw e;
  }
  return { read, write: (text) => post.write(Buffer.from(text).toString('base64')), destroy };
}

/**
 * Vérifie un flux RTSP. Les identifiants peuvent être dans l'URL (rtsp://user:pass@hôte/…)
 * ou passés à part ; ils ne sont jamais renvoyés.
 * @returns {Promise<{ok:boolean, status?:number, error?:string, video?:any, audio?:any}>}
 */
export async function probeRtsp(rawUrl, { username, password, basicFirst = false, timeoutMs = 6000, connect = (opts) => net.connect(opts) } = {}) {
  let u;
  try {
    u = new URL(rawUrl);
  } catch {
    return { ok: false, error: 'Adresse RTSP invalide' };
  }
  const tunnel = u.protocol === 'rtsp+http:';
  if (u.protocol !== 'rtsp:' && !tunnel) return { ok: false, error: 'Adresse rtsp:// attendue' };
  const user = username ?? decodeURIComponent(u.username);
  const pass = password ?? decodeURIComponent(u.password);
  const port = Number(u.port) || (tunnel ? 80 : 554);
  // Dans le tunnel, les demandes RTSP portent l'adresse rtsp:// de la même porte.
  let url;
  if (tunnel) url = `rtsp://${u.hostname}:${port}${u.pathname}${u.search}`;
  else {
    u.username = '';
    u.password = '';
    url = u.toString();
  }

  // Une connexion neuve par requête : certaines caméras (Dahua grand public) ferment la
  // connexion après avoir répondu 401, la requête identifiée doit donc repartir de zéro.
  const describe = async (cseq, extra = {}) => {
    let timer;
    const timeout = new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error('délai dépassé')), timeoutMs);
    });
    let channel = null;
    const opening = tunnel
      ? openTunnel({ host: u.hostname, port, path: `${u.pathname}${u.search}`, connect })
      : (async () => {
          const socket = connect({ host: u.hostname, port });
          socket.setTimeout?.(timeoutMs);
          await connected(socket);
          return { read: socket, write: (text) => socket.write(text), destroy: () => socket.destroy() };
        })();
    opening.then((c) => (channel = c), () => null);
    try {
      channel = await Promise.race([opening, timeout]);
      return await Promise.race([rtspRequest(channel.read, { method: 'DESCRIBE', url, cseq, headers: { Accept: 'application/sdp', ...extra } }, channel.write), timeout]);
    } finally {
      clearTimeout(timer);
      if (channel) channel.destroy();
      else opening.then((c) => c.destroy(), () => null);
    }
  };

  let stage = 'connexion';
  try {
    // basicFirst : identifiants envoyés dès la première demande (certaines caméras Dahua grand
    // public coupent la connexion au lieu de répondre 401).
    let res = await describe(1, basicFirst && user ? { Authorization: basicHeader(user, pass) } : {});
    if (res.status === 401 && user) {
      stage = 'identification';
      const challenge = parseChallenge(res.headers['www-authenticate']);
      const authorization =
        challenge?.scheme === 'digest'
          ? digestHeader({ method: 'DESCRIBE', uri: url, username: user, password: pass, challenge })
          : basicHeader(user, pass);
      res = await describe(2, { Authorization: authorization });
    }
    if (res.status === 401) return { ok: false, status: 401, error: 'Identifiants refusés par le flux RTSP' };
    if (res.status !== 200) return { ok: false, status: res.status, error: `Le flux RTSP répond ${res.status}` };
    return { ok: true, status: 200, ...parseSdp(res.body) };
  } catch (e) {
    const cut = /ECONNRESET|socket hang up|EPIPE/i.test(e.message);
    if (cut && stage === 'identification') return { ok: false, error: `La caméra coupe le flux RTSP après l'envoi du mot de passe (${e.message})` };
    if (cut) return { ok: false, error: `La caméra coupe le flux RTSP dès la première demande : RTSP désactivé ou accès bloqué (${e.message})` };
    return { ok: false, error: `Flux RTSP injoignable (${e.message})` };
  }
}

/** Ajoute des identifiants à une URL RTSP (pour MediaMTX, sur la machine locale uniquement). */
export function withCredentials(rawUrl, username, password) {
  // rtsp+http:// (tunnel) : schéma non standard, identifiants insérés à la main.
  if (/^rtsp\+http:\/\//i.test(rawUrl) && username) {
    const rest = rawUrl.slice('rtsp+http://'.length).replace(/^[^/@]*@/, '');
    return `rtsp+http://${encodeURIComponent(username)}:${encodeURIComponent(password ?? '')}@${rest}`;
  }
  const u = new URL(rawUrl);
  if (username) {
    u.username = encodeURIComponent(username);
    u.password = encodeURIComponent(password ?? '');
  }
  return u.toString();
}
