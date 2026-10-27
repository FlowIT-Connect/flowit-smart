// Cœur de la passerelle : synchronisation de l'inventaire, exécution des commandes
// (pending → sent → confirmed | failed | timeout | rejected) et automatisations locales.

import { conditionsHold, localTime, stateTriggerFired, timeTriggerDue } from './automations.js';
import { log } from './log.js';
import { validateValue } from './validate.js';

export class Bridge {
  /**
   * @param {{store:any, adapter:any, config:any, clock?:()=>Date}} deps
   */
  constructor({ store, adapter, config, clock = () => new Date() }) {
    this.store = store;
    this.adapter = adapter;
    this.config = config;
    this.clock = clock;
    this.homeId = null;
    this.timezone = 'Africa/Algiers';
    this.enabled = true;
    /** deviceId -> { externalId, caps: Map<key, cap>, isSensitive, state, availability } */
    this.devices = new Map();
    this.byExternal = new Map();
    this.automations = [];
    this.firedTimeKeys = new Map();
    this.lastAutomationRun = new Map();
    this.inflightDevices = new Set();
    this.inflightRuns = new Set();
    this.running = new Set();
    this.timers = [];
    this.queueBusy = false;
    this.queueAgain = false;
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
    if (this.config.runAutomations !== false) {
      await this.refreshAutomations();
      every(this.config.automationRefreshMs, () => this.refreshAutomations());
      every(10_000, () => this.tickTimeTriggers());
    }
    await this.processQueue();
  }

  async stop() {
    for (const t of this.timers) clearInterval(t);
    this.unsubscribe?.();
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
    for (const desc of this.adapter.devices()) {
      const snap = this.adapter.snapshot(desc.externalId);
      let deviceId = bindings.get(desc.externalId);
      const common = {
        vendor: desc.vendor,
        model: desc.model,
        protocol: desc.protocol,
        connection_source: desc.connectionSource,
        availability: snap.availability,
        state: snap.state,
        ...(snap.availability === 'available' ? { last_seen_at: now } : {}),
        ...(desc.isSensitive ? { is_sensitive: true } : {}), // jamais abaissé par la passerelle
      };
      if (deviceId) {
        await this.store.updateDevice(deviceId, common);
        await this.store.replaceCapabilities(deviceId, desc.capabilities);
      } else {
        deviceId = await this.store.createDevice(
          { home_id: this.homeId, integration_id: this.config.integrationId, name: desc.name, ...common },
          desc.externalId,
          desc.capabilities,
        );
        log.info('bridge.device_created', { device_id: deviceId, protocol: desc.protocol });
      }
      seen.add(desc.externalId);
      const prev = this.devices.get(deviceId);
      this.devices.set(deviceId, {
        externalId: desc.externalId,
        caps: new Map(desc.capabilities.map((c) => [c.capability_key, c])),
        isSensitive: desc.isSensitive || prev?.isSensitive || false,
        state: snap.state,
        availability: snap.availability,
      });
      this.byExternal.set(desc.externalId, deviceId);
    }
    for (const [externalId, deviceId] of bindings) {
      if (!seen.has(externalId)) await this.store.updateDevice(deviceId, { availability: 'unavailable' });
    }
    await this.store.setIntegrationStatus(this.config.integrationId, this.enabled ? 'connected' : 'disabled', null, now);
    log.info('bridge.inventory_synced', { devices: seen.size });
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
      else if (dev.isSensitive) result = { status: 'rejected', error: 'Commande bloquée : appareil sensible non validé' };
      else {
        const invalid = validateValue(cap, cmd.value);
        result = invalid
          ? { status: 'rejected', error: invalid }
          : await this.adapter.execute(dev.externalId, cmd.capability_key, cmd.value, this.config.commandTimeoutMs);
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

  async sweepStale() {
    const limit = new Date(this.clock().getTime() - this.config.pendingMaxAgeMs).toISOString();
    const n = await this.store.expireCommands(this.homeId, [...this.devices.keys()], limit, 'Aucune passerelle disponible pour exécuter la commande à temps');
    if (n) log.warn('bridge.commands_expired', { count: n });
  }

  // ------------------------------------------------------------------ Automatisations (exécution locale, §5.9)
  async refreshAutomations() {
    this.automations = await this.store.listAutomations(this.homeId);
    const integ = await this.store.getIntegration(this.config.integrationId);
    this.enabled = integ?.status !== 'disabled';
  }

  async tickTimeTriggers() {
    const now = localTime(this.clock(), this.timezone);
    for (const a of this.automations) {
      if (!timeTriggerDue(a.trigger, now) || this.firedTimeKeys.get(a.id) === now.key) continue;
      this.firedTimeKeys.set(a.id, now.key);
      await this.runAutomation(a, now, `time:${now.key}`);
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

  async runAutomation(a, now, reason) {
    // Anti-boucle : une exécution au plus toutes les 10 s par automatisation.
    const last = this.lastAutomationRun.get(a.id) ?? 0;
    if (this.clock().getTime() - last < 10_000) {
      log.warn('automation.throttled', { automation_id: a.id });
      return;
    }
    const states = await this.store.listDeviceStates(this.homeId);
    if (!conditionsHold(a.conditions, states, now)) {
      log.debug('automation.conditions_false', { automation_id: a.id });
      return;
    }
    this.lastAutomationRun.set(a.id, this.clock().getTime());
    let issued = 0;
    for (const [i, act] of (a.actions ?? []).entries()) {
      try {
        if (act.scene_id) {
          await this.store.executeScene(act.scene_id, a.id);
        } else {
          await this.store.insertCommand({
            home_id: this.homeId,
            device_id: act.device_id,
            capability_key: act.capability_key,
            value: act.value,
            idempotency_key: `auto:${a.id}:${reason}:${i}`,
            automation_id: a.id,
          });
        }
        issued++;
      } catch (e) {
        log.error('automation.action_failed', { automation_id: a.id, error: e.message });
      }
    }
    await this.store.markAutomationRun(a.id, this.clock().toISOString());
    await this.store.logEvent({ home_id: this.homeId, event_type: 'automation_run', result: issued ? 'success' : 'failed', details: { automation_id: a.id, name: a.name, actions: issued } });
    log.info('automation.run', { automation_id: a.id, reason, actions: issued });
    await this.processQueue();
  }
}
