// Cœur de la passerelle : synchronisation de l'inventaire, exécution des commandes
// (pending → sent → confirmed | failed | timeout | rejected) et automatisations locales.

import {
  activeModes,
  closedCovers,
  conditionsHold,
  exceptionHolds,
  localTime,
  modeTriggerFired,
  presencePlan,
  stateTriggerFired,
  sunTriggerDue,
  timeTriggerDue,
  weatherTriggerHolds,
} from './automations.js';
import { DEFAULT_PRESETS, deviceCommands, effectivePreset, seasonMode } from './climate.js';
import { fetchWeather } from './weather.js';
import { CameraStreamer } from './cameras.js';
import { log } from './log.js';
import { validateValue } from './validate.js';

/** Passerelle de la plateforme : les appareils sont posés et attribués par l'installateur. */
export const INSTALLER_ONLY_MESSAGE = 'Les appareils de ce logement sont installés par votre installateur Solea';

export const DEVICE_LIMIT_MESSAGE = 'Limite d\'appareils atteinte : demandez le déblocage dans Solea';

/** Refus de la base quand le logement a atteint sa limite d'appareils (migration solea_plans). */
export function isDeviceLimit(e) {
  return String(e?.message ?? '').includes('LIMITE_APPAREILS');
}

export class Bridge {
  /**
   * @param {{store:any, adapter:any, config:any, clock?:()=>Date}} deps
   */
  constructor({ store, adapter, config, clock = () => new Date(), weatherFetcher = fetchWeather }) {
    this.store = store;
    this.weatherFetcher = weatherFetcher;
    this.adapter = adapter;
    this.config = config;
    this.clock = clock;
    this.homeId = null;
    this.timezone = 'Africa/Algiers';
    this.enabled = true;
    /** deviceId -> { externalId, caps: Map<key, cap>, isSensitive, state, availability } */
    this.devices = new Map();
    this.byExternal = new Map();
    /** Appareils refusés faute de place dans le logement (null : pas encore compté). */
    this.waitingDevices = null;
    this.automations = [];
    this.firedTimeKeys = new Map();
    this.lastAutomationRun = new Map();
    /** Météo du logement (null : pas de position ou pas encore lue). */
    this.weather = null;
    /** Déclencheurs météo : depuis quand le seuil est dépassé, et déjà exécutés. */
    this.weatherSince = new Map();
    this.weatherFired = new Set();
    this.weatherConfirm = null;
    /** « PUIS » en attente : automationId -> { timer, deadline }. */
    this.followUps = new Map();
    /** Exécutions récentes par automatisation (coupe-circuit anti-boucle). */
    this.recentRuns = new Map();
    /** Modes du logement (été / hiver / vacances) et simulation de présence. */
    this.modeRow = null;
    this.modes = [];
    this.simulation = null; // { day, plan: [{id, on, off, state}] }
    /** Chauffage / clim : ambiance déjà appliquée par zone (zoneId -> signature). */
    this.climateApplied = new Map();
    this.inflightDevices = new Set();
    this.inflightRuns = new Set();
    this.running = new Set();
    this.timers = [];
    this.queueBusy = false;
    this.queueAgain = false;
    this.pairingBusy = false;
    this.pairingsAvailable = true;
    /** Appareils déjà attribués à une demande d'ajout (deux demandes ne prennent pas le même). */
    this.pairedDevices = new Set();
    this.stopped = false;
  }

  async start() {
    const integ = await this.store.getIntegration(this.config.integrationId);
    if (!integ) throw new Error(`Intégration introuvable : ${this.config.integrationId}`);
    this.homeId = integ.home_id;
    this.enabled = integ.status !== 'disabled';
    const home = await this.store.getHome(this.homeId);
    if (home?.timezone) this.timezone = home.timezone;
    log.info('bridge.start', { integration_id: integ.id, home_id: this.homeId, provider: integ.provider, timezone: this.timezone });

    this.adapter.on('inventory', () => this.syncInventory().catch((e) => log.error('bridge.sync_failed', { error: e.message })));
    this.adapter.on('device', (externalId, snap) => this.onDeviceState(externalId, snap).catch((e) => log.error('bridge.state_failed', { error: e.message })));
    this.adapter.on('connection', (ok) =>
      this.store.setIntegrationStatus(this.config.integrationId, ok ? 'connected' : 'error', ok ? null : 'Moteur domotique injoignable').catch(() => {}),
    );

    // Équipements vidéo (UDI) : le concentrateur a besoin du logement avant de démarrer.
    this.adapter.attachHome?.({ homeId: this.homeId, store: this.store, resolveDevice: (deviceId) => this.devices.get(deviceId)?.externalId ?? null });

    try {
      await this.adapter.start();
    } catch (e) {
      await this.store.setIntegrationStatus(this.config.integrationId, 'error', e.message).catch(() => {});
      throw e;
    }
    await this.syncInventory();
    // Commandes restées "sent" lors d'un arrêt brutal : résultat inconnu, on le dit (§5.4).
    await this.store.failInflight([...this.devices.keys()], 'Passerelle redémarrée pendant la commande');
    if (this.enabled) await this.store.setIntegrationStatus(this.config.integrationId, 'connected', null);

    this.unsubscribe = this.store.subscribeCommands(this.homeId, () => this.processQueue());
    const every = (ms, fn) => this.timers.push(setInterval(() => fn().catch((e) => log.error('bridge.timer_failed', { error: e.message })), ms));
    every(this.config.pollIntervalMs, () => this.processQueue());
    every(this.config.pollIntervalMs * 5, () => this.sweepStale());
    await this.store.failStalePairings?.(this.homeId, this.#pairingCutoff(), 'Passerelle redémarrée pendant l\'ajout : recommencez').catch(() => {});
    every(this.config.pollIntervalMs, () => this.processPairings());
    if (this.config.runAutomations !== false) {
      await this.refreshAutomations();
      every(this.config.automationRefreshMs, () => this.refreshAutomations());
      // Boîtier vidéo à côté d'une autre passerelle : seuls les déclencheurs de SES appareils
      // (mouvement d'une caméra…) tournent ici ; les déclencheurs horaires restent à l'autre.
      if (this.config.runTimeTriggers !== false) {
        every(10_000, () => this.tickTimeTriggers());
        every(60_000, async () => {
          await this.evaluateModes(); // départ / retour atteint
          await this.tickPresenceSimulation();
          await this.tickClimate();
        });
        // Météo lue par la passerelle elle-même : les règles tournent même téléphone éteint.
        if (this.config.weather !== false) {
          await this.refreshWeather().catch((e) => log.warn('weather.failed', { error: e.message }));
          every(this.config.weatherIntervalMs ?? 300_000, () => this.refreshWeather());
        }
      }
    }
    if (this.store.subscribeCameraWatch) {
      this.cameras = new CameraStreamer({
        store: this.store,
        adapter: this.adapter,
        homeId: this.homeId,
        resolve: (deviceId) => this.cameraTarget(deviceId),
        intervalMs: this.config.cameraIntervalMs ?? 1000,
      });
      this.cameras.start();
    }
    await this.processQueue();
  }

  async stop() {
    this.stopped = true;
    for (const t of this.timers) clearInterval(t);
    for (const f of this.followUps.values()) clearTimeout(f.timer);
    this.followUps.clear();
    clearTimeout(this.weatherConfirm);
    this.unsubscribe?.();
    await this.cameras?.stop();
    this.adapter.stop();
    await Promise.allSettled([...this.running]);
  }

  // ------------------------------------------------------------------ Inventaire
  /** Une synchronisation à la fois : deux passes simultanées créeraient des appareils en double. */
  syncInventory() {
    const run = (this.syncChain ?? Promise.resolve()).catch(() => {}).then(() => this.#syncInventory());
    this.syncChain = run;
    return run;
  }

  async #syncInventory() {
    const bindings = new Map((await this.store.listBindings(this.config.integrationId)).map((b) => [b.external_id, b.device_id]));
    const seen = new Set();
    const now = this.clock().toISOString();
    let waiting = 0;
    for (const desc of this.adapter.devices()) {
      const snap = this.adapter.snapshot(desc.externalId);
      let deviceId = bindings.get(desc.externalId);
      const common = {
        vendor: desc.vendor,
        model: desc.model,
        protocol: desc.protocol,
        connection_source: desc.connectionSource,
        ...(desc.imageUrl ? { image_url: desc.imageUrl } : {}), // photo officielle du produit
        availability: snap.availability,
        state: snap.state,
        ...(snap.availability === 'available' ? { last_seen_at: now } : {}),
        ...(desc.isSensitive ? { is_sensitive: true } : {}), // jamais abaissé par la passerelle
      };
      if (deviceId) {
        await this.store.updateDevice(deviceId, common);
        await this.store.replaceCapabilities(deviceId, desc.capabilities);
      } else {
        try {
          deviceId = await this.store.createDevice(
            { home_id: this.homeId, integration_id: this.config.integrationId, name: desc.name, ...common },
            desc.externalId,
            desc.capabilities,
          );
        } catch (e) {
          if (!isDeviceLimit(e)) throw e;
          // Logement à sa limite : l'appareil sera créé au premier inventaire après le déblocage.
          waiting++;
          continue;
        }
        log.info('bridge.device_created', { device_id: deviceId, protocol: desc.protocol });
      }
      seen.add(desc.externalId);
      const prev = this.devices.get(deviceId);
      let bleKey = desc.bleKey;
      if (desc.bleKey !== undefined && desc.bleKey !== prev?.bleKey) {
        // Jamais dans les journaux : la clé ouvre la serrure.
        try {
          await this.store.saveBleKey(deviceId, this.homeId, desc.bleKey);
          log.info('bridge.ble_key_synced', { device_id: deviceId, present: Boolean(desc.bleKey) });
        } catch (e) {
          // Base pas encore à jour, par exemple : le reste de l'inventaire continue.
          log.warn('bridge.ble_key_failed', { device_id: deviceId, error: e.message });
          bleKey = prev?.bleKey; // nouvel essai au prochain inventaire
        }
      }
      this.devices.set(deviceId, {
        externalId: desc.externalId,
        caps: new Map(desc.capabilities.map((c) => [c.capability_key, c])),
        isSensitive: desc.isSensitive || prev?.isSensitive || false,
        bleKey,
        state: snap.state,
        availability: snap.availability,
      });
      this.byExternal.set(desc.externalId, deviceId);
    }
    for (const [externalId, deviceId] of bindings) {
      if (!seen.has(externalId)) await this.store.updateDevice(deviceId, { availability: 'unavailable' });
    }
    await this.store.setIntegrationStatus(this.config.integrationId, this.enabled ? 'connected' : 'disabled', null, now);
    if (waiting !== this.waitingDevices) {
      if (waiting) log.warn('bridge.device_limit_reached', { waiting });
      try {
        await this.store.setWaitingDevices(this.homeId, waiting);
        this.waitingDevices = waiting;
      } catch (e) {
        log.warn('bridge.waiting_devices_failed', { error: e.message }); // base pas encore à jour
      }
    }
    log.info('bridge.inventory_synced', { devices: seen.size, ...(waiting ? { waiting } : {}) });
    return { waiting };
  }

  async onDeviceState(externalId, snap) {
    const deviceId = this.byExternal.get(externalId);
    const dev = deviceId && this.devices.get(deviceId);
    if (!dev) return;
    const before = dev.state;
    if (JSON.stringify(before) === JSON.stringify(snap.state) && dev.availability === snap.availability) return;
    dev.state = snap.state;
    dev.availability = snap.availability;
    await this.store.updateDevice(deviceId, {
      state: snap.state,
      availability: snap.availability,
      ...(snap.availability === 'available' ? { last_seen_at: this.clock().toISOString() } : {}),
    });
    if (this.config.runAutomations !== false) await this.evaluateStateTriggers(deviceId, before, snap.state);
  }

  /** Caméra d'un appareil connu de cette passerelle (null sinon). */
  cameraTarget(deviceId) {
    const dev = this.devices.get(deviceId);
    if (!dev) return null;
    for (const [key, cap] of dev.caps) if (cap.metadata?.kind === 'camera') return { externalId: dev.externalId, key };
    return null;
  }

  // ------------------------------------------------------------------ Commandes
  async processQueue() {
    if (this.queueBusy) {
      this.queueAgain = true;
      return;
    }
    this.queueBusy = true;
    try {
      do {
        this.queueAgain = false;
        const ids = [...this.devices.keys()];
        if (!ids.length) return;
        const due = await this.store.fetchDueCommands(this.homeId, ids, this.clock().toISOString());
        const runsSeen = new Set();
        for (const cmd of due) {
          // Scène : une action à la fois, dans l'ordre (le délai est porté par not_before).
          if (cmd.scene_run_id) {
            if (runsSeen.has(cmd.scene_run_id) || this.inflightRuns.has(cmd.scene_run_id)) continue;
            runsSeen.add(cmd.scene_run_id);
          }
          if (this.inflightDevices.has(cmd.device_id)) continue; // une commande à la fois par appareil
          const p = this.executeCommand(cmd).finally(() => {
            this.running.delete(p);
            this.processQueue().catch(() => {});
          });
          this.running.add(p);
        }
      } while (this.queueAgain);
    } finally {
      this.queueBusy = false;
    }
  }

  async executeCommand(cmd) {
    const dev = this.devices.get(cmd.device_id);
    if (!dev) return;
    this.inflightDevices.add(cmd.device_id);
    if (cmd.scene_run_id) this.inflightRuns.add(cmd.scene_run_id);
    try {
      if (!(await this.store.claimCommand(cmd.id))) return; // déjà traitée ailleurs
      const started = Date.now();
      const cap = dev.caps.get(cmd.capability_key);
      let result;
      if (!this.enabled) result = { status: 'rejected', error: 'Intégration désactivée' };
      else if (dev.isSensitive && !(await this.sensitiveAllowed(cmd))) {
        result = { status: 'rejected', error: 'Commande bloquée : appareil sensible non validé' };
      } else {
        const invalid = validateValue(cap, cmd.value);
        result = invalid
          ? { status: 'rejected', error: invalid }
          : await this.adapter.execute(dev.externalId, cmd.capability_key, cmd.value, this.config.commandTimeoutMs);
      }
      if (result.accessCode) {
        try {
          await this.store.saveAccessCode({ ...result.accessCode, home_id: this.homeId, device_id: cmd.device_id, command_id: cmd.id, created_by: cmd.requested_by ?? null });
        } catch (e) {
          log.error('bridge.access_code_save_failed', { request_id: cmd.id, error: e.message });
          result = { status: 'failed', error: 'Code créé mais non enregistré : réessayez' };
        }
      }
      await this.store.completeCommand(cmd.id, result.status, result.error ?? null);
      log.info('bridge.command', {
        request_id: cmd.id,
        device_id: cmd.device_id,
        capability: cmd.capability_key,
        status: result.status,
        ms: Date.now() - started,
        ...(result.error ? { error: result.error } : {}),
      });
      if (result.status === 'confirmed') await this.onDeviceState(dev.externalId, this.adapter.snapshot(dev.externalId));
    } catch (e) {
      log.error('bridge.command_error', { request_id: cmd.id, error: e.message });
      await this.store.completeCommand(cmd.id, 'failed', 'Erreur interne de la passerelle').catch(() => {});
    } finally {
      this.inflightDevices.delete(cmd.device_id);
      if (cmd.scene_run_id) this.inflightRuns.delete(cmd.scene_run_id);
    }
  }

  /**
   * Appareil sensible (serrure) : demande manuelle d'un membre, appareil activé par le
   * propriétaire. Revérifié ici : la validation a pu être retirée depuis la demande.
   */
  async sensitiveAllowed(cmd) {
    if (!cmd.requested_by || cmd.scene_run_id || cmd.automation_id) return false;
    return this.store.isSecurityValidated(cmd.device_id);
  }

  async sweepStale() {
    const limit = new Date(this.clock().getTime() - this.config.pendingMaxAgeMs).toISOString();
    const n = await this.store.expireCommands(this.homeId, [...this.devices.keys()], limit, 'Aucune passerelle disponible pour exécuter la commande à temps');
    if (n) log.warn('bridge.commands_expired', { count: n });
  }

  // ------------------------------------------------------------------ Ajout d'appareils depuis l'application
  #pairingCutoff() {
    return new Date(this.clock().getTime() - (this.config.pairingMaxAgeMs ?? 15 * 60_000)).toISOString();
  }

  async processPairings() {
    if (this.pairingBusy || !this.pairingsAvailable || !this.store.fetchPairings) return;
    this.pairingBusy = true;
    try {
      let list;
      try {
        list = await this.store.fetchPairings(this.homeId);
      } catch (e) {
        // Base pas encore mise à jour (migration solea_pairing) : le reste continue.
        this.pairingsAvailable = false;
        log.warn('bridge.pairing_unavailable', { error: e.message });
        return;
      }
      for (const req of list) {
        // Serrure : seule une passerelle reliée à TTLock peut l'enregistrer.
        if (req.kind === 'ttlock_lock' && !this.adapter.pairLock && !this.config.installerOnly) continue;
        if (Date.parse(req.created_at) < Date.parse(this.#pairingCutoff())) {
          if (await this.store.claimPairing(req.id)) await this.store.completePairing(req.id, 'failed', 'Demande trop ancienne : recommencez', null);
          continue;
        }
        if (!(await this.store.claimPairing(req.id))) continue;
        const p = this.runPairing(req).finally(() => this.running.delete(p));
        this.running.add(p);
      }
    } finally {
      this.pairingBusy = false;
    }
  }

  async runPairing(req) {
    const started = Date.now();
    let status = 'failed';
    let error = null;
    let deviceId = null;
    try {
      if (this.config.installerOnly) throw new Error(INSTALLER_ONLY_MESSAGE);
      if (!this.enabled) throw new Error('Intégration désactivée');
      deviceId = req.kind === 'ttlock_lock' ? await this.#pairLock(req) : await this.#findPaired(req);
      if (deviceId) {
        const patch = { ...(req.name ? { name: req.name } : {}), ...(req.room_id ? { room_id: req.room_id } : {}) };
        if (Object.keys(patch).length) await this.store.updateDevice(deviceId, patch);
        status = 'done';
      } else if (this.waitingDevices) {
        error = DEVICE_LIMIT_MESSAGE;
      } else {
        error =
          req.kind === 'ttlock_lock'
            ? 'Serrure enregistrée chez TTLock mais pas encore visible : patientez une minute'
            : 'Aucun nouvel appareil trouvé : vérifiez qu\'il apparaît dans Smart Life, puis recommencez';
      }
    } catch (e) {
      error = e.message;
    }
    try {
      await this.store.completePairing(req.id, status, error, deviceId);
    } catch (e) {
      log.error('bridge.pairing_save_failed', { request_id: req.id, error: e.message });
    }
    // Jamais la clé de la serrure dans les journaux.
    log.info('bridge.pairing', { request_id: req.id, kind: req.kind, status, device_id: deviceId, ms: Date.now() - started, ...(error ? { error } : {}) });
  }

  /** Serrure installée en Bluetooth par l'application : enregistrée sur le compte TTLock. */
  async #pairLock(req) {
    const externalId = await this.adapter.pairLock(req.lock_data, req.name);
    await this.syncInventory();
    const deviceId = this.byExternal.get(externalId) ?? null;
    if (deviceId) this.pairedDevices.add(deviceId);
    return deviceId;
  }

  /** Appareil couplé dans Smart Life : relit l'inventaire jusqu'à voir un nouvel appareil. */
  async #findPaired(req) {
    const deadline = Date.now() + (this.config.pairingScanMs ?? 5 * 60_000);
    while (!this.stopped) {
      try {
        await this.adapter.rescan?.();
        await this.syncInventory();
      } catch (e) {
        log.warn('bridge.pairing_scan_failed', { request_id: req.id, error: e.message });
      }
      const id = await this.store.findNewDevice(this.config.integrationId, req.created_at, [...this.pairedDevices]);
      if (id) {
        this.pairedDevices.add(id);
        return id;
      }
      if (this.waitingDevices || Date.now() >= deadline) return null;
      await new Promise((r) => setTimeout(r, this.config.pairingRetryMs ?? 10_000));
    }
    return null;
  }

  // ------------------------------------------------------------------ Automatisations (exécution locale, §5.9)
  async refreshAutomations() {
    const list = await this.store.listAutomations(this.homeId);
    // Règles de sécurité d'abord (vent fort, fuite…).
    this.automations = [...list].sort((a, b) => (b.priority === 'security') - (a.priority === 'security'));
    const integ = await this.store.getIntegration(this.config.integrationId);
    this.enabled = integ?.status !== 'disabled';
    await this.refreshModes();
  }

  // ------------------------------------------------------------------ Modes Été / Hiver / Vacances
  async refreshModes() {
    try {
      this.modeRow = (await this.store.getHomeModes?.(this.homeId)) ?? null;
    } catch {
      this.modeRow = null; // base pas encore à jour
    }
    await this.evaluateModes();
  }

  /** Changement de mode (réglage ou date de départ / retour atteinte) → déclencheurs « mode ». */
  async evaluateModes() {
    const before = this.modes;
    const after = activeModes(this.modeRow, this.clock());
    this.modes = after;
    // Premier relevé après un redémarrage : pas de déclenchement, le mode était déjà là.
    if (!this.modesLoaded) {
      this.modesLoaded = true;
      return;
    }
    if (before.join() === after.join()) return;
    log.info('modes.changed', { modes: after });
    const now = localTime(this.clock(), this.timezone);
    for (const a of this.automations) {
      if (modeTriggerFired(a.trigger, before, after)) await this.runAutomation(a, now, `mode:${a.trigger.mode}:${a.trigger.event ?? 'start'}`);
    }
    if (!after.includes('vacation')) await this.#endSimulation();
  }

  /**
   * Simulation de présence pendant les vacances : lumières choisies allumées puis
   * éteintes à des heures différentes chaque soir, à partir du coucher du soleil.
   */
  async tickPresenceSimulation() {
    const row = this.modeRow;
    const ids = Array.isArray(row?.simulation_devices) ? row.simulation_devices.filter((id) => this.devices.has(id)) : [];
    if (!this.modes.includes('vacation') || !row?.presence_simulation || !ids.length) {
      await this.#endSimulation();
      return;
    }
    const now = localTime(this.clock(), this.timezone);
    const day = now.key.slice(0, 10);
    if (this.simulation?.day !== day) {
      const sunset = this.weather?.sunset instanceof Date ? localTime(this.weather.sunset, this.timezone) : null;
      const start = Math.min(21 * 60, sunset && sunset.key.slice(0, 10) === day ? sunset.minutes : 19 * 60);
      this.simulation = { day, plan: presencePlan(ids, start, this.random ?? Math.random).map((p) => ({ ...p, state: false })) };
    }
    for (const p of this.simulation.plan) {
      const want = now.minutes >= p.on && now.minutes < p.off;
      if (want !== p.state) {
        p.state = want;
        await this.#simCommand(p.id, want, `${day}:${p.id}:${want ? 'on' : 'off'}`);
      }
    }
  }

  async #endSimulation() {
    const sim = this.simulation;
    this.simulation = null;
    for (const p of sim?.plan ?? []) {
      if (p.state) await this.#simCommand(p.id, false, `${sim.day}:${p.id}:end`);
    }
  }

  async #simCommand(deviceId, on, key) {
    try {
      await this.store.insertCommand({ home_id: this.homeId, device_id: deviceId, capability_key: 'switch', value: on, idempotency_key: `sim:${key}` });
      log.info('presence.simulation', { device_id: deviceId, on });
      await this.processQueue();
    } catch (e) {
      log.warn('presence.simulation_failed', { error: e.message });
    }
  }

  // ------------------------------------------------------------------ Chauffage et clim par pièce
  /**
   * Applique l'ambiance de chaque pièce (Confort, Éco, Nuit, Absence, Hors-gel) quand elle
   * change. Entre deux changements, un réglage fait à la main sur l'appareil est respecté.
   */
  async tickClimate() {
    let data;
    try {
      data = await this.store.getClimate?.(this.homeId);
    } catch {
      data = null;
    }
    if (!data || data.settings?.enabled === false) return;
    const now = this.clock();
    const local = localTime(now, this.timezone);
    const mode = seasonMode(this.modes);
    const presets = data.settings?.presets ?? DEFAULT_PRESETS;
    for (const zone of data.zones) {
      if (!zone.enabled) continue;
      const { preset, source } = effectivePreset(zone, data.settings, this.modes, now, local);
      const signature = `${preset}|${source}|${mode}|${JSON.stringify(presets[preset] ?? null)}|${(zone.devices ?? []).join()}`;
      if (this.climateApplied.get(zone.id) === signature) continue;
      let target = null;
      let pending = false;
      for (const deviceId of zone.devices ?? []) {
        const d = this.devices.get(deviceId);
        if (!d) continue;
        if (d.availability === 'unavailable') {
          pending = true; // réessayé à la prochaine minute
          continue;
        }
        const res = deviceCommands(d, presets, preset, mode);
        target ??= res.target;
        for (const [i, c] of res.commands.entries()) {
          try {
            await this.store.insertCommand({ home_id: this.homeId, device_id: deviceId, capability_key: c.capability_key, value: c.value, idempotency_key: `climate:${zone.id}:${local.key}:${deviceId}:${i}` });
          } catch (e) {
            pending = true;
            log.warn('climate.command_failed', { zone_id: zone.id, device_id: deviceId, error: e.message });
          }
        }
      }
      if (!pending) this.climateApplied.set(zone.id, signature);
      log.info('climate.applied', { zone_id: zone.id, preset, source, mode, target });
      if (zone.active_preset !== preset || zone.active_source !== source || Number(zone.active_target ?? NaN) !== target) {
        await this.store
          .updateClimateZone(zone.id, { active_preset: preset, active_source: source, active_target: target, active_since: now.toISOString() })
          .catch((e) => log.warn('climate.save_failed', { error: e.message }));
      }
    }
    await this.processQueue();
  }

  #ctx() {
    return { weather: this.weather, date: this.clock(), modes: this.modes ?? [] };
  }

  async tickTimeTriggers() {
    const now = localTime(this.clock(), this.timezone);
    for (const a of this.automations) {
      const due = timeTriggerDue(a.trigger, now) || sunTriggerDue(a.trigger, now, this.weather, this.timezone);
      if (!due || this.firedTimeKeys.get(a.id) === now.key) continue;
      this.firedTimeKeys.set(a.id, now.key);
      await this.runAutomation(a, now, `${a.trigger.type}:${now.key}`);
    }
  }

  // ------------------------------------------------------------------ Météo
  async refreshWeather() {
    const home = await this.store.getHome(this.homeId);
    const lat = home?.latitude == null ? null : Number(home.latitude);
    const lon = home?.longitude == null ? null : Number(home.longitude);
    if (!Number.isFinite(lat) || !Number.isFinite(lon)) return null; // position pas encore choisie dans l'app
    const w = await this.weatherFetcher({ latitude: lat, longitude: lon, apiKey: this.config.weatherApiKey ?? null });
    this.weather = w;
    try {
      await this.store.insertWeatherReading({
        home_id: this.homeId,
        observed_at: (w.observed_at ?? this.clock()).toISOString(),
        wind_speed: w.wind_speed,
        wind_gust: w.wind_gust,
        precipitation: w.precipitation,
        temperature: w.temperature,
        is_day: w.is_day,
        sunrise: w.sunrise?.toISOString() ?? null,
        sunset: w.sunset?.toISOString() ?? null,
        source: w.source ?? 'open-meteo',
      });
    } catch (e) {
      log.warn('weather.store_failed', { error: e.message }); // base pas encore à jour
    }
    await this.evaluateWeatherTriggers();
    return w;
  }

  /** Seuil dépassé pendant `for_minutes` (délai de confirmation) → une exécution, réarmée quand ça retombe. */
  async evaluateWeatherTriggers() {
    const nowMs = this.clock().getTime();
    const now = localTime(this.clock(), this.timezone);
    for (const a of this.automations) {
      if (a.trigger?.type !== 'weather') continue;
      if (!weatherTriggerHolds(a.trigger, this.weather)) {
        this.weatherSince.delete(a.id);
        this.weatherFired.delete(a.id);
        continue;
      }
      if (this.weatherFired.has(a.id)) continue;
      const waitMs = Math.max(0, Number(a.trigger.for_minutes) || 0) * 60_000;
      if (!this.weatherSince.has(a.id)) {
        this.weatherSince.set(a.id, nowMs);
        if (waitMs > 0) {
          // Nouvelle lecture à la fin du délai pour confirmer.
          clearTimeout(this.weatherConfirm);
          this.weatherConfirm = setTimeout(
            () => this.refreshWeather().catch((e) => log.warn('weather.failed', { error: e.message })),
            waitMs + 1_000,
          );
          continue;
        }
      }
      if (nowMs - this.weatherSince.get(a.id) < waitMs) continue;
      this.weatherFired.add(a.id);
      await this.runAutomation(a, now, `weather:${a.trigger.metric}:${nowMs}`);
    }
  }

  async evaluateStateTriggers(deviceId, before, after) {
    const now = localTime(this.clock(), this.timezone);
    for (const a of this.automations) {
      if (stateTriggerFired(a.trigger, deviceId, before, after)) {
        await this.runAutomation(a, now, `state:${deviceId}:${this.clock().getTime()}`);
      }
    }
  }

  async #issue(a, actions, keyPrefix) {
    let issued = 0;
    for (const [i, act] of (actions ?? []).entries()) {
      try {
        if (act.scene_id) {
          await this.store.executeScene(act.scene_id, a.id);
        } else {
          await this.store.insertCommand({
            home_id: this.homeId,
            device_id: act.device_id,
            capability_key: act.capability_key,
            value: act.value,
            idempotency_key: `${keyPrefix}:${i}`,
            automation_id: a.id,
          });
        }
        issued++;
      } catch (e) {
        log.error('automation.action_failed', { automation_id: a.id, error: e.message });
      }
    }
    return issued;
  }

  async #recordRun(a, phase, status, reason, details = {}) {
    try {
      await this.store.insertAutomationRun({ home_id: this.homeId, automation_id: a.id, name: a.name ?? '', phase, status, reason: String(reason).slice(0, 200), details });
    } catch (e) {
      log.warn('automation.history_failed', { error: e.message }); // base pas encore à jour
    }
  }

  async #notify(type, body, data, ref) {
    try {
      await this.store.notifyHome(this.homeId, type, body, data, ref);
    } catch (e) {
      log.warn('notify.failed', { type, error: e.message });
    }
  }

  async runAutomation(a, now, reason) {
    // Anti-boucle : une exécution au plus toutes les 10 s par automatisation…
    const nowMs = this.clock().getTime();
    const last = this.lastAutomationRun.get(a.id) ?? 0;
    if (nowMs - last < 10_000) {
      log.warn('automation.throttled', { automation_id: a.id });
      return;
    }
    // … et 30 par heure au plus (deux règles qui se relancent l'une l'autre).
    const recent = (this.recentRuns.get(a.id) ?? []).filter((t) => nowMs - t < 3_600_000);
    if (recent.length >= 30) {
      log.warn('automation.loop_blocked', { automation_id: a.id });
      if (recent.length === 30) await this.#recordRun(a, 'main', 'skipped', 'Boucle détectée : 30 exécutions en une heure');
      recent.push(nowMs);
      this.recentRuns.set(a.id, recent);
      return;
    }
    const states = await this.store.listDeviceStates(this.homeId);
    const ctx = this.#ctx();
    if (!conditionsHold(a.conditions, states, now, ctx)) {
      log.debug('automation.conditions_false', { automation_id: a.id });
      return;
    }
    if (exceptionHolds(a.exceptions, states, now, ctx)) {
      log.info('automation.exception', { automation_id: a.id });
      await this.#recordRun(a, 'main', 'skipped', 'SAUF SI vérifié', { trigger: reason });
      return;
    }
    this.lastAutomationRun.set(a.id, nowMs);
    recent.push(nowMs);
    this.recentRuns.set(a.id, recent);
    const actions = a.actions ?? [];
    const issued = await this.#issue(a, actions, `auto:${a.id}:${reason}`);
    await this.store.markAutomationRun(a.id, this.clock().toISOString());
    await this.store.logEvent({ home_id: this.homeId, event_type: 'automation_run', result: issued ? 'success' : 'failed', details: { automation_id: a.id, name: a.name, actions: issued } });
    const status = issued === actions.length ? 'success' : issued ? 'partial' : 'failed';
    const weather = a.trigger?.type === 'weather' && this.weather
      ? { wind_speed: this.weather.wind_speed, wind_gust: this.weather.wind_gust, temperature: this.weather.temperature, precipitation: this.weather.precipitation }
      : undefined;
    await this.#recordRun(a, 'main', status, reason, { actions: issued, total: actions.length, ...(weather ? { weather } : {}) });
    if (a.trigger?.type === 'weather' && ['wind_speed', 'wind_gust'].includes(a.trigger.metric) && weather) {
      const wind = Math.round(weather.wind_speed ?? 0);
      const gust = weather.wind_gust == null ? null : Math.round(weather.wind_gust);
      await this.#notify('high_wind', `Vent ${wind} km/h${gust == null ? '' : ` · rafales ${gust} km/h`}`, { wind, ...(gust == null ? {} : { gust }) }, a.id);
    }
    const covers = closedCovers(actions);
    if (covers && issued) await this.#notify('shutters_auto_closed', `${covers} volet(s) fermé(s) : ${a.name ?? ''}`, { count: covers, automation: a.name ?? '' }, a.id);
    log.info('automation.run', { automation_id: a.id, reason, actions: issued });
    this.#scheduleFollowUp(a);
    await this.processQueue();
  }

  // ------------------------------------------------------------------ « PUIS » (actions différées)
  #scheduleFollowUp(a) {
    const f = a.follow_up;
    if (!f || !Array.isArray(f.actions) || !f.actions.length) return;
    const existing = this.followUps.get(a.id);
    if (existing) {
      if (f.restart_on_trigger === false) return; // garde le premier délai
      clearTimeout(existing.timer);
    }
    const delayMs = Math.max(0, Number(f.after_minutes) || 0) * 60_000;
    const deadline = this.clock().getTime() + delayMs + 24 * 3_600_000;
    const entry = { deadline, timer: null };
    entry.timer = setTimeout(() => this.runFollowUp(a.id).catch((e) => log.error('automation.follow_up_failed', { error: e.message })), delayMs);
    this.followUps.set(a.id, entry);
  }

  /** Exécute le « PUIS » si ses conditions sont vraies ; sinon réessaie chaque minute (24 h au plus). */
  async runFollowUp(automationId) {
    const entry = this.followUps.get(automationId);
    const a = this.automations.find((x) => x.id === automationId);
    if (!entry || !a?.follow_up || this.stopped) {
      this.followUps.delete(automationId);
      return;
    }
    const now = localTime(this.clock(), this.timezone);
    const states = await this.store.listDeviceStates(this.homeId);
    if (!conditionsHold(a.follow_up.conditions, states, now, this.#ctx())) {
      if (this.clock().getTime() >= entry.deadline) {
        this.followUps.delete(automationId);
        await this.#recordRun(a, 'follow_up', 'skipped', 'Conditions du PUIS jamais réunies en 24 h');
        return;
      }
      entry.timer = setTimeout(() => this.runFollowUp(automationId).catch((e) => log.error('automation.follow_up_failed', { error: e.message })), this.config.followUpRetryMs ?? 60_000);
      return;
    }
    this.followUps.delete(automationId);
    const actions = a.follow_up.actions;
    const issued = await this.#issue(a, actions, `follow:${a.id}:${this.clock().getTime()}`);
    await this.#recordRun(a, 'follow_up', issued === actions.length ? 'success' : issued ? 'partial' : 'failed', 'PUIS', { actions: issued, total: actions.length });
    log.info('automation.follow_up', { automation_id: a.id, actions: issued });
    await this.processQueue();
  }
}
