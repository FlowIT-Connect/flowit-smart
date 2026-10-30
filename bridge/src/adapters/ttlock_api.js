// Client de l'API cloud TTLock (TTLock Open Platform, v3) : https://euopen.ttlock.com/document
//
// Connexion OAuth avec le compte de l'application TTLock (identifiant + mot de passe haché
// en MD5, comme l'exige TTLock) et les clés de l'application créée sur open.ttlock.com.
// Le jeton est renouvelé automatiquement. Aucun secret ni code d'accès n'est journalisé.

import { createHash } from 'node:crypto';

export const TTLOCK_DEFAULT_URL = 'https://euapi.ttlock.com';

const TOKEN_ERRORS = new Set([10003, 10004]); // jeton invalide ou expiré

/** Messages compréhensibles pour les erreurs les plus fréquentes. */
const HINTS = {
  1: 'Échec côté TTLock',
  10000: 'clientId invalide : vérifiez les clés de l\'application sur open.ttlock.com',
  10001: 'Client non autorisé : l\'application TTLock Open Platform n\'est pas encore approuvée',
  10007: 'Identifiant ou mot de passe TTLock incorrect',
  10011: 'Jeton TTLock expiré',
  80000: 'L\'heure de ce PC est fausse : réglez-la automatiquement puis relancez',
  [-2018]: 'Ce compte TTLock n\'a pas les droits d\'administrateur sur la serrure',
  [-2012]: 'La serrure n\'est reliée à aucune passerelle TTLock (G2/G3)',
  [-3002]: 'Passerelle TTLock hors ligne',
  [-3003]: 'Passerelle TTLock occupée : réessayez dans un instant',
  [-4043]: 'Fonction non prise en charge par cette serrure',
};

export class TTLockApiError extends Error {
  constructor(code, msg) {
    super(HINTS[code] ? `${HINTS[code]} (TTLock ${code})` : `TTLock ${code} : ${msg ?? 'erreur inconnue'}`);
    this.code = code;
  }
}

/** Mot de passe tel qu'attendu par TTLock : MD5 en minuscules, 32 caractères. */
export const md5 = (s) => createHash('md5').update(s, 'utf8').digest('hex');

/** Types de codes d'accès TTLock (keyboardPwdType). */
export const PASSCODE_TYPES = { one_time: 1, permanent: 2, period: 3 };

export class TTLockClient {
  /**
   * @param {{clientId:string, clientSecret:string, username:string, passwordMd5:string, baseUrl?:string, fetchImpl?:typeof fetch, now?:()=>number}} opts
   */
  constructor({ clientId, clientSecret, username, passwordMd5, baseUrl = TTLOCK_DEFAULT_URL, fetchImpl = (...a) => fetch(...a), now = () => Date.now() }) {
    this.clientId = clientId;
    this.clientSecret = clientSecret;
    this.username = username;
    this.passwordMd5 = passwordMd5;
    this.baseUrl = baseUrl.replace(/\/$/, '');
    this.fetchImpl = fetchImpl;
    this.now = now;
    this.token = null;
    this.refreshToken = null;
    this.tokenExpiresAt = 0;
    this.tokenPromise = null;
  }

  async #raw(method, path, params) {
    const form = new URLSearchParams(Object.entries(params).filter(([, v]) => v !== undefined && v !== null).map(([k, v]) => [k, String(v)]));
    const url = method === 'GET' ? `${this.baseUrl}${path}?${form}` : this.baseUrl + path;
    let res;
    try {
      res = await this.fetchImpl(url, {
        method,
        ...(method === 'GET' ? {} : { headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: form.toString() }),
        signal: AbortSignal.timeout(15_000),
      });
    } catch (e) {
      throw new Error(`Cloud TTLock injoignable (${e.message})`);
    }
    if (!res.ok) throw new Error(`Cloud TTLock : réponse HTTP ${res.status}`);
    return res.json();
  }

  async #ensureToken() {
    if (this.token && this.now() < this.tokenExpiresAt) return;
    this.tokenPromise ??= (async () => {
      try {
        const base = { clientId: this.clientId, clientSecret: this.clientSecret };
        let r = this.refreshToken ? await this.#raw('POST', '/oauth2/token', { ...base, grant_type: 'refresh_token', refresh_token: this.refreshToken }) : null;
        if (!r?.access_token) r = await this.#raw('POST', '/oauth2/token', { ...base, username: this.username, password: this.passwordMd5 });
        if (!r.access_token) throw new TTLockApiError(r.errcode ?? 1, r.errmsg ?? r.description);
        this.token = r.access_token;
        this.refreshToken = r.refresh_token ?? null;
        // Marge d'une heure avant l'expiration annoncée (en secondes, 90 jours en général).
        this.tokenExpiresAt = this.now() + Math.max(60, (r.expires_in ?? 7_776_000) - 3600) * 1000;
      } finally {
        this.tokenPromise = null;
      }
    })();
    await this.tokenPromise;
  }

  /** Requête authentifiée ; renvoie la réponse ou lève TTLockApiError (errcode ≠ 0). */
  async request(method, path, params = {}) {
    await this.#ensureToken();
    const call = () => this.#raw(method, path, { clientId: this.clientId, accessToken: this.token, date: this.now(), ...params });
    let r = await call();
    if (r.errcode && TOKEN_ERRORS.has(r.errcode)) {
      this.token = null;
      await this.#ensureToken();
      r = await call();
    }
    if (r.errcode) throw new TTLockApiError(r.errcode, r.errmsg);
    return r;
  }

  /** Serrures et contrôles d'accès du compte (batterie, passerelle). */
  async listLocks() {
    const all = [];
    for (let pageNo = 1; pageNo <= 20; pageNo++) {
      const r = await this.request('GET', '/v3/lock/list', { pageNo, pageSize: 100 });
      all.push(...(r.list ?? []));
      if (!r.pages || pageNo >= r.pages) break;
    }
    return all;
  }

  /** Derniers passages enregistrés (remontés par une passerelle ou l'app TTLock en Bluetooth). */
  async listRecords(lockId, pageSize = 20) {
    const r = await this.request('GET', '/v3/lockRecord/list', { lockId, pageNo: 1, pageSize, startDate: 0, endDate: 0 });
    return r.list ?? [];
  }

  /**
   * Code au clavier calculé par le cloud TTLock : fonctionne sans passerelle, la serrure
   * le reconnaît hors ligne. startDate / endDate en millisecondes.
   * @returns {Promise<{keyboardPwd:string, keyboardPwdId:number}>}
   */
  createPasscode(lockId, { type, name, startDate, endDate }) {
    return this.request('POST', '/v3/keyboardPwd/get', {
      lockId,
      keyboardPwdType: PASSCODE_TYPES[type],
      keyboardPwdName: name || undefined,
      startDate,
      endDate,
    });
  }

  /** Ouverture à distance : nécessite une passerelle TTLock (ou une serrure Wi-Fi). */
  unlock(lockId) {
    return this.request('POST', '/v3/lock/unlock', { lockId });
  }

  /** État ouvert / fermé (0 fermé, 1 ouvert, 2 inconnu) : nécessite une passerelle. */
  async openState(lockId) {
    const r = await this.request('GET', '/v3/lock/queryOpenState', { lockId });
    return r.state;
  }
}
