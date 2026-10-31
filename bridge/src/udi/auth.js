// Authentification HTTP « Basic » et « Digest » (RFC 7616 / 2617), utilisée pour les images
// fixes des caméras et visiophones (Hikvision, Dahua, Axis… exigent souvent Digest) et pour RTSP.

import { createHash, randomBytes } from 'node:crypto';

const md5 = (s) => createHash('md5').update(s).digest('hex');
const sha256 = (s) => createHash('sha256').update(s).digest('hex');

/** Analyse un en-tête WWW-Authenticate. Garde le premier défi Digest, sinon Basic. */
export function parseChallenge(header) {
  if (!header) return null;
  const challenges = [];
  const re = /(Digest|Basic)\s+((?:[a-z0-9_-]+\s*=\s*(?:"[^"]*"|[^,\s]+)\s*,?\s*)*)/gi;
  let m;
  while ((m = re.exec(header))) {
    const params = {};
    const pr = /([a-z0-9_-]+)\s*=\s*(?:"([^"]*)"|([^,\s]+))/gi;
    let p;
    while ((p = pr.exec(m[2]))) params[p[1].toLowerCase()] = p[2] ?? p[3];
    challenges.push({ scheme: m[1].toLowerCase(), ...params });
  }
  return challenges.find((c) => c.scheme === 'digest') ?? challenges[0] ?? null;
}

export function basicHeader(username, password) {
  return `Basic ${Buffer.from(`${username}:${password}`).toString('base64')}`;
}

/**
 * En-tête Authorization Digest pour une requête.
 * @param {{method:string, uri:string, username:string, password:string, challenge:any, nc?:number, cnonce?:string}} p
 */
export function digestHeader({ method, uri, username, password, challenge, nc = 1, cnonce = randomBytes(8).toString('hex') }) {
  const algorithm = (challenge.algorithm ?? 'MD5').toUpperCase();
  const hash = algorithm.startsWith('SHA-256') ? sha256 : md5;
  let ha1 = hash(`${username}:${challenge.realm}:${password}`);
  if (algorithm.endsWith('-SESS')) ha1 = hash(`${ha1}:${challenge.nonce}:${cnonce}`);
  const ha2 = hash(`${method}:${uri}`);
  const qop = challenge.qop?.split(',').map((q) => q.trim()).find((q) => q === 'auth');
  const ncHex = nc.toString(16).padStart(8, '0');
  const response = qop ? hash(`${ha1}:${challenge.nonce}:${ncHex}:${cnonce}:${qop}:${ha2}`) : hash(`${ha1}:${challenge.nonce}:${ha2}`);
  const parts = [
    `username="${username}"`,
    `realm="${challenge.realm}"`,
    `nonce="${challenge.nonce}"`,
    `uri="${uri}"`,
    `response="${response}"`,
  ];
  if (challenge.algorithm) parts.push(`algorithm=${challenge.algorithm}`);
  if (challenge.opaque) parts.push(`opaque="${challenge.opaque}"`);
  if (qop) parts.push(`qop=${qop}`, `nc=${ncHex}`, `cnonce="${cnonce}"`);
  return `Digest ${parts.join(', ')}`;
}

/** Retire les identifiants d'une URL (fetch les refuse) et les renvoie à part. */
export function splitCredentials(url) {
  const u = new URL(url);
  const creds = u.username || u.password ? { username: decodeURIComponent(u.username), password: decodeURIComponent(u.password) } : null;
  u.username = '';
  u.password = '';
  return { url: u.toString(), creds };
}

/**
 * fetch avec authentification : premier essai sans identifiants, puis, sur 401, réessai avec
 * Digest ou Basic selon le défi de l'appareil.
 */
export async function fetchWithAuth(fetchImpl, url, init = {}, creds = null) {
  const first = await fetchImpl(url, init);
  if (first.status !== 401 || !creds) return first;
  const challenge = parseChallenge(first.headers.get('www-authenticate'));
  await first.arrayBuffer().catch(() => {});
  if (!challenge) return first;
  const u = new URL(url);
  const authorization =
    challenge.scheme === 'digest'
      ? digestHeader({ method: init.method ?? 'GET', uri: `${u.pathname}${u.search}`, ...creds, challenge })
      : basicHeader(creds.username, creds.password);
  return fetchImpl(url, { ...init, headers: { ...(init.headers ?? {}), Authorization: authorization } });
}
