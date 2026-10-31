// Pilote ONVIF générique (Profile S / T) : la plupart des caméras IP et de nombreux
// visiophones (Hikvision, Dahua, Uniview, Akuvox, Axis…) parlent ONVIF.

import { fetchWithAuth } from '../auth.js';
import { UdiError, capabilityFlags, webrtcAudio } from '../contract.js';
import { OnvifClient, motionFromNotification } from '../onvif/client.js';
import { probeRtsp } from '../rtsp.js';
import { log } from '../../log.js';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export class OnvifDriver {
  /**
   * @param {{id:string, name:string, host:string, port?:number, username?:string, password?:string}} source
   * @param {{fetchImpl?:typeof fetch, probe?:typeof probeRtsp, events?:boolean, pullTimeoutSeconds?:number}} [deps]
   */
  constructor(source, { fetchImpl = (...a) => fetch(...a), probe = probeRtsp, events = true, pullTimeoutSeconds = 10 } = {}) {
    this.source = source;
    this.fetchImpl = fetchImpl;
    this.probe = probe;
    this.eventsEnabled = events;
    this.pullTimeoutSeconds = pullTimeoutSeconds;
    this.client = new OnvifClient({
      host: source.host,
      port: source.port || 80,
      username: source.username ?? '',
      password: source.password ?? '',
      fetchImpl,
    });
    this.info = null;
    this.flags = capabilityFlags();
    this.detected = {};
    this.urls = { main: null, sub: null, snapshot: null };
    this.rtspCheck = null;
    this.listeners = [];
    this.stopped = false;
    this.eventLoop = null;
    this.eventsOk = null;
  }

  onEvent(cb) {
    this.listeners.push(cb);
  }

  #emit(ev) {
    for (const cb of this.listeners) {
      try {
        cb(ev);
      } catch {
        /* un écouteur fautif ne casse pas le pilote */
      }
    }
  }

  #wrap(e) {
    if (e instanceof UdiError) return e;
    if (e?.isAuth) return new UdiError('Identifiants refusés par l\'appareil', 'auth');
    if (/injoignable/i.test(e?.message ?? '')) return new UdiError(e.message, 'unreachable');
    return new UdiError(e?.message ?? String(e), 'protocol');
  }

  async connect() {
    this.stopped = false;
    try {
      await this.client.syncClock().catch(() => null); // facultatif : certains appareils l'exigent authentifié
      this.info = await this.client.getDeviceInformation();
      const caps = await this.client.getCapabilities();
      const profiles = await this.client.getProfiles();
      if (!profiles.length) throw new UdiError('Aucun profil vidéo ONVIF', 'unsupported');
      const byPixels = [...profiles].sort((a, b) => (b.width ?? 0) * (b.height ?? 0) - (a.width ?? 0) * (a.height ?? 0));
      const main = byPixels[0];
      const sub = byPixels.length > 1 ? byPixels[byPixels.length - 1] : null;
      this.urls.main = await this.client.getStreamUri(main.token);
      this.urls.sub = sub ? await this.client.getStreamUri(sub.token).catch(() => null) : null;
      this.urls.snapshot = await this.client.getSnapshotUri(main.token).catch(() => null);
      this.profiles = profiles.map(({ token, name, encoding, width, height }) => ({ token, name, encoding, width, height }));

      // Vérification réelle du flux : ce qui est annoncé ne suffit pas.
      this.rtspCheck = this.urls.main
        ? await this.probe(this.urls.main, { username: this.source.username, password: this.source.password })
        : { ok: false, error: 'Pas d\'adresse RTSP' };

      this.detected = {
        relay_outputs: caps.relayOutputs,
        audio_outputs: caps.audioOutputs,
        audio_sources: caps.audioSources,
        ptz: Boolean(caps.services.ptz) || profiles.some((p) => p.ptz),
        pull_point: caps.pullPoint,
        events_service: Boolean(caps.services.events),
      };
      this.flags = capabilityFlags({
        video_stream: this.rtspCheck.ok && Boolean(this.rtspCheck.video),
        snapshot: Boolean(this.urls.snapshot),
        audio_input: this.rtspCheck.ok && webrtcAudio(this.rtspCheck.audio?.codec),
        // Parler, relais de porte, PTZ : détectés mais pas encore pilotés par Solea (phases B et C).
      });
      if (this.eventsEnabled && caps.services.events) this.#startEvents();
    } catch (e) {
      throw this.#wrap(e);
    }
  }

  identity() {
    return {
      manufacturer: this.info?.manufacturer ?? null,
      model: this.info?.model ?? null,
      firmware: this.info?.firmware ?? null,
      serial: this.info?.serial ?? null,
    };
  }

  capabilities() {
    return { ...this.flags, motion_detection: this.eventsOk === true };
  }

  streams() {
    return { main: this.urls.main, sub: this.urls.sub };
  }

  async snapshot() {
    if (!this.urls.snapshot) throw new UdiError('Cet appareil ne fournit pas d\'image fixe', 'unsupported');
    const creds = this.source.username ? { username: this.source.username, password: this.source.password ?? '' } : null;
    const res = await fetchWithAuth(this.fetchImpl, this.urls.snapshot, { signal: AbortSignal.timeout(8000) }, creds);
    if (res.status === 401) throw new UdiError('Identifiants refusés pour l\'image', 'auth');
    if (!res.ok) throw new UdiError(`Image indisponible (HTTP ${res.status})`, 'protocol');
    return { bytes: Buffer.from(await res.arrayBuffer()), contentType: res.headers.get('content-type')?.split(';')[0] || 'image/jpeg' };
  }

  #startEvents() {
    if (this.eventLoop) return;
    this.eventLoop = this.#eventsLoop().finally(() => (this.eventLoop = null));
  }

  async #eventsLoop() {
    let address = null;
    let renewAt = 0;
    let backoff = 5000;
    let failures = 0;
    while (!this.stopped) {
      try {
        if (!address) {
          address = await this.client.createPullPoint(120);
          renewAt = Date.now() + 60_000;
          this.eventsOk = true;
          backoff = 5000;
          failures = 0;
        }
        const messages = await this.client.pullMessages(address, { timeoutSeconds: this.pullTimeoutSeconds });
        for (const n of messages) {
          const motion = motionFromNotification(n);
          if (motion !== null) this.#emit({ type: 'motion', value: motion, at: n.time });
        }
        if (Date.now() > renewAt) {
          await this.client.renew(address, 120);
          renewAt = Date.now() + 60_000;
        }
      } catch (e) {
        if (this.stopped) break;
        failures++;
        address = null;
        if (failures >= 3) this.eventsOk = false;
        log.warn('udi.onvif_events_failed', { source: this.source.id, error: e.message });
        await sleep(backoff);
        backoff = Math.min(backoff * 2, 120_000);
      }
    }
    if (address) await this.client.unsubscribe(address);
  }

  async diagnose() {
    const steps = [];
    const add = (step, ok, detail) => steps.push({ step, ok, detail: detail ?? null });
    try {
      await this.connect();
    } catch (e) {
      add('connexion', false, e.message);
      return { steps, detected: this.detected };
    }
    const id = this.identity();
    add('connexion', true, `ONVIF sur ${this.source.host}:${this.source.port || 80}`);
    add('identification', Boolean(id.manufacturer || id.model), [id.manufacturer, id.model, id.firmware && `firmware ${id.firmware}`].filter(Boolean).join(' · ') || null);
    add('onvif', true, `${this.profiles.length} profil(s) : ${this.profiles.map((p) => `${p.name} ${p.encoding ?? ''} ${p.width ?? '?'}×${p.height ?? '?'}`.trim()).join(', ')}`);
    add(
      'rtsp',
      Boolean(this.rtspCheck?.ok),
      this.rtspCheck?.ok
        ? `Vidéo ${this.rtspCheck.video?.codec ?? '?'}${this.rtspCheck.audio ? `, audio ${this.rtspCheck.audio.codec ?? '?'}${webrtcAudio(this.rtspCheck.audio.codec) ? '' : ' (non lisible en WebRTC)'}` : ', sans audio'}`
        : this.rtspCheck?.error,
    );
    if (this.flags.snapshot) {
      try {
        const img = await this.snapshot();
        add('image', true, `${Math.round(img.bytes.length / 1024)} Ko`);
      } catch (e) {
        add('image', false, e.message);
      }
    } else add('image', false, 'Non fournie par l\'appareil');
    add('événements', this.detected.events_service === true, this.detected.events_service ? (this.detected.pull_point ? 'Mouvement via ONVIF' : 'Service présent, sans « pull point »') : 'Non pris en charge');
    if (this.detected.relay_outputs > 0) add('relais', true, `${this.detected.relay_outputs} sortie(s) détectée(s), pilotage prévu en phase B`);
    return { steps, detected: this.detected };
  }

  /** Vérification légère : l'appareil répond-il encore ? */
  async ping() {
    try {
      await this.client.getDeviceInformation();
    } catch (e) {
      throw this.#wrap(e);
    }
  }

  async disconnect() {
    this.stopped = true;
    await this.eventLoop?.catch(() => {});
  }
}
