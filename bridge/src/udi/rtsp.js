// Vérification d'un flux RTSP sans lecteur vidéo : requête DESCRIBE (avec Digest/Basic si
// besoin) et lecture du SDP pour connaître les codecs vidéo et audio réellement proposés.
// Sert au diagnostic : « le flux répond », « H.264 », « avec micro ».
// Le canal audio retour (parler à la caméra) n'est pas testé ici : il viendra avec la phase SIP.

import net from 'node:net';

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
function rtspRequest(socket, { method, url, cseq, headers = {} }) {
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
    socket.write(`${lines.join('\r\n')}\r\n\r\n`);
  });
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
  if (u.protocol !== 'rtsp:') return { ok: false, error: 'Adresse rtsp:// attendue' };
  const user = username ?? decodeURIComponent(u.username);
  const pass = password ?? decodeURIComponent(u.password);
  u.username = '';
  u.password = '';
  const url = u.toString();

  // Une connexion neuve par requête : certaines caméras (Dahua grand public) ferment la
  // connexion après avoir répondu 401, la requête identifiée doit donc repartir de zéro.
  const describe = async (cseq, extra = {}) => {
    const socket = connect({ host: u.hostname, port: Number(u.port) || 554 });
    socket.setTimeout?.(timeoutMs);
    let timer;
    const timeout = new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error('délai dépassé')), timeoutMs);
      socket.once('timeout', () => reject(new Error('délai dépassé')));
    });
    try {
      await Promise.race([new Promise((resolve, reject) => (socket.once('connect', resolve), socket.once('error', reject))), timeout]);
      return await Promise.race([rtspRequest(socket, { method: 'DESCRIBE', url, cseq, headers: { Accept: 'application/sdp', ...extra } }), timeout]);
    } finally {
      clearTimeout(timer);
      socket.destroy();
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
  const u = new URL(rawUrl);
  if (username) {
    u.username = encodeURIComponent(username);
    u.password = encodeURIComponent(password ?? '');
  }
  return u.toString();
}
