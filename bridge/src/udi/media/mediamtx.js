// Pilotage de MediaMTX (relais vidéo local) par son API v3 :
//   - un « chemin » par flux de caméra (source RTSP lue seulement quand quelqu'un regarde),
//   - WHEP : l'application obtient la vidéo en WebRTC sans jamais voir l'adresse RTSP.
// MediaMTX tourne sur le boîtier, son API et son point WHEP n'écoutent que sur 127.0.0.1 :
// seule la passerelle s'en sert. Seul le média WebRTC (UDP) sort, chiffré (DTLS-SRTP).

import { createHmac } from 'node:crypto';

export class MediaMtx {
  /** @param {{apiUrl?:string, webrtcUrl?:string, fetchImpl?:typeof fetch}} [opts] */
  constructor({ apiUrl = 'http://127.0.0.1:9997', webrtcUrl = 'http://127.0.0.1:8889', fetchImpl = (...a) => fetch(...a) } = {}) {
    this.apiUrl = apiUrl.replace(/\/$/, '');
    this.webrtcUrl = webrtcUrl.replace(/\/$/, '');
    this.fetchImpl = fetchImpl;
  }

  async #api(method, path, body) {
    const res = await this.fetchImpl(`${this.apiUrl}${path}`, {
      method,
      headers: body ? { 'Content-Type': 'application/json' } : {},
      body: body ? JSON.stringify(body) : undefined,
      signal: AbortSignal.timeout(5000),
    });
    const text = await res.text();
    return { status: res.status, ok: res.ok, json: text ? safeJson(text) : null };
  }

  /** MediaMTX répond-il ? */
  async health() {
    try {
      const r = await this.#api('GET', '/v3/paths/list');
      return r.ok;
    } catch {
      return false;
    }
  }

  /** Crée ou met à jour un chemin dont la source est un flux RTSP (lu à la demande). */
  async ensurePath(name, source) {
    const conf = { source, sourceOnDemand: true, rtspTransport: 'tcp' };
    const cur = await this.#api('GET', `/v3/config/paths/get/${encodeURIComponent(name)}`);
    if (cur.status === 404) {
      const r = await this.#api('POST', `/v3/config/paths/add/${encodeURIComponent(name)}`, conf);
      if (!r.ok) throw new Error(`MediaMTX : ajout du flux refusé (${r.status} ${r.json?.error ?? ''})`.trim());
      return 'added';
    }
    if (!cur.ok) throw new Error(`MediaMTX injoignable (${cur.status})`);
    if (cur.json?.source === source && cur.json?.sourceOnDemand === true) return 'unchanged';
    const r = await this.#api('PATCH', `/v3/config/paths/patch/${encodeURIComponent(name)}`, conf);
    if (!r.ok) throw new Error(`MediaMTX : mise à jour du flux refusée (${r.status})`);
    return 'updated';
  }

  async removePath(name) {
    const r = await this.#api('DELETE', `/v3/config/paths/delete/${encodeURIComponent(name)}`);
    return r.ok || r.status === 404;
  }

  /** Serveurs STUN/TURN utilisés par MediaMTX pour joindre l'application hors du réseau local. */
  async setIceServers(servers) {
    const webrtcICEServers2 = servers.flatMap((s) =>
      [].concat(s.urls).map((url) => ({ url, ...(s.username ? { username: s.username, password: s.credential ?? '' } : {}) })),
    );
    const r = await this.#api('PATCH', '/v3/config/global/patch', { webrtcICEServers2 });
    if (!r.ok) throw new Error(`MediaMTX : serveurs ICE refusés (${r.status})`);
  }

  /** Négociation WHEP : offre SDP de l'application → réponse SDP de MediaMTX. */
  async whep(name, offer) {
    const res = await this.fetchImpl(`${this.webrtcUrl}/${encodeURIComponent(name)}/whep`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/sdp' },
      body: offer,
      signal: AbortSignal.timeout(10_000),
    });
    const text = await res.text();
    if (res.status !== 201 && res.status !== 200) {
      throw new Error(res.status === 404 ? 'Flux vidéo introuvable sur le relais' : `Relais vidéo : négociation refusée (${res.status})`);
    }
    const location = res.headers.get('location');
    return { answer: text, location: location ? new URL(location, `${this.webrtcUrl}/`).toString() : null };
  }

  async closeSession(location) {
    if (!location) return;
    await this.fetchImpl(location, { method: 'DELETE', signal: AbortSignal.timeout(5000) }).catch(() => {});
  }
}

function safeJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

/** Nom de chemin MediaMTX d'une source : stable, sans caractère spécial, sans secret. */
export function pathName(sourceId, quality = 'main') {
  return `solea_${String(sourceId).replace(/[^a-zA-Z0-9]/g, '')}_${quality === 'sub' ? 'sub' : 'main'}`;
}

/**
 * Identifiants TURN temporaires (« TURN REST API », coturn avec use-auth-secret) :
 * l'application reçoit un mot de passe valable quelques heures, jamais le secret.
 */
export function turnCredentials(secret, { ttlSeconds = 6 * 3600, now = Date.now(), user = 'solea' } = {}) {
  const username = `${Math.floor(now / 1000) + ttlSeconds}:${user}`;
  const credential = createHmac('sha1', secret).update(username).digest('base64');
  return { username, credential, expiresAt: new Date((Math.floor(now / 1000) + ttlSeconds) * 1000).toISOString() };
}

/** Serveurs ICE à publier : STUN publics + TURN de l'exploitant si configuré. */
export function iceServers({ stun = [], turn = [], turnSecret = null, now = Date.now() } = {}) {
  const out = [];
  if (stun.length) out.push({ urls: stun });
  if (turn.length && turnSecret) {
    const c = turnCredentials(turnSecret, { now });
    out.push({ urls: turn, username: c.username, credential: c.credential });
  }
  return out;
}
