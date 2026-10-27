// Module complémentaire Home Assistant : le Supervisor écrit les options saisies par
// l'utilisateur dans /data/options.json et fournit SUPERVISOR_TOKEN. On les traduit en
// variables d'environnement pour réutiliser loadConfig() tel quel.

import { existsSync, readFileSync } from 'node:fs';

export const ADDON_OPTIONS_FILE = '/data/options.json';
export const DEFAULT_SUPABASE_URL = 'https://qhzlmzfdbajulnymrwvg.supabase.co';

/** Variables d'environnement déduites des options du module (ne modifie rien). */
export function envFromAddonOptions(options, supervisorToken) {
  const env = {
    SUPABASE_URL: (options.supabase_url || DEFAULT_SUPABASE_URL).trim(),
    SUPABASE_SERVICE_ROLE_KEY: (options.service_role_key ?? '').trim(),
    INTEGRATION_ID: (options.integration_id ?? '').trim(),
    ADAPTER: options.simulator ? 'simulator' : 'home_assistant',
    RUN_AUTOMATIONS: options.run_automations === false ? 'false' : 'true',
    LOG_LEVEL: options.log_level || 'info',
  };
  if (!options.simulator) {
    // API de Home Assistant via le Supervisor : aucun jeton longue durée à créer.
    env.HA_WS_URL = 'ws://supervisor/core/websocket';
    env.HA_TOKEN = supervisorToken ?? '';
  }
  if (options.entity_filter) env.HA_ENTITY_FILTER = options.entity_filter;
  return env;
}

/** Applique les options du module si le fichier existe ; sans effet hors Home Assistant. */
export function applyAddonOptions(env = process.env, file = ADDON_OPTIONS_FILE) {
  if (!existsSync(file)) return false;
  const options = JSON.parse(readFileSync(file, 'utf8'));
  Object.assign(env, envFromAddonOptions(options, env.SUPERVISOR_TOKEN));
  return true;
}
