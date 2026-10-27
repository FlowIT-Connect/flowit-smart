// Client de l'API cloud Tuya (Tuya IoT Platform, « OpenAPI ») :
// https://developer.tuya.com/en/docs/iot/new-singnature?id=Kbw0q34cs2e5g
//
// Signature HMAC-SHA256 sur chaque requête ; le jeton d'accès est obtenu avec l'Access ID
// et l'Access Secret du projet cloud et renouvelé automatiquement. Aucun secret n'est journalisé.

import { createHash, createHmac, randomUUID } from 'node:crypto';

/** Data centers Tuya (le projet cloud et le compte Smart Life doivent être sur le même). */
export const TUYA_REGIONS = {
  eu: { url: 'https://openapi.tuyaeu.com', label: 'Central Europe (Algérie, Europe, Afrique)' },
  weu: { url: 'https://openapi-weaz.tuyaeu.com', label: 'Western Europe' },
  us: { url: 'https://openapi.tuyaus.com', label: 'Western America' },
  eus: { url: 'https://openapi-ueaz.tuyaus.com', label: 'Eastern America' },
  cn: { url: 'https://openapi.tuyacn.com', label: 'China' },
  in: { url: 'https://openapi.tuyain.com', label: 'India' },
};

const TOKEN_ERRORS = new Set([1010, 1011]); // jeton invalide ou expiré

/** Messages compréhensibles pour les erreurs les plus fréquentes à l'installation. */
const HINTS = {
  1004: 'Access ID ou Access Secret incorrect',
  1106: 'Accès refusé : vérifiez que le compte Smart Life est bien lié au projet cloud',
  2009: 'Appareil hors ligne',
  28841002: 'Abonnement « IoT Core » expiré : prolongez-le sur platform.tuya.com',
  28841004: 'Abonnement « IoT Core » expiré : prolongez-le sur platform.tuya.com',
  28841105: 'Le projet cloud n\'a pas accès à cette API : ajoutez le service « IoT Core »',
};

export class TuyaApiError extends Error {
  constructor(code, msg) {
    super(HINTS[code] ? `${HINTS[code]} (Tuya ${code})` : `Tuya ${code} : ${msg ?? 'erreur inconnue'}`);
    this.code = code;
  }
}

const sha256 = (s) => createHash('sha256').update(s).digest('hex');

/** Chemin + paramètres triés par nom, tel que signé par Tuya. */
export function canonicalPath(path, query = {}) {
  const keys = Object.keys(query).filter((k) => query[k] !== undefined && query[k] !== null && query[k] !== '').sort();
  if (!keys.length) return path;
  return `${path}?${keys.map((k) => `${k}=${query[k]}`).join('&')}`;
}

/** Signature Tuya : HMAC-SHA256(secret, clientId + accessToken + t + nonce + stringToSign), en majuscules. */
export function sign({ clientId, secret, accessToken = '', t, nonce = '', method, body = '', pathWithQuery }) {
  const stringToSign = [method.toUpperCase(), sha256(body), '', pathWithQuery].join('\n');
  return createHmac('sha256', secret).update(clientId + accessToken + t + nonce + stringToSign).digest('hex').toUpperCase();
}

export class TuyaClient {
  /**
   * @param {{accessId:string, accessSecret:string, baseUrl:string, fetchImpl?:typeof fetch, now?:()=>number}} opts
   */
  constructor({ accessId, accessSecret, baseUrl, fetchImpl = (...a) => fetch(...a), now = () => Date.now() }) {
    this.accessId = accessId;
    this.accessSecret = accessSecret;
    this.baseUrl = baseUrl.replace(/\/$/, '');
    this.fetchImpl = fetchImpl;
    this.now = now;
    this.token = null;
    this.tokenExpiresAt = 0;
    this.tokenPromise = null;
  }

  async #raw(method, path, { query, body, withToken = true } = {}) {
    const pathWithQuery = canonicalPath(path, query);
    const payload = body === undefined ? '' : JSON.stringify(body);
    const t = String(this.now());
    const nonce = randomUUID();
    const accessToken = withToken ? this.token : '';
    const headers = {
      client_id: this.accessId,
      t,
      nonce,
      sign_method: 'HMAC-SHA256',
      sign: sign({ clientId: this.accessId, secret: this.accessSecret, accessToken, t, nonce, method, body: payload, pathWithQuery }),
      ...(accessToken ? { access_token: accessToken } : {}),
      ...(payload ? { 'Content-Type': 'application/json' } : {}),
    };
    let res;
    try {
      res = await this.fetchImpl(this.baseUrl + pathWithQuery, { method, headers, ...(payload ? { body: payload } : {}), signal: AbortSignal.timeout(15_000) });
    } catch (e) {
      throw new Error(`Cloud Tuya injoignable (${e.message})`);
    }
    if (!res.ok) throw new Error(`Cloud Tuya : réponse HTTP ${res.status}`);
    return res.json();
  }

  async #ensureToken() {
    if (this.token && this.now() < this.tokenExpiresAt) return;
    this.tokenPromise ??= (async () => {
      try {
        const r = await this.#raw('GET', '/v1.0/token', { query: { grant_type: 1 }, withToken: false });
        if (!r.success) throw new TuyaApiError(r.code, r.msg);
        this.token = r.result.access_token;
        // Marge d'une minute avant l'expiration annoncée (en secondes).
        this.tokenExpiresAt = this.now() + Math.max(60, (r.result.expire_time ?? 7200) - 60) * 1000;
      } finally {
        this.tokenPromise = null;
      }
    })();
    await this.tokenPromise;
  }

  /** Requête authentifiée ; renvoie `result` ou lève TuyaApiError. */
  async request(method, path, opts = {}) {
    await this.#ensureToken();
    let r = await this.#raw(method, path, opts);
    if (!r.success && TOKEN_ERRORS.has(r.code)) {
      this.token = null;
      await this.#ensureToken();
      r = await this.#raw(method, path, opts);
    }
    if (!r.success) throw new TuyaApiError(r.code, r.msg);
    return r.result;
  }

  /** Appareils du (des) compte(s) Smart Life liés au projet cloud, avec leur état et `online`. */
  async listDevices() {
    const all = [];
    let lastRowKey;
    for (let page = 0; page < 50; page++) {
      const r = await this.request('GET', '/v1.0/iot-01/associated-users/devices', { query: { size: 100, last_row_key: lastRowKey } });
      all.push(...(r.devices ?? []));
      if (!r.has_more || !r.last_row_key) break;
      lastRowKey = r.last_row_key;
    }
    return all;
  }

  /** Fonctions pilotables et états lisibles d'un appareil (avec plages et échelles). */
  specifications(deviceId) {
    return this.request('GET', `/v1.0/devices/${encodeURIComponent(deviceId)}/specifications`);
  }

  /** État courant et `online` d'un appareil. */
  device(deviceId) {
    return this.request('GET', `/v1.0/devices/${encodeURIComponent(deviceId)}`);
  }

  sendCommands(deviceId, commands) {
    return this.request('POST', `/v1.0/devices/${encodeURIComponent(deviceId)}/commands`, { body: { commands } });
  }
}
