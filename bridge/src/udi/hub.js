// Concentrateur UDI : fait tourner un pilote par équipement vidéo, chacun isolé (sa propre
// reprise sur erreur), publie leur état dans Solea, négocie la vidéo WebRTC avec MediaMTX et
// répond aux demandes de recherche d'équipements sur le réseau local.
//
// Une panne d'un appareil (ou d'un fabricant) ne fait que passer CET appareil « hors ligne ».

import { log } from '../log.js';
import { OnvifDriver } from './drivers/onvif_driver.js';
import { RtspDriver } from './drivers/rtsp_driver.js';
import { UdiError } from './contract.js';
import { iceServers, pathName } from './media/mediamtx.js';
import { withCredentials } from './rtsp.js';

export const UDI_PREFIX = 'udi:';
const sourceIdOf = (externalId) => (externalId?.startsWith(UDI_PREFIX) ? externalId.slice(UDI_PREFIX.length) : null);

export function defaultDriverFactory(source, deps = {}) {
  if (source.driver === 'onvif') return new OnvifDriver(source, deps);
  if (source.driver === 'rtsp') return new RtspDriver(source, deps);
  throw new UdiError(`Pilote inconnu : ${source.driver}`, 'unsupported');
}

/** Signature des réglages qui imposent de reconnecter le pilote. */
const settingsKey = (s) =>
  JSON.stringify([s.driver, s.host, s.port, s.rtsp_url, s.rtsp_sub_url, s.snapshot_url, s.username, s.password, s.credentials_updated_at]);

export class UdiHub {
  /**
   * @param {{driverFactory?:Function, mediamtx?:any, discover?:Function, allowedSubnet?:(ip:string)=>boolean,
   *          stun?:string[], turn?:string[], turnSecret?:string|null, retryMinMs?:number, retryMaxMs?:number,
   *          pingMs?:number, sessionMaxAgeMs?:number, clock?:()=>number, version?:string}} [opts]
   */
  constructor({
    driverFactory = defaultDriverFactory,
    mediamtx = null,
    discover = null,
    allowedSubnet = () => true,
    stun = [],
    turn = [],
    turnSecret = null,
    retryMinMs = 10_000,
    retryMaxMs = 5 * 60_000,
    pingMs = 2 * 60_000,
    sessionMaxAgeMs = 2 * 3600_000,
    clock = () => Date.now(),
    version = 'udi-1',
  } = {}) {
    Object.assign(this, { driverFactory, mediamtx, discover, allowedSubnet, stun, turn, turnSecret, retryMinMs, retryMaxMs, pingMs, sessionMaxAgeMs, clock, version });
    /** sourceId -> runner */
    this.runners = new Map();
    /** sessionId -> { location, startedAt } */
    this.sessions = new Map();
    this.busySessions = new Set();
    this.scanBusy = false;
    this.timers = [];
    this.stopped = true;
    this.emitter = null;
  }

  /** Branche le concentrateur sur un logement (appelé par la passerelle avant le démarrage). */
  attach({ homeId, store, resolveDevice, emitter }) {
    Object.assign(this, { homeId, store, resolveDevice, emitter });
  }

  async start() {
    if (!this.store || !this.homeId) throw new Error('UDI : attach() doit précéder start()');
    this.stopped = false;
    await this.refreshSources().catch((e) => log.error('udi.sources_failed', { error: e.message }));
    await this.heartbeat().catch((e) => log.warn('udi.heartbeat_failed', { error: e.message }));
    const every = (ms, fn) => this.timers.push(setInterval(() => fn().catch((e) => log.warn('udi.timer_failed', { error: e.message })), ms));
    every(30_000, () => this.refreshSources());
    every(2_000, () => this.processSessions());
    every(5_000, () => this.processScans());
    every(60_000, () => this.heartbeat());
    every(this.pingMs, () => this.pingAll());
    this.unsubscribe = this.store.subscribeVideo?.(this.homeId, (table) => {
      const run = table === 'video_sessions' ? this.processSessions() : table === 'video_scans' ? this.processScans() : this.refreshSources();
      run.catch((e) => log.warn('udi.realtime_failed', { table, error: e.message }));
    });
  }

  async stop() {
    this.stopped = true;
    for (const t of this.timers) clearInterval(t);
    this.timers = [];
    this.unsubscribe?.();
    for (const [id, s] of this.sessions) {
      await this.mediamtx?.closeSession(s.location);
      this.sessions.delete(id);
    }
    await Promise.allSettled([...this.runners.values()].map((r) => this.#stopRunner(r)));
    this.runners.clear();
  }

  // ---------------------------------------------------------------- Inventaire
  devices() {
    return [...this.runners.values()].map((r) => this.#descriptor(r));
  }

  owns(externalId) {
    return this.runners.has(sourceIdOf(externalId));
  }

  snapshotOf(externalId) {
    const r = this.runners.get(sourceIdOf(externalId));
    if (!r) return { state: {}, availability: 'unknown' };
    const availability = r.status === 'online' ? 'available' : r.status === 'connecting' ? 'unknown' : 'unavailable';
    const state = r.status === 'online' ? { camera: 'idle', ...(r.flags.motion_detection ? { motion: r.motion } : {}) } : {};
    return { state, availability };
  }

  async snapshot(externalId) {
    const r = this.runners.get(sourceIdOf(externalId));
    if (!r?.driver) throw new UdiError('Équipement vidéo inconnu', 'unsupported');
    return r.driver.snapshot();
  }

  #descriptor(r) {
    const s = r.source;
    const flags = r.flags;
    const id = r.identity ?? {};
    return {
      externalId: `${UDI_PREFIX}${s.id}`,
      name: s.name,
      vendor: id.manufacturer ?? s.manufacturer ?? null,
      model: id.model ?? s.model ?? (s.category === 'intercom' ? 'Visiophone IP' : 'Caméra IP'),
      protocol: 'other',
      connectionSource: 'local',
      isSensitive: false,
      capabilities: [
        {
          capability_key: 'camera',
          type: 'string',
          writable: false,
          metadata: { kind: 'camera', live: flags.video_stream && this.mediamtx ? 'webrtc' : null, udi: flags, category: s.category, driver: s.driver },
        },
        ...(flags.motion_detection ? [{ capability_key: 'motion', type: 'sensor', writable: false, metadata: { kind: 'binary' } }] : []),
      ],
    };
  }

  // ---------------------------------------------------------------- Sources
  async refreshSources() {
    if (this.stopped) return;
    const sources = await this.store.listVideoSources(this.homeId);
    const wanted = new Map(sources.filter((s) => s.enabled !== false).map((s) => [s.id, s]));
    let changed = false;
    for (const [id, r] of this.runners) {
      if (!wanted.has(id)) {
        await this.#stopRunner(r);
        await this.mediamtx?.removePath(pathName(id, 'main')).catch(() => {});
        await this.mediamtx?.removePath(pathName(id, 'sub')).catch(() => {});
        this.runners.delete(id);
        changed = true;
      }
    }
    for (const [id, s] of wanted) {
      const r = this.runners.get(id);
      if (!r) {
        this.#startRunner(s);
        changed = true;
      } else if (r.key !== settingsKey(s)) {
        await this.#stopRunner(r);
        this.#startRunner(s);
        changed = true;
      } else {
        const renamed = r.source.name !== s.name;
        r.source = s;
        if (renamed) changed = true;
        if (s.test_requested_at && s.test_requested_at !== r.lastTestRequest) this.#diagnose(r).catch(() => {});
      }
    }
    if (changed) this.emitter?.emit('inventory');
  }

  #startRunner(source) {
    const r = {
      source,
      key: settingsKey(source),
      driver: null,
      status: 'connecting',
      flags: {},
      identity: null,
      motion: false,
      attempt: 0,
      retry: null,
      lastTestRequest: source.test_requested_at ?? null,
      stopped: false,
    };
    try {
      r.driver = this.driverFactory(source);
      r.driver.onEvent((ev) => this.#onDriverEvent(r, ev));
    } catch (e) {
      r.status = 'error';
      r.lastError = e.message;
    }
    this.runners.set(source.id, r);
    if (r.driver) {
      // Premier ajout (jamais diagnostiqué) ou nouvel essai demandé : diagnostic complet, sinon connexion.
      const first = !source.diagnosed_at || (source.test_requested_at && source.test_requested_at > source.diagnosed_at);
      (first ? this.#diagnose(r) : this.#connect(r)).catch(() => {});
    } else {
      this.#report(r).catch(() => {});
    }
  }

  async #stopRunner(r) {
    r.stopped = true;
    clearTimeout(r.retry);
    await r.driver?.disconnect().catch(() => {});
  }

  #onDriverEvent(r, ev) {
    if (r.stopped) return;
    if (ev.type === 'motion' && ev.value !== r.motion) {
      r.motion = ev.value;
      this.emitter?.emit('device', `${UDI_PREFIX}${r.source.id}`, this.snapshotOf(`${UDI_PREFIX}${r.source.id}`));
    }
  }

  async #connect(r) {
    if (r.stopped || this.stopped) return;
    try {
      await r.driver.connect();
      await this.#online(r);
    } catch (e) {
      await this.#failed(r, e);
    }
  }

  async #online(r) {
    const before = JSON.stringify([r.flags, r.identity]);
    r.status = 'online';
    r.attempt = 0;
    r.lastError = null;
    r.identity = r.driver.identity();
    r.flags = r.driver.capabilities();
    await this.#preparePaths(r).catch((e) => log.warn('udi.mediamtx_failed', { source: r.source.id, error: e.message }));
    await this.#report(r);
    log.info('udi.online', { source: r.source.id, driver: r.source.driver, model: r.identity.model });
    if (before !== JSON.stringify([r.flags, r.identity])) this.emitter?.emit('inventory');
    else this.emitter?.emit('device', `${UDI_PREFIX}${r.source.id}`, this.snapshotOf(`${UDI_PREFIX}${r.source.id}`));
  }

  async #failed(r, e) {
    if (r.stopped) return;
    const wasOnline = r.status === 'online';
    r.status = e?.kind === 'auth' ? 'auth_error' : 'offline';
    r.lastError = e?.message ?? String(e);
    r.attempt++;
    log.warn('udi.offline', { source: r.source.id, error: r.lastError, attempt: r.attempt });
    await this.#report(r).catch(() => {});
    if (wasOnline || r.attempt === 1) this.emitter?.emit('device', `${UDI_PREFIX}${r.source.id}`, this.snapshotOf(`${UDI_PREFIX}${r.source.id}`));
    // Mauvais mot de passe : on réessaie lentement pour ne pas bloquer le compte de l'appareil.
    const base = r.status === 'auth_error' ? this.retryMaxMs : Math.min(this.retryMinMs * 2 ** (r.attempt - 1), this.retryMaxMs);
    clearTimeout(r.retry);
    r.retry = setTimeout(() => this.#connect(r), base);
  }

  async #diagnose(r) {
    r.lastTestRequest = r.source.test_requested_at ?? r.lastTestRequest;
    let result;
    try {
      result = await r.driver.diagnose();
    } catch (e) {
      result = { steps: [{ step: 'connexion', ok: false, detail: e.message }], detected: {} };
    }
    const connected = result.steps.find((s) => s.step === 'connexion' || s.step === 'rtsp')?.ok === true;
    await this.store
      .updateVideoSource(r.source.id, { diagnostic: { steps: result.steps, detected: result.detected }, diagnosed_at: new Date(this.clock()).toISOString() })
      .catch((e) => log.warn('udi.report_failed', { source: r.source.id, error: e.message }));
    if (connected) await this.#online(r);
    else {
      const failed = result.steps.find((s) => !s.ok);
      await this.#failed(r, new UdiError(failed?.detail ?? 'Diagnostic en échec', /refusés/.test(failed?.detail ?? '') ? 'auth' : 'unreachable'));
    }
  }

  async #report(r) {
    const id = r.identity ?? {};
    await this.store.updateVideoSource(r.source.id, {
      status: r.status,
      last_error: r.lastError ?? null,
      capabilities: r.flags,
      ...(id.manufacturer ? { manufacturer: id.manufacturer } : {}),
      ...(id.model ? { model: id.model } : {}),
      ...(id.firmware ? { firmware: id.firmware } : {}),
      ...(r.status === 'online' ? { last_seen_at: new Date(this.clock()).toISOString() } : {}),
    });
  }

  async #preparePaths(r) {
    if (!this.mediamtx || !r.flags.video_stream) return;
    const { main, sub } = r.driver.streams();
    const creds = [r.source.username, r.source.password];
    if (main) await this.mediamtx.ensurePath(pathName(r.source.id, 'main'), withCredentials(main, ...creds));
    if (sub) await this.mediamtx.ensurePath(pathName(r.source.id, 'sub'), withCredentials(sub, ...creds));
  }

  /** Vérification périodique : un appareil qui ne répond plus passe hors ligne. */
  async pingAll() {
    await Promise.allSettled(
      [...this.runners.values()]
        .filter((r) => r.status === 'online' && r.driver)
        .map(async (r) => {
          try {
            await (r.driver.ping ? r.driver.ping() : r.driver.connect());
            await this.store.updateVideoSource(r.source.id, { last_seen_at: new Date(this.clock()).toISOString() }).catch(() => {});
          } catch (e) {
            await this.#failed(r, e);
          }
        }),
    );
  }

  // ---------------------------------------------------------------- Vidéo WebRTC
  async processSessions() {
    if (this.stopped) return;
    const rows = await this.store.listVideoSessions(this.homeId, [...this.sessions.keys()]);
    for (const row of rows) {
      if (row.status === 'offer' && !this.busySessions.has(row.id) && !this.sessions.has(row.id)) {
        this.busySessions.add(row.id);
        this.#answer(row)
          .catch((e) => log.warn('udi.session_failed', { session: row.id, error: e.message }))
          .finally(() => this.busySessions.delete(row.id));
      } else if (this.sessions.has(row.id)) {
        const s = this.sessions.get(row.id);
        if (row.status === 'closed' || row.status === 'failed' || this.clock() - s.startedAt > this.sessionMaxAgeMs) {
          await this.mediamtx?.closeSession(s.location);
          this.sessions.delete(row.id);
          if (row.status !== 'closed') await this.store.updateVideoSession(row.id, { status: 'closed' }).catch(() => {});
        }
      }
    }
  }

  async #answer(row) {
    const fail = (error) => this.store.updateVideoSession(row.id, { status: 'failed', error });
    if (this.clock() - Date.parse(row.created_at) > 60_000) return fail('Demande expirée');
    if (!this.mediamtx) return fail('Relais vidéo non installé sur le boîtier');
    const externalId = this.resolveDevice?.(row.device_id);
    const r = this.runners.get(sourceIdOf(externalId));
    if (!r) return fail('Équipement vidéo inconnu de ce boîtier');
    if (r.status !== 'online') return fail('Équipement hors ligne');
    if (!r.flags.video_stream) return fail('Cet équipement ne fournit pas de flux vidéo');
    const quality = row.quality === 'sub' && r.driver.streams().sub ? 'sub' : 'main';
    try {
      await this.#preparePaths(r);
      const { answer, location } = await this.mediamtx.whep(pathName(r.source.id, quality), row.offer);
      this.sessions.set(row.id, { location, startedAt: this.clock() });
      await this.store.updateVideoSession(row.id, { status: 'answered', answer, quality, answered_at: new Date(this.clock()).toISOString() });
      log.info('udi.session_answered', { session: row.id, source: r.source.id, quality });
    } catch (e) {
      await fail(e.message);
    }
  }

  // ---------------------------------------------------------------- Recherche réseau
  async processScans() {
    if (this.stopped || this.scanBusy || !this.discover) return;
    const scans = await this.store.listPendingVideoScans(this.homeId);
    const scan = scans[0];
    if (!scan) return;
    this.scanBusy = true;
    try {
      await this.store.updateVideoScan(scan.id, { status: 'running' });
      const found = await this.discover({ allowed: this.allowedSubnet });
      const known = new Set([...this.runners.values()].map((r) => r.source.host).filter(Boolean));
      const results = found.map((d) => ({
        host: d.host,
        port: d.port,
        name: d.name,
        hardware: d.hardware,
        protocol: 'onvif',
        already_added: known.has(d.host),
      }));
      await this.store.updateVideoScan(scan.id, { status: 'done', results, finished_at: new Date(this.clock()).toISOString() });
      log.info('udi.scan_done', { found: results.length });
    } catch (e) {
      await this.store.updateVideoScan(scan.id, { status: 'failed', error: e.message, finished_at: new Date(this.clock()).toISOString() }).catch(() => {});
    } finally {
      this.scanBusy = false;
    }
  }

  // ---------------------------------------------------------------- Boîtier
  async heartbeat() {
    if (this.stopped) return;
    const mediamtxOk = this.mediamtx ? await this.mediamtx.health() : false;
    const servers = iceServers({ stun: this.stun, turn: this.turn, turnSecret: this.turnSecret, now: this.clock() });
    // Les identifiants TURN expirent : MediaMTX reçoit des identifiants neufs chaque heure.
    if (mediamtxOk && (!this.iceAppliedAt || this.clock() - this.iceAppliedAt > 3600_000)) {
      await this.mediamtx
        .setIceServers(servers)
        .then(() => (this.iceAppliedAt = this.clock()))
        .catch((e) => log.warn('udi.ice_failed', { error: e.message }));
    }
    await this.store.upsertMediaGateway(this.homeId, {
      ice_servers: servers,
      relay_ok: mediamtxOk,
      discovery: Boolean(this.discover),
      version: this.version,
      last_seen_at: new Date(this.clock()).toISOString(),
    });
  }
}
