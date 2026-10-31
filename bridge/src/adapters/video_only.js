// Adaptateur vide (ADAPTER=video) : pour le boîtier vidéo installé dans une villa ou un
// immeuble, qui ne pilote que les caméras et visiophones (UDI). Les autres appareils du
// logement restent gérés par leur propre passerelle (Tuya, TTLock, Home Assistant…).

import { EventEmitter } from 'node:events';

export class VideoOnlyAdapter extends EventEmitter {
  async start() {
    this.emit('connection', true);
  }
  stop() {}
  devices() {
    return [];
  }
  snapshot() {
    return { state: {}, availability: 'unknown' };
  }
  async execute() {
    return { status: 'failed', error: 'Appareil inconnu de ce boîtier' };
  }
}
