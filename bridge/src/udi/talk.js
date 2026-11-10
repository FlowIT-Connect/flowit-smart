// « Parler à travers la caméra » : la voix du téléphone arrive en WebRTC sur le relais local
// (MediaMTX, chemin propre à la session), le boîtier la lit en RTSP sur 127.0.0.1 et la renvoie
// à la caméra par sa voie de retour audio ONVIF, en G.711. Rien ne sort de la maison.

import { BACKCHANNEL, RtspSession, alawToUlaw, controlUrl, rewriteRtp, ulawToAlaw } from './rtsp_session.js';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export class TalkRelay {
  /**
   * @param {{cameraUrl:string, username?:string, password?:string, sourceUrl:string, connect?:Function, readyTimeoutMs?:number}} opts
   */
  constructor({ cameraUrl, username = '', password = '', sourceUrl, connect, readyTimeoutMs = 20_000 }) {
    this.cameraUrl = cameraUrl;
    this.creds = { username, password };
    this.sourceUrl = sourceUrl;
    this.connect = connect;
    this.readyTimeoutMs = readyTimeoutMs;
    this.camera = null;
    this.source = null;
    this.stopped = false;
    this.packets = 0;
    this.onEnd = null;
  }

  /** Voie de retour annoncée par la caméra (piste audio « sendonly » en G.711). */
  static backchannelOf(medias) {
    return medias.find((m) => m.kind === 'audio' && m.direction === 'sendonly' && ['PCMA', 'PCMU'].includes(m.codec)) ?? null;
  }

  async #openSource() {
    const deadline = Date.now() + this.readyTimeoutMs;
    // Le téléphone publie sa voix quelques secondes après la réponse (ICE, DTLS) : on attend.
    for (;;) {
      if (this.stopped) throw new Error('arrêté');
      const s = new RtspSession(this.sourceUrl, { connect: this.connect });
      try {
        await s.open();
        const d = await s.describe();
        return { s, d };
      } catch (e) {
        await s.close().catch(() => {});
        if (e.status !== 404 && e.status !== 400) throw e;
        if (Date.now() > deadline) throw new Error('La voix du téléphone n\'est pas arrivée au boîtier');
        await sleep(400);
      }
    }
  }

  async start() {
    const { s: source, d: src } = await this.#openSource();
    this.source = source;
    const audio = src.medias.find((m) => m.kind === 'audio');
    if (!audio || !['PCMA', 'PCMU'].includes(audio.codec)) throw new Error(`Voix du téléphone dans un format inattendu (${audio?.codec ?? 'aucun son'})`);

    const camera = new RtspSession(this.cameraUrl, { ...this.creds, require: BACKCHANNEL, connect: this.connect });
    this.camera = camera;
    await camera.open();
    const cam = await camera.describe();
    const back = TalkRelay.backchannelOf(cam.medias);
    if (!back) throw new Error('Cette caméra n\'accepte pas la voix (pas de voie de retour audio)');
    await camera.setup(controlUrl(cam.base, back.control), 0);
    await camera.play(cam.sessionControl ? controlUrl(cam.base, cam.sessionControl) : cam.base);

    const convert = audio.codec === back.codec ? null : audio.codec === 'PCMU' ? ulawToAlaw : alawToUlaw;
    const ssrc = (Math.random() * 0xffffffff) >>> 0;
    source.onRtp = (ch, pkt) => {
      if (ch !== 0) return; // canal 1 : RTCP
      const out = rewriteRtp(pkt, { pt: back.pt, ssrc, convert });
      if (out && camera.sendRtp(0, out)) this.packets++;
    };
    const end = () => {
      if (this.stopped) return;
      this.stop().finally(() => this.onEnd?.());
    };
    source.onClose = end;
    camera.onClose = end;
    await source.setup(controlUrl(src.base, audio.control), 0);
    await source.play(src.sessionControl ? controlUrl(src.base, src.sessionControl) : src.base);
    return { codec: back.codec, from: audio.codec };
  }

  async stop() {
    if (this.stopped) return;
    this.stopped = true;
    await Promise.all([this.source?.close().catch(() => {}), this.camera?.close().catch(() => {})]);
  }
}
