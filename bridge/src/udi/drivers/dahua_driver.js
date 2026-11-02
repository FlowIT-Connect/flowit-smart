// Pilote Dahua (caméras grand public Hero / Imou et caméras IP Dahua), ajoutées par le QR code
// de l'étiquette : numéro de série + code de sécurité, sans adresse IP à saisir.
//
// 1. L'adresse IP est retrouvée sur le réseau local par le numéro de série (découverte DHIP),
//    puis retrouvée à nouveau si la box lui en donne une autre.
// 2. La vidéo passe par l'adresse RTSP standard de Dahua (/cam/realmonitor), flux principal
//    (subtype=0) et secondaire (subtype=1). Identifiant « admin », mot de passe = code de sécurité.
// 3. L'image fixe (snapshot.cgi) n'est annoncée que si la caméra la fournit réellement.

import { fetchWithAuth } from '../auth.js';
import { UdiError, capabilityFlags, webrtcAudio } from '../contract.js';
import { probeRtsp } from '../rtsp.js';
import { OnvifDriver } from './onvif_driver.js';

export const dahuaRtsp = (host, subtype, port = 554) => `rtsp://${host}:${port}/cam/realmonitor?channel=1&subtype=${subtype}`;

export class DahuaDriver {
  /**
   * @param {{id:string, host?:string|null, serial?:string|null, model?:string|null, username?:string, password?:string}} source
   * @param {{locate?:(serial:string)=>Promise<{host:string, model?:string|null, mac?:string|null}|null>, probe?:Function, fetchImpl?:Function, onvif?:Function}} [deps]
   */
  constructor(source, { locate = async () => null, probe = probeRtsp, fetchImpl = (...a) => fetch(...a), onvif = (src) => new OnvifDriver(src, { fetchImpl, probe, events: false }) } = {}) {
    this.onvif = onvif;
    this.alt = null; // flux annoncés par ONVIF quand l'adresse Dahua standard ne répond pas
    this.source = source;
    this.locate = locate;
    this.probe = probe;
    this.fetchImpl = fetchImpl;
    this.host = source.host ?? null;
    this.found = null;
    this.check = null;
    this.snapshotOk = false;
    this.flags = capabilityFlags();
  }

  onEvent() {
    /* événements Dahua : plus tard (phase B) */
  }

  get creds() {
    return { username: this.source.username || 'admin', password: this.source.password ?? '' };
  }

  async #find() {
    if (!this.source.serial) return null;
    const d = await this.locate(this.source.serial);
    if (d?.host) {
      this.found = d;
      this.host = d.host;
    }
    return d;
  }

  async #probe() {
    return this.probe(dahuaRtsp(this.host, 0), this.creds);
  }

  async connect() {
    if (!this.host) {
      if (!this.source.serial) throw new UdiError('Ni adresse ni numéro de série', 'unsupported');
      if (!(await this.#find())) {
        throw new UdiError('Caméra introuvable sur le réseau : vérifiez qu\'elle est allumée et sur le même Wi-Fi que le boîtier', 'unreachable');
      }
    }
    let check = await this.#probe();
    // L'adresse a peut-être changé (box redémarrée) : on la cherche à nouveau par le numéro de série.
    if (!check.ok && check.status !== 401 && this.source.serial) {
      const before = this.host;
      if ((await this.#find()) && this.host !== before) check = await this.#probe();
    }
    // Adresse RTSP standard refusée : on demande à la caméra elle-même (ONVIF) où est son flux.
    if (!check.ok && check.status !== 401) {
      const alt = await this.#viaOnvif();
      if (alt.check?.ok) check = alt.check;
      else check = { ...check, error: `${check.error}. Essai ONVIF : ${alt.error}` };
    }
    this.check = check;
    if (!check.ok) {
      throw new UdiError(check.status === 401 ? 'Code de sécurité refusé par la caméra' : check.error, check.status === 401 ? 'auth' : 'unreachable');
    }
    this.snapshotOk = await this.#trySnapshot().then(() => true, () => false);
    this.flags = capabilityFlags({
      video_stream: Boolean(check.video),
      snapshot: this.snapshotOk,
      audio_input: webrtcAudio(check.audio?.codec),
    });
  }

  async #viaOnvif() {
    try {
      const d = this.onvif({ id: this.source.id, name: this.source.name ?? 'Dahua', host: this.host, port: 80, ...this.creds });
      await d.connect();
      const check = d.rtspCheck ?? { ok: false, error: 'aucun flux annoncé' };
      if (check.ok) this.alt = d.streams();
      return { check, error: check.ok ? null : check.error };
    } catch (e) {
      return { check: null, error: e?.message ?? String(e) };
    }
  }

  identity() {
    return { manufacturer: 'Dahua', model: this.found?.model ?? this.source.model ?? null, firmware: null, serial: this.source.serial ?? null };
  }

  /** Adresse trouvée sur le réseau, à enregistrer dans Solea pour l'afficher. */
  located() {
    return this.host ? { host: this.host, mac: this.found?.mac ?? null } : null;
  }

  capabilities() {
    return { ...this.flags };
  }

  streams() {
    if (this.alt?.main) return this.alt;
    return this.host ? { main: dahuaRtsp(this.host, 0), sub: dahuaRtsp(this.host, 1) } : { main: null, sub: null };
  }

  async #trySnapshot() {
    const res = await this.fetchImpl(`http://${this.host}/cgi-bin/snapshot.cgi?channel=1`, { signal: AbortSignal.timeout(6000) });
    const final = res.status === 401 ? await fetchWithAuth(this.fetchImpl, `http://${this.host}/cgi-bin/snapshot.cgi?channel=1`, { signal: AbortSignal.timeout(6000) }, this.creds) : res;
    if (final.status === 401) throw new UdiError('Code de sécurité refusé pour l\'image', 'auth');
    const type = final.headers.get('content-type') ?? '';
    if (!final.ok || !type.startsWith('image/')) throw new UdiError(`Image indisponible (HTTP ${final.status})`);
    return { bytes: Buffer.from(await final.arrayBuffer()), contentType: type.split(';')[0] };
  }

  async snapshot() {
    if (!this.host) throw new UdiError('Caméra pas encore trouvée sur le réseau', 'unreachable');
    return this.#trySnapshot();
  }

  async diagnose() {
    const steps = [];
    const add = (step, ok, detail) => steps.push({ step, ok, detail: detail ?? null });
    if (!this.source.host && this.source.serial) {
      const d = await this.#find().catch(() => null);
      if (!d) {
        add('réseau', false, 'Caméra introuvable sur le réseau : vérifiez qu\'elle est allumée et sur le même Wi-Fi que le boîtier');
        return { steps, detected: {} };
      }
      add('réseau', true, `Trouvée à l'adresse ${d.host}`);
    }
    try {
      await this.connect();
    } catch (e) {
      add('rtsp', false, e.message);
      return { steps, detected: {} };
    }
    const c = this.check;
    add('rtsp', true, `Vidéo ${c.video?.codec ?? '?'}${c.audio ? `, audio ${c.audio.codec ?? '?'}${webrtcAudio(c.audio.codec) ? '' : ' (non lisible en WebRTC)'}` : ', sans audio'}`);
    add('image', this.snapshotOk, this.snapshotOk ? 'Image fixe disponible' : 'Pas d\'image fixe : la vidéo reste disponible');
    add('identification', true, ['Dahua', this.identity().model, this.source.serial ? `n° ${this.source.serial}` : null].filter(Boolean).join(' · '));
    return { steps, detected: {} };
  }

  async ping() {
    const check = this.alt?.main ? await this.probe(this.alt.main, this.creds) : await this.#probe();
    if (!check.ok) throw new UdiError(check.error, check.status === 401 ? 'auth' : 'unreachable');
  }

  async disconnect() {}
}
