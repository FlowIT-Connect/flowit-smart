// Pilote RTSP générique : pour une caméra sans ONVIF, on donne directement l'adresse du flux
// (et, si elle existe, l'adresse de son image fixe). Pas d'identification automatique.

import { fetchWithAuth, splitCredentials } from '../auth.js';
import { UdiError, capabilityFlags, webrtcAudio } from '../contract.js';
import { probeRtsp } from '../rtsp.js';

export class RtspDriver {
  /**
   * @param {{id:string, rtsp_url:string, rtsp_sub_url?:string|null, snapshot_url?:string|null,
   *          manufacturer?:string|null, model?:string|null, username?:string, password?:string}} source
   */
  constructor(source, { fetchImpl = (...a) => fetch(...a), probe = probeRtsp } = {}) {
    this.source = source;
    this.fetchImpl = fetchImpl;
    this.probe = probe;
    this.check = null;
    this.flags = capabilityFlags();
  }

  onEvent() {
    /* pas d'événements en RTSP simple */
  }

  async connect() {
    if (!this.source.rtsp_url) throw new UdiError('Adresse RTSP manquante', 'unsupported');
    this.check = await this.probe(this.source.rtsp_url, { username: this.source.username, password: this.source.password });
    if (!this.check.ok) throw new UdiError(this.check.error, this.check.status === 401 ? 'auth' : 'unreachable');
    this.flags = capabilityFlags({
      video_stream: Boolean(this.check.video),
      snapshot: Boolean(this.source.snapshot_url),
      audio_input: webrtcAudio(this.check.audio?.codec),
    });
  }

  identity() {
    return { manufacturer: this.source.manufacturer ?? null, model: this.source.model ?? null, firmware: null, serial: null };
  }

  capabilities() {
    return { ...this.flags };
  }

  streams() {
    return { main: this.source.rtsp_url, sub: this.source.rtsp_sub_url ?? null };
  }

  async snapshot() {
    if (!this.source.snapshot_url) throw new UdiError('Pas d\'adresse d\'image fixe', 'unsupported');
    const { url, creds } = splitCredentials(this.source.snapshot_url);
    const auth = this.source.username ? { username: this.source.username, password: this.source.password ?? '' } : creds;
    const res = await fetchWithAuth(this.fetchImpl, url, { signal: AbortSignal.timeout(8000) }, auth);
    if (res.status === 401) throw new UdiError('Identifiants refusés pour l\'image', 'auth');
    if (!res.ok) throw new UdiError(`Image indisponible (HTTP ${res.status})`);
    return { bytes: Buffer.from(await res.arrayBuffer()), contentType: res.headers.get('content-type')?.split(';')[0] || 'image/jpeg' };
  }

  async diagnose() {
    const steps = [];
    const add = (step, ok, detail) => steps.push({ step, ok, detail: detail ?? null });
    try {
      await this.connect();
      add('rtsp', true, `Vidéo ${this.check.video?.codec ?? '?'}${this.check.audio ? `, audio ${this.check.audio.codec ?? '?'}${webrtcAudio(this.check.audio.codec) ? '' : ' (non lisible en WebRTC)'}` : ', sans audio'}`);
    } catch (e) {
      add('rtsp', false, e.message);
      return { steps, detected: {} };
    }
    if (this.source.snapshot_url) {
      try {
        const img = await this.snapshot();
        add('image', true, `${Math.round(img.bytes.length / 1024)} Ko`);
      } catch (e) {
        add('image', false, e.message);
      }
    }
    add('identification', false, 'RTSP seul : marque et modèle saisis à la main');
    return { steps, detected: {} };
  }

  async ping() {
    const check = await this.probe(this.source.rtsp_url, { username: this.source.username, password: this.source.password });
    if (!check.ok) throw new UdiError(check.error, check.status === 401 ? 'auth' : 'unreachable');
  }

  async disconnect() {}
}
