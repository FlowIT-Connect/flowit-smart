// Images en direct des caméras.
//
// L'application signale qu'un membre regarde une caméra (message « watch » sur le canal
// temps réel de la maison, répété toutes les quelques secondes). Tant que ce signal arrive,
// la passerelle lit l'image de la caméra environ chaque seconde, la dépose dans le bucket
// privé camera-frames et prévient l'application (« frame »). Personne ne regarde : aucune
// image ne quitte la maison.

import { log } from './log.js';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export class CameraStreamer {
  /**
   * @param {{store:any, adapter:any, homeId:string, resolve:(deviceId:string)=>({externalId:string,key:string}|null),
   *          intervalMs?:number, watchTtlMs?:number, retryMs?:number}} deps
   */
  constructor({ store, adapter, homeId, resolve, intervalMs = 1000, watchTtlMs = 15_000, retryMs = 3000 }) {
    this.store = store;
    this.adapter = adapter;
    this.homeId = homeId;
    this.resolve = resolve;
    this.intervalMs = intervalMs;
    this.watchTtlMs = watchTtlMs;
    this.retryMs = retryMs;
    this.lastWatch = new Map();
    this.loops = new Map();
    this.stopped = false;
  }

  start() {
    this.channel = this.store.subscribeCameraWatch(this.homeId, (deviceId) => this.watch(deviceId));
  }

  async stop() {
    this.stopped = true;
    this.channel?.unsubscribe();
    await Promise.allSettled([...this.loops.values()]);
  }

  watch(deviceId) {
    if (this.stopped || !this.resolve(deviceId)) return; // appareil inconnu de cette passerelle
    this.lastWatch.set(deviceId, Date.now());
    if (!this.loops.has(deviceId)) {
      const loop = this.#loop(deviceId).finally(() => this.loops.delete(deviceId));
      this.loops.set(deviceId, loop);
    }
  }

  async #loop(deviceId) {
    log.info('camera.watch_start', { device_id: deviceId });
    let failing = false;
    while (!this.stopped && Date.now() - (this.lastWatch.get(deviceId) ?? 0) < this.watchTtlMs) {
      const started = Date.now();
      const target = this.resolve(deviceId);
      if (!target) break;
      try {
        const frame = await this.adapter.cameraSnapshot?.(target.externalId, target.key);
        if (!frame) break;
        const at = new Date().toISOString();
        await this.store.uploadCameraFrame(this.homeId, deviceId, frame.bytes, frame.contentType);
        await this.channel?.notify(deviceId, at);
        failing = false;
      } catch (e) {
        if (!failing) log.warn('camera.frame_failed', { device_id: deviceId, error: e.message });
        failing = true;
        await sleep(this.retryMs);
        continue;
      }
      await sleep(Math.max(0, this.intervalMs - (Date.now() - started)));
    }
    log.info('camera.watch_stop', { device_id: deviceId });
  }
}
