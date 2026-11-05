// Adaptateur Tuya Cloud (ADAPTER=tuya_cloud) : pilote les appareils Wi-Fi Tuya / Smart Life
// directement par le cloud Tuya, sans box Home Assistant. Nécessite Internet.
//
// Le cloud Tuya ne pousse pas les changements d'état sans service de messages (Pulsar) :
// la passerelle interroge l'état périodiquement (TUYA_POLL_SECONDS) et, après une commande,
// relit l'appareil jusqu'à voir la nouvelle valeur avant de confirmer (§5.4).

import { EventEmitter } from 'node:events';

import { log } from '../log.js';
import { buildTuyaDevice, statusMap, tuyaSnapshot, tuyaStateMatches } from './tuya_mapping.js';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Catégories Tuya des passerelles (Zigbee, Bluetooth, multi-protocoles). */
const GATEWAY_CATEGORIES = new Set(['wg', 'wg2', 'wgsxj', 'wfcon', 'dgnzk', 'zigbee', 'gateway']);
const GATEWAY_NAME = /gateway|passerelle|\bhub\b|zigbee|网关/i;

/** Passerelle Smart Life susceptible d'avoir des sous-appareils ? */
export function isTuyaGateway(dev) {
  if (dev?.sub === true) return false;
  return GATEWAY_CATEGORIES.has(dev?.category) || GATEWAY_NAME.test(`${dev?.product_name ?? ''} ${dev?.name ?? ''}`);
}

/**
 * Spécification minimale déduite des états, quand Tuya refuse de donner la vraie
 * (certains sous-appareils Zigbee) : lecture seule, rien n'est piloté à l'aveugle.
 */
export function specFromStatus(dev) {
  const status = [];
  for (const { code, value } of dev?.status ?? []) {
    const type = typeof value === 'boolean' ? 'Boolean' : typeof value === 'number' ? 'Integer' : 'Enum';
    status.push({ code, type, values: type === 'Enum' ? { range: [String(value)] } : {} });
  }
  return { category: dev?.category, functions: [], status };
}

export class TuyaCloudAdapter extends EventEmitter {
  /**
   * @param {{client:import('./tuya_api.js').TuyaClient, pollMs?:number, confirmPollMs?:number, inventoryEveryMs?:number}} opts
   */
  constructor({ client, pollMs = 30_000, confirmPollMs = 1_000, inventoryEveryMs = 30 * 60_000, subScanEveryMs = 2 * 60_000, imageBase = null }) {
    super();
    this.client = client;
    this.imageBase = imageBase;
    this.pollMs = pollMs;
    this.confirmPollMs = confirmPollMs;
    this.inventoryEveryMs = inventoryEveryMs;
    this.subScanEveryMs = subScanEveryMs;
    this.subDevices = new Map(); // tuyaId -> sous-appareil d'une passerelle (absent de la liste du compte)
    this.lastSubScan = 0;
    this.cloudIds = new Set(); // identifiants vus au dernier inventaire
    this.inventory = new Map(); // externalId -> descripteur
    this.status = new Map(); // tuyaId -> Map(code -> value)
    this.online = new Map(); // tuyaId -> boolean
    this.specs = new Map(); // tuyaId -> spécification (mise en cache)
    this.connected = false;
    this.timer = null;
    this.lastInventory = 0;
    this.polling = false;
  }

  async start() {
    await this.#refreshInventory(await this.#listAll(true));
    this.#setConnected(true);
    this.timer = setInterval(() => this.#poll(), this.pollMs);
  }

  stop() {
    clearInterval(this.timer);
  }

  devices() {
    return [...this.inventory.values()];
  }

  snapshot(externalId) {
    const d = this.inventory.get(externalId);
    return d ? tuyaSnapshot(d, this.status.get(d.tuyaId) ?? new Map(), this.online.get(d.tuyaId)) : { state: {}, availability: 'unavailable' };
  }

  #setConnected(ok) {
    if (ok === this.connected) return;
    this.connected = ok;
    this.emit('connection', ok);
  }

  /**
   * Appareils du compte + sous-appareils des passerelles (Zigbee…). Selon le compte et
   * la région, Tuya ne renvoie pas toujours les sous-appareils dans la liste du compte :
   * on interroge chaque passerelle (toutes les `subScanEveryMs`), puis on lit l'état
   * des sous-appareils manquants un par un.
   */
  async #listAll(forceSubScan = false) {
    const list = await this.client.listDevices();
    const ids = new Set(list.map((d) => d.id));
    const gateways = list.filter(isTuyaGateway);
    if (gateways.length && (forceSubScan || Date.now() - this.lastSubScan > this.subScanEveryMs)) {
      const next = new Map();
      for (const gw of gateways) {
        try {
          const subs = await this.client.subDevices(gw.id);
          for (const sub of subs) if (sub?.id && !ids.has(sub.id)) next.set(sub.id, { ...sub, gateway_id: gw.id });
          log.info('tuya.gateway', { gateway: gw.id, category: gw.category, sub_devices: subs.length });
        } catch (e) {
          log.warn('tuya.sub_devices_failed', { gateway: gw.id, error: e.message });
          for (const [id, sub] of this.subDevices) if (sub.gateway_id === gw.id) next.set(id, sub);
        }
      }
      this.subDevices = next;
      this.lastSubScan = Date.now();
    }
    for (const [id, sub] of this.subDevices) {
      if (ids.has(id)) continue;
      try {
        const d = await this.client.device(id);
        list.push({ ...sub, ...d, id, gateway_id: sub.gateway_id });
      } catch (e) {
        log.warn('tuya.sub_device_read_failed', { device: id, error: e.message });
        list.push({ ...sub, status: sub.status ?? [] });
      }
    }
    return list;
  }

  async #refreshInventory(list) {
    const next = new Map();
    for (const dev of list) {
      let spec = this.specs.get(dev.id);
      if (!spec) {
        try {
          spec = await this.client.specifications(dev.id);
          this.specs.set(dev.id, spec);
        } catch (e) {
          // Réessayé au prochain inventaire ; en attendant, lecture seule d'après l'état.
          log.warn('tuya.specification_failed', { device: dev.id, category: dev.category, error: e.message });
          spec = specFromStatus(dev);
        }
      }
      const desc = buildTuyaDevice(dev, spec, { imageBase: this.imageBase });
      if (!desc.capabilities.length) {
        const codes = [...new Set([...(spec?.functions ?? []), ...(spec?.status ?? []), ...(dev.status ?? [])].map((f) => f.code))];
        log.info('tuya.device_ignored', { device: dev.id, name: dev.name, category: dev.category, codes, reason: isTuyaGateway(dev) ? 'passerelle (ses appareils sont importés à part)' : 'aucune fonction reconnue' });
        continue;
      }
      next.set(desc.externalId, desc);
      this.status.set(dev.id, statusMap(dev.status));
      this.online.set(dev.id, dev.online !== false);
    }
    this.inventory = next;
    this.cloudIds = new Set(list.map((d) => d.id));
    this.lastInventory = Date.now();
    if (!list.length) log.warn('tuya.no_devices', { hint: 'Aucun appareil : liez le compte Smart Life au projet cloud (Devices > Link App Account) et vérifiez le data center' });
    log.info('tuya.inventory', { devices: next.size, cloud_devices: list.length });
    this.emit('inventory');
  }

  /** Relecture immédiate (ajout d'un appareil depuis l'application). */
  rescan() {
    return this.#poll(true);
  }

  async #poll(forceSubScan = false) {
    if (this.polling) return;
    this.polling = true;
    try {
      const list = await this.#listAll(forceSubScan);
      this.#setConnected(true);
      // Tous les appareils vus au dernier inventaire, ignorés compris (passerelle, télécommande
      // IR…) : sinon chaque interrogation refait l'inventaire et les changements d'état ne
      // déclenchent plus les automatisations.
      const known = this.cloudIds;
      const ids = new Set(list.map((d) => d.id));
      const changed = list.some((d) => !known.has(d.id)) || [...known].some((id) => !ids.has(id));
      if (changed || Date.now() - this.lastInventory > this.inventoryEveryMs) {
        await this.#refreshInventory(list);
        return;
      }
      for (const dev of list) this.#applyStatus(dev.id, statusMap(dev.status), dev.online !== false);
    } catch (e) {
      log.error('tuya.poll_failed', { error: e.message });
      this.#setConnected(false);
    } finally {
      this.polling = false;
    }
  }

  #applyStatus(tuyaId, status, online) {
    const before = JSON.stringify([...(this.status.get(tuyaId) ?? [])]) + this.online.get(tuyaId);
    // Fusion : une réponse partielle ne doit pas effacer les autres valeurs connues.
    const merged = new Map([...(this.status.get(tuyaId) ?? []), ...status]);
    this.status.set(tuyaId, merged);
    this.online.set(tuyaId, online);
    if (before === JSON.stringify([...merged]) + online) return;
    const externalId = `tuya:${tuyaId}`;
    if (this.inventory.has(externalId)) this.emit('device', externalId, this.snapshot(externalId));
  }

  /**
   * Envoie la commande au cloud Tuya puis relit l'appareil jusqu'à voir la valeur demandée.
   * @returns {Promise<{status:'confirmed'|'failed'|'timeout', error?:string}>}
   */
  async execute(externalId, key, value, timeoutMs) {
    const device = this.inventory.get(externalId);
    const entry = device?.capMap[key];
    if (!entry?.write) return { status: 'failed', error: 'Capacité absente côté Tuya' };
    if (!this.online.get(device.tuyaId)) return { status: 'failed', error: 'Appareil indisponible (hors ligne dans Smart Life)' };
    const deadline = Date.now() + timeoutMs;
    try {
      await this.client.sendCommands(device.tuyaId, entry.write(value, this.status.get(device.tuyaId)));
      while (Date.now() < deadline) {
        await sleep(Math.min(this.confirmPollMs, Math.max(0, deadline - Date.now())));
        const d = await this.client.device(device.tuyaId);
        this.#applyStatus(device.tuyaId, statusMap(d.status), d.online !== false);
        if (d.online === false) return { status: 'failed', error: 'Appareil indisponible (hors ligne dans Smart Life)' };
        if (tuyaStateMatches(entry, this.status.get(device.tuyaId), value)) return { status: 'confirmed' };
      }
      return { status: 'timeout', error: 'Aucun retour d\'état de l\'appareil dans le délai' };
    } catch (e) {
      return { status: 'failed', error: e.message };
    }
  }
}
