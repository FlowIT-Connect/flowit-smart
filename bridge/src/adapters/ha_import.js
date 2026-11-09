// Appareils de Home Assistant ajoutés à une autre passerelle (Smart Life, TTLock, yeedi).
//
// Sur la box, le module FlowIT Bridge en mode tuya_cloud peut aussi reprendre les appareils
// de certaines intégrations de Home Assistant (par défaut Broadlink : télécommande
// infrarouge et son capteur de température / humidité). Seules les intégrations listées
// sont reprises : les appareils que Solea publie lui-même dans HA par MQTT ne reviennent
// jamais dans Solea en double.

import { log } from '../log.js';

/** Appareil venu de Home Assistant (jamais republié dans HA par l'export MQTT). */
export const isHaExternalId = (externalId) => /^(device|entity):/.test(String(externalId));

/**
 * Greffe l'adaptateur Home Assistant `ha` sur `adapter` (même principe que addYeedi).
 * Home Assistant injoignable : les autres appareils continuent de fonctionner.
 */
export function addHomeAssistant(adapter, ha) {
  const base = {
    start: adapter.start.bind(adapter),
    stop: adapter.stop.bind(adapter),
    devices: adapter.devices.bind(adapter),
    snapshot: adapter.snapshot.bind(adapter),
    execute: adapter.execute.bind(adapter),
  };
  ha.on('device', (id, snap) => adapter.emit('device', id, snap));
  ha.on('inventory', () => adapter.emit('inventory'));
  adapter.start = async () => {
    await base.start();
    ha.start().catch((e) => {
      // Nouvel essai par l'adaptateur HA lui-même dès que la connexion revient.
      log.error('ha_import.unreachable', { error: e.message, hint: 'Home Assistant est-il démarré ?' });
      setTimeout(() => adapter.emit('ha_retry'), 0);
    });
  };
  let retry = null;
  adapter.on('ha_retry', () => {
    clearTimeout(retry);
    retry = setTimeout(() => ha.start().catch(() => adapter.emit('ha_retry')), 30_000);
  });
  adapter.stop = () => {
    clearTimeout(retry);
    ha.stop();
    base.stop();
  };
  adapter.devices = () => [...base.devices(), ...ha.devices()];
  adapter.snapshot = (externalId) => (isHaExternalId(externalId) ? ha.snapshot(externalId) : base.snapshot(externalId));
  adapter.execute = (externalId, key, value, timeoutMs, ...rest) =>
    isHaExternalId(externalId) ? ha.execute(externalId, key, value, timeoutMs) : base.execute(externalId, key, value, timeoutMs, ...rest);
  return adapter;
}
