// Accès Supabase de la passerelle (clé service_role : à garder sur la machine de la passerelle,
// jamais dans l'application). Chaque requête est bornée à la maison de l'intégration.

import { createClient } from '@supabase/supabase-js';

function check({ data, error }) {
  if (error) throw new Error(`Supabase : ${error.message}`);
  return data;
}

export class SupabaseStore {
  constructor(url, serviceKey, { fetch } = {}) {
    this.db = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      ...(fetch ? { global: { fetch } } : {}),
    });
  }

  async getIntegration(id) {
    return check(await this.db.from('integrations').select('id, home_id, provider, status').eq('id', id).maybeSingle());
  }

  async getHome(id) {
    return check(await this.db.from('homes').select('id, timezone').eq('id', id).maybeSingle());
  }

  async setIntegrationStatus(id, status, lastError, lastSyncAt) {
    const patch = { status, last_error: lastError };
    if (lastSyncAt) patch.last_sync_at = lastSyncAt;
    check(await this.db.from('integrations').update(patch).eq('id', id).neq('status', 'disabled'));
  }

  async listBindings(integrationId) {
    return check(await this.db.from('device_bindings').select('device_id, external_id').eq('integration_id', integrationId));
  }

  async createDevice(row, externalId, capabilities) {
    const device = check(await this.db.from('devices').insert(row).select('id').single());
    check(await this.db.from('device_bindings').insert({ device_id: device.id, integration_id: row.integration_id, external_id: externalId }));
    if (capabilities.length) {
      check(await this.db.from('device_capabilities').insert(capabilities.map((c) => ({ ...c, device_id: device.id }))));
    }
    return device.id;
  }

  async updateDevice(id, patch) {
    check(await this.db.from('devices').update(patch).eq('id', id));
  }

  async replaceCapabilities(deviceId, capabilities) {
    if (capabilities.length) {
      check(
        await this.db
          .from('device_capabilities')
          .upsert(capabilities.map((c) => ({ ...c, device_id: deviceId })), { onConflict: 'device_id,capability_key' }),
      );
    }
    const keep = capabilities.map((c) => `"${c.capability_key}"`).join(',');
    let q = this.db.from('device_capabilities').delete().eq('device_id', deviceId);
    if (keep) q = q.not('capability_key', 'in', `(${keep})`);
    check(await q);
  }

  async fetchDueCommands(homeId, deviceIds, nowIso) {
    return check(
      await this.db
        .from('device_commands')
        .select('id, home_id, device_id, capability_key, value, scene_run_id, not_before, created_at')
        .eq('home_id', homeId)
        .eq('status', 'pending')
        .lte('not_before', nowIso)
        .in('device_id', deviceIds)
        .order('not_before')
        .order('created_at')
        .limit(50),
    );
  }

  /** Passage atomique pending → sent : une seule passerelle exécute une commande donnée. */
  async claimCommand(id) {
    const rows = check(await this.db.from('device_commands').update({ status: 'sent' }).eq('id', id).eq('status', 'pending').select('id'));
    return rows.length === 1;
  }

  async completeCommand(id, status, error) {
    check(await this.db.from('device_commands').update({ status, error, completed_at: new Date().toISOString() }).eq('id', id).eq('status', 'sent'));
  }

  async failInflight(deviceIds, error) {
    if (!deviceIds.length) return;
    check(
      await this.db
        .from('device_commands')
        .update({ status: 'failed', error, completed_at: new Date().toISOString() })
        .eq('status', 'sent')
        .in('device_id', deviceIds),
    );
  }

  async expireCommands(homeId, deviceIds, olderThanIso, error) {
    if (!deviceIds.length) return 0;
    const rows = check(
      await this.db
        .from('device_commands')
        .update({ status: 'timeout', error, completed_at: new Date().toISOString() })
        .eq('home_id', homeId)
        .eq('status', 'pending')
        .lt('not_before', olderThanIso)
        .in('device_id', deviceIds)
        .select('id'),
    );
    return rows.length;
  }

  subscribeCommands(homeId, onInsert) {
    const channel = this.db
      .channel(`bridge:${homeId}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'device_commands', filter: `home_id=eq.${homeId}` }, () => onInsert())
      .subscribe();
    return () => this.db.removeChannel(channel);
  }

  async listAutomations(homeId) {
    return check(await this.db.from('automations').select('*').eq('home_id', homeId).eq('enabled', true).eq('run_locally', true));
  }

  async listDeviceStates(homeId) {
    const rows = check(await this.db.from('devices').select('id, state').eq('home_id', homeId));
    return Object.fromEntries(rows.map((r) => [r.id, r.state]));
  }

  async insertCommand(row) {
    check(await this.db.from('device_commands').insert(row));
  }

  async executeScene(sceneId, automationId) {
    return check(await this.db.rpc('execute_scene', { p_scene_id: sceneId, p_automation_id: automationId }));
  }

  async markAutomationRun(id, atIso) {
    check(await this.db.from('automations').update({ last_run_at: atIso }).eq('id', id));
  }

  async logEvent(row) {
    check(await this.db.from('event_logs').insert(row));
  }
}
