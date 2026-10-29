// Store en mémoire reproduisant le comportement de SupabaseStore pour les tests.
import { randomUUID } from 'node:crypto';

export class MemoryStore {
  constructor({ homeId = 'home-1', integrationId = 'integ-1', timezone = 'Africa/Algiers' } = {}) {
    this.integrations = new Map([[integrationId, { id: integrationId, home_id: homeId, provider: 'home_assistant', status: 'pending' }]]);
    this.homes = new Map([[homeId, { id: homeId, timezone }]]);
    this.devices = new Map();
    this.bindings = [];
    this.capabilities = [];
    this.commands = [];
    this.automations = [];
    this.events = [];
    this.scenesExecuted = [];
    this.listeners = [];
    this.cameraWatchers = [];
    this.frames = new Map(); // chemin -> { bytes, contentType }
    this.frameNotices = [];
  }

  async getIntegration(id) { return this.integrations.get(id) ?? null; }
  async getHome(id) { return this.homes.get(id) ?? null; }
  async setIntegrationStatus(id, status, lastError, lastSyncAt) {
    const i = this.integrations.get(id);
    if (i.status === 'disabled') return;
    Object.assign(i, { status, last_error: lastError }, lastSyncAt ? { last_sync_at: lastSyncAt } : {});
  }
  async listBindings(integrationId) { return this.bindings.filter((b) => b.integration_id === integrationId); }
  async createDevice(row, externalId, caps) {
    const id = randomUUID();
    this.devices.set(id, { id, is_sensitive: false, ...row });
    this.bindings.push({ device_id: id, integration_id: row.integration_id, external_id: externalId });
    await this.replaceCapabilities(id, caps);
    return id;
  }
  async updateDevice(id, patch) { Object.assign(this.devices.get(id), patch); }
  async replaceCapabilities(deviceId, caps) {
    this.capabilities = this.capabilities.filter((c) => c.device_id !== deviceId).concat(caps.map((c) => ({ ...c, device_id: deviceId })));
  }
  async fetchDueCommands(homeId, deviceIds, nowIso) {
    return this.commands
      .filter((c) => c.home_id === homeId && c.status === 'pending' && c.not_before <= nowIso && deviceIds.includes(c.device_id))
      .sort((a, b) => a.not_before.localeCompare(b.not_before) || a.seq - b.seq);
  }
  async claimCommand(id) {
    const c = this.commands.find((x) => x.id === id);
    if (c?.status !== 'pending') return false;
    c.status = 'sent';
    return true;
  }
  async completeCommand(id, status, error) {
    const c = this.commands.find((x) => x.id === id);
    if (c.status === 'sent') Object.assign(c, { status, error, completed_at: new Date().toISOString() });
  }
  async failInflight(deviceIds, error) {
    for (const c of this.commands) if (c.status === 'sent' && deviceIds.includes(c.device_id)) Object.assign(c, { status: 'failed', error });
  }
  async expireCommands(homeId, deviceIds, olderThanIso, error) {
    let n = 0;
    for (const c of this.commands) {
      if (c.home_id === homeId && c.status === 'pending' && c.not_before < olderThanIso && deviceIds.includes(c.device_id)) {
        Object.assign(c, { status: 'timeout', error });
        n++;
      }
    }
    return n;
  }
  subscribeCommands(_homeId, cb) {
    this.listeners.push(cb);
    return () => {};
  }
  async listAutomations(homeId) { return this.automations.filter((a) => a.home_id === homeId && a.enabled && a.run_locally !== false); }
  async listDeviceStates() { return Object.fromEntries([...this.devices.values()].map((d) => [d.id, d.state])); }
  async insertCommand(row) {
    if (this.commands.some((c) => c.idempotency_key === row.idempotency_key && c.requested_by === row.requested_by && row.requested_by)) {
      throw new Error('duplicate');
    }
    const now = new Date().toISOString();
    const cmd = { id: randomUUID(), status: 'pending', not_before: now, created_at: now, seq: this.commands.length, scene_run_id: null, ...row };
    this.commands.push(cmd);
    for (const l of this.listeners) l();
    return cmd;
  }
  async executeScene(sceneId, automationId) { this.scenesExecuted.push({ sceneId, automationId }); return randomUUID(); }
  async markAutomationRun(id, at) { const a = this.automations.find((x) => x.id === id); if (a) a.last_run_at = at; }
  async logEvent(row) { this.events.push(row); }
  subscribeCameraWatch(_homeId, onWatch) {
    this.cameraWatchers.push(onWatch);
    return { notify: async (deviceId, at) => this.frameNotices.push({ deviceId, at }), unsubscribe: () => {} };
  }
  async uploadCameraFrame(homeId, deviceId, bytes, contentType) {
    const path = `${homeId}/${deviceId}.jpg`;
    this.frames.set(path, { bytes, contentType });
    return path;
  }
  watchCamera(deviceId) { for (const w of this.cameraWatchers) w(deviceId); }

  // Aides de test
  deviceByName(name) { return [...this.devices.values()].find((d) => d.name === name); }
  caps(deviceId) { return this.capabilities.filter((c) => c.device_id === deviceId); }
}
