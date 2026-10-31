// Branche le concentrateur UDI sur un adaptateur existant (Home Assistant, Tuya Cloud,
// simulateur ou « video » seul) : mêmes appareils, mêmes commandes, sans changer le cœur
// de la passerelle. Même principe que les caméras directes et TTLock.

import { UdiHub } from './hub.js';

export { UdiHub } from './hub.js';

/** @param {any} adapter @param {UdiHub} hub */
export function addUdi(adapter, hub) {
  const base = {
    start: adapter.start.bind(adapter),
    stop: adapter.stop.bind(adapter),
    devices: adapter.devices.bind(adapter),
    snapshot: adapter.snapshot.bind(adapter),
    execute: adapter.execute.bind(adapter),
    cameraSnapshot: adapter.cameraSnapshot?.bind(adapter),
  };
  adapter.udi = hub;
  /** Appelé par la passerelle dès que le logement est connu, avant start(). */
  adapter.attachHome = ({ homeId, store, resolveDevice }) => hub.attach({ homeId, store, resolveDevice, emitter: adapter });
  adapter.start = async () => {
    await base.start();
    await hub.start();
  };
  adapter.stop = () => {
    hub.stop().catch(() => {});
    base.stop();
  };
  adapter.devices = () => [...base.devices(), ...hub.devices()];
  adapter.snapshot = (externalId) => (hub.owns(externalId) ? hub.snapshotOf(externalId) : base.snapshot(externalId));
  adapter.execute = async (externalId, ...rest) =>
    hub.owns(externalId) ? { status: 'failed', error: 'Aucune commande vidéo dans cette version' } : base.execute(externalId, ...rest);
  adapter.cameraSnapshot = async (externalId, key) => {
    if (hub.owns(externalId)) return hub.snapshot(externalId);
    return base.cameraSnapshot ? base.cameraSnapshot(externalId, key) : null;
  };
  return adapter;
}
