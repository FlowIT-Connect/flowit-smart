// Cloud TTLock simulé pour les tests : mêmes routes et mêmes formats que l'API v3 réelle.

export const CLIENT_ID = 'test-client-id';
export const CLIENT_SECRET = 'test-client-secret';
export const USERNAME = 'baziz@example.dz';
export const PASSWORD_MD5 = 'a11c3ad6ab5f2bc3ba26fce1f4d33a9a';

export function demoLocks() {
  return [
    { lockId: 1001, lockName: 'M201_7e3f', lockAlias: 'Boîtier entrée', electricQuantity: 82, hasGateway: 0 },
    { lockId: 1002, lockName: 'S31_a1b2', lockAlias: 'Porte garage', electricQuantity: 55, hasGateway: 1 },
  ];
}

export class FakeTTLockCloud {
  constructor({ locks = demoLocks() } = {}) {
    this.locks = locks;
    this.calls = [];
    this.tokens = new Set();
    this.issued = 0;
    this.openState = new Map([[1002, 0]]);
    this.records = new Map([
      [1001, [
        { recordType: 4, success: 1, keyboardPwd: '48213977', lockDate: Date.parse('2026-10-30T08:12:00Z') },
        { recordType: 1, success: 1, username: 'baziz', lockDate: Date.parse('2026-10-30T07:40:00Z') },
      ]],
    ]);
    this.keys = [
      { keyId: 501, lockId: 1001, username: USERNAME, keyName: 'Admin', keyStatus: '110401', startDate: 0, endDate: 0 },
      { keyId: 502, lockId: 1001, username: '+213555000111', keyName: 'Karim', keyStatus: '110401', startDate: 0, endDate: 0 },
    ];
    this.nextKeyId = 600;
    this.failNext = null; // errcode à renvoyer une fois
  }

  fetch = async (url, init = {}) => {
    const u = new URL(url);
    const params = Object.fromEntries(init.method === 'GET' || !init.body ? u.searchParams : new URLSearchParams(init.body));
    this.calls.push({ path: u.pathname, params });
    return new Response(JSON.stringify(this.#route(u.pathname, params)), { headers: { 'content-type': 'application/json' } });
  };

  #route(path, p) {
    if (path === '/oauth2/token') {
      if (p.clientId !== CLIENT_ID || p.clientSecret !== CLIENT_SECRET) return { errcode: 10000, errmsg: 'invalid client_id' };
      if (p.grant_type !== 'refresh_token' && (p.username !== USERNAME || p.password !== PASSWORD_MD5)) {
        return { errcode: 10007, errmsg: 'invalid account or invalid password' };
      }
      const token = `tok-${++this.issued}`;
      this.tokens.add(token);
      return { access_token: token, refresh_token: `ref-${this.issued}`, uid: 7, expires_in: 7_776_000 };
    }
    if (p.clientId !== CLIENT_ID || !this.tokens.has(p.accessToken)) return { errcode: 10004, errmsg: 'invalid grant' };
    if (this.failNext) {
      const errcode = this.failNext;
      this.failNext = null;
      return { errcode, errmsg: 'simulated' };
    }
    const lock = this.locks.find((l) => String(l.lockId) === p.lockId);
    switch (path) {
      case '/v3/lock/list':
        return { list: this.locks, pageNo: 1, pageSize: 100, pages: 1, total: this.locks.length };
      case '/v3/lockRecord/list':
        return { list: this.records.get(Number(p.lockId)) ?? [], pages: 1 };
      case '/v3/keyboardPwd/get':
        if (!lock) return { errcode: -1003, errmsg: 'lock not found' };
        return { keyboardPwd: String(10_000_000 + this.calls.length), keyboardPwdId: this.calls.length };
      case '/v3/lock/listKey':
        return { list: this.keys.filter((k) => String(k.lockId) === p.lockId && k.keyStatus !== '110408'), pages: 1 };
      case '/v3/key/send': {
        if (!lock) return { errcode: -1003, errmsg: 'lock not found' };
        if (p.receiverUsername === 'inconnu@x.dz') return { errcode: 20002, errmsg: 'user not exist' };
        const keyId = this.nextKeyId++;
        this.keys.push({ keyId, lockId: lock.lockId, username: p.receiverUsername, keyName: p.keyName, keyStatus: '110401', startDate: Number(p.startDate), endDate: Number(p.endDate) });
        return { keyId };
      }
      case '/v3/key/freeze':
      case '/v3/key/unfreeze':
      case '/v3/key/delete':
      case '/v3/key/changePeriod': {
        const key = this.keys.find((k) => String(k.keyId) === p.keyId);
        if (!key) return { errcode: -1008, errmsg: 'eKey does not exist' };
        if (path.endsWith('freeze')) key.keyStatus = path === '/v3/key/freeze' ? '110405' : '110401';
        if (path === '/v3/key/delete') key.keyStatus = '110408';
        if (path === '/v3/key/changePeriod') Object.assign(key, { startDate: Number(p.startDate), endDate: Number(p.endDate) });
        return { errcode: 0 };
      }
      case '/v3/lock/unlock':
        if (!lock?.hasGateway) return { errcode: -2012, errmsg: 'lock is not connected to any gateway' };
        this.openState.set(lock.lockId, 1);
        return { errcode: 0, errmsg: 'none error message' };
      case '/v3/lock/queryOpenState':
        if (!lock?.hasGateway) return { errcode: -2012, errmsg: 'lock is not connected to any gateway' };
        return { state: this.openState.get(lock.lockId) ?? 2 };
      default:
        return { errcode: 1, errmsg: `route inconnue ${path}` };
    }
  }
}
