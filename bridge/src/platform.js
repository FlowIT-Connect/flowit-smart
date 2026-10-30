// Passerelle de la plateforme (PLATFORM=true) : un seul compte installateur (Tuya, TTLock)
// pour tous les logements, sur le serveur de l'exploitant.
//
// L'inventaire du compte est inscrit dans platform_devices ; l'exploitant attribue chaque
// appareil à un logement depuis Solea. Pour chaque logement qui a des appareils, une
// passerelle ordinaire (Bridge) tourne sur une « vue » de l'adaptateur partagé limitée aux
// appareils de ce logement : commandes, scènes, automatisations et limite d'appareils
// fonctionnent exactement comme avec une passerelle par maison.

import { EventEmitter } from 'node:events';

import { Bridge } from './bridge.js';
import { log } from './log.js';

/** Adaptateur partagé, réduit aux appareils d'un logement. */
export class HomeAdapterView extends EventEmitter {
  constructor(shared, allowed = new Set()) {
    super();
    this.shared = shared;
    this.allowed = new Set(allowed);
    this.forward = {
      device: (externalId, snap) => {
        if (this.allowed.has(externalId)) this.emit('device', externalId, snap);
      },
      connection: (ok) => this.emit('connection', ok),
      inventory: () => this.emit('inventory'),
    };
    for (const [event, fn] of Object.entries(this.forward)) shared.on(event, fn);
    if (shared.cameraSnapshot) {
      this.cameraSnapshot = (externalId, ...rest) =>
        this.allowed.has(externalId) ? shared.cameraSnapshot(externalId, ...rest) : Promise.reject(new Error('Caméra hors de ce logement'));
    }
  }

  /** L'adaptateur partagé est démarré une seule fois par le superviseur. */
  async start() {}

  stop() {
    for (const [event, fn] of Object.entries(this.forward)) this.shared.off(event, fn);
  }

  setAllowed(ids) {
    const next = new Set(ids);
    const same = next.size === this.allowed.size && [...next].every((id) => this.allowed.has(id));
    this.allowed = next;
    if (!same) this.emit('inventory');
  }

  devices() {
    return this.shared.devices().filter((d) => this.allowed.has(d.externalId));
  }

  snapshot(externalId) {
    return this.shared.snapshot(externalId);
  }

  async execute(externalId, key, value, timeoutMs) {
    if (!this.allowed.has(externalId)) return { status: 'failed', error: 'Appareil retiré de ce logement' };
    return this.shared.execute(externalId, key, value, timeoutMs);
  }
}

export class PlatformSupervisor {
  /**
   * @param {{store, adapter, config, makeBridge?: (opts) => Bridge}} opts
   */
  constructor({ store, adapter, config, makeBridge = (opts) => new Bridge(opts) }) {
    this.store = store;
    this.adapter = adapter;
    this.config = config;
    this.makeBridge = makeBridge;
    /** homeId -> { bridge, view } */
    this.homes = new Map();
    this.timer = null;
    this.chain = Promise.resolve();
    this.stopped = false;
  }

  async start() {
    await this.adapter.start();
    this.adapter.on('inventory', () => this.refresh().catch((e) => log.error('platform.refresh_failed', { error: e.message })));
    await this.refresh();
    this.timer = setInterval(
      () => this.refresh().catch((e) => log.error('platform.refresh_failed', { error: e.message })),
      this.config.platformRefreshMs ?? 20_000,
    );
  }

  async stop() {
    this.stopped = true;
    clearInterval(this.timer);
    await this.chain.catch(() => {});
    await Promise.allSettled([...this.homes.values()].map(({ bridge }) => bridge.stop()));
    this.homes.clear();
    this.adapter.stop();
  }

  /** Une passe à la fois : inventaire inscrit, attributions lues, passerelles par logement à jour. */
  refresh() {
    const run = this.chain.catch(() => {}).then(() => this.#refresh());
    this.chain = run;
    return run;
  }

  async #refresh() {
    if (this.stopped) return;
    const inventory = this.adapter.devices().map((d) => ({
      external_id: d.externalId,
      name: d.name,
      vendor: d.vendor ?? null,
      model: d.model ?? null,
      protocol: d.protocol ?? null,
      image_url: d.imageUrl ?? null,
    }));
    const assignments = await this.store.syncPlatformDevices(inventory);
    const byHome = new Map();
    for (const { external_id: externalId, home_id: homeId } of assignments) {
      if (!byHome.has(homeId)) byHome.set(homeId, new Set());
      byHome.get(homeId).add(externalId);
    }

    for (const [homeId, ids] of byHome) {
      const running = this.homes.get(homeId);
      if (running) {
        running.view.setAllowed(ids); // nouvel inventaire : la passerelle du logement se resynchronise
        continue;
      }
      try {
        const integrationId = await this.store.ensurePlatformIntegration(homeId, [...ids]);
        const view = new HomeAdapterView(this.adapter, ids);
        const bridge = this.makeBridge({
          store: this.store,
          adapter: view,
          config: { ...this.config, integrationId, installerOnly: true },
        });
        await bridge.start();
        this.homes.set(homeId, { bridge, view });
        log.info('platform.home_started', { home_id: homeId, devices: ids.size });
      } catch (e) {
        log.error('platform.home_failed', { home_id: homeId, error: e.message }); // nouvel essai à la passe suivante
      }
    }

    for (const [homeId, { bridge, view }] of this.homes) {
      if (byHome.has(homeId)) continue;
      // Plus aucun appareil attribué : la passerelle de ce logement s'arrête.
      this.homes.delete(homeId);
      view.setAllowed([]);
      await bridge.stop().catch(() => {});
      view.stop();
      log.info('platform.home_stopped', { home_id: homeId });
    }
    const unassigned = inventory.length - assignments.filter((a) => inventory.some((d) => d.external_id === a.external_id)).length;
    log.info('platform.synced', { devices: inventory.length, homes: this.homes.size, unassigned });
  }
}
