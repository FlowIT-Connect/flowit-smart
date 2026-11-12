// Module complémentaire Home Assistant : le Supervisor écrit les options saisies par
// l'utilisateur dans /data/options.json et fournit SUPERVISOR_TOKEN. On les traduit en
// variables d'environnement pour réutiliser loadConfig() tel quel.
//
// Deux façons d'utiliser le module :
//  - mode « home_assistant » : les appareils de CE Home Assistant vont dans Solea ;
//  - mode « tuya_cloud » : la passerelle Solea complète (Smart Life, TTLock, robot yeedi)
//    tourne sur la box à la place du PC, et peut publier ses appareils dans Home Assistant
//    par MQTT (option ha_mqtt, identifiants fournis par le Supervisor) ;
//  - mode « video » (module « Solea Boîtier vidéo ») : caméras et visiophones du logement,
//    avec le relais MediaMTX lancé à côté par run_video.sh, pour pouvoir éteindre le PC.

import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';

import { log } from './log.js';

export const ADDON_OPTIONS_FILE = '/data/options.json';
export const DEFAULT_SUPABASE_URL = 'https://qhzlmzfdbajulnymrwvg.supabase.co';
/** Module « Solea Yeedi » (GPL) copié à part dans l'image du module complémentaire. */
export const YEEDI_ENTRY = '/yeedi/src/index.js';
/** Dossier de configuration de HA dans le module (map homeassistant_config, lecture seule). */
export const HA_CONFIG_DIR = '/homeassistant';
/** Télécommandes de clim de la bibliothèque, gardées par le module (dossier persistant). */
export const IR_DATA_DIR = '/data/broadlink';
/** Intégrations de HA reprises par défaut en mode tuya_cloud : télécommandes Broadlink. */
export const DEFAULT_HA_INTEGRATIONS = 'broadlink';
const YEEDI_PORT = 8790;

const text = (v) => (v == null ? '' : String(v).trim());

/** Mode du module : ancien réglage « simulator » encore accepté. */
export function addonMode(options) {
  if (options.simulator) return 'simulator';
  return ['tuya_cloud', 'simulator', 'video'].includes(options.mode) ? options.mode : 'home_assistant';
}

/** Variables d'environnement déduites des options du module (ne modifie rien). */
export function envFromAddonOptions(options, supervisorToken) {
  const mode = addonMode(options);
  const env = {
    SUPABASE_URL: (options.supabase_url || DEFAULT_SUPABASE_URL).trim(),
    SUPABASE_SERVICE_ROLE_KEY: text(options.service_role_key),
    INTEGRATION_ID: text(options.integration_id),
    ADAPTER: mode,
    RUN_AUTOMATIONS: options.run_automations === false ? 'false' : 'true',
    LOG_LEVEL: options.log_level || 'info',
  };
  if (mode === 'home_assistant') {
    // API de Home Assistant via le Supervisor : aucun jeton longue durée à créer.
    env.HA_WS_URL = 'ws://supervisor/core/websocket';
    env.HA_TOKEN = supervisorToken ?? '';
    if (options.entity_filter) env.HA_ENTITY_FILTER = options.entity_filter;
    env.HA_CONFIG_DIR = HA_CONFIG_DIR;
    env.IR_DATA_DIR = IR_DATA_DIR;
  }
  if (mode === 'tuya_cloud') {
    env.TUYA_ACCESS_ID = text(options.tuya_access_id);
    env.TUYA_ACCESS_SECRET = text(options.tuya_access_secret);
    env.TUYA_REGION = text(options.tuya_region) || 'eu';
    // Appareils de HA ajoutés à la passerelle (Broadlink par défaut ; "" pour aucun).
    const integrations = options.ha_integrations == null ? DEFAULT_HA_INTEGRATIONS : text(options.ha_integrations);
    if (integrations && supervisorToken) {
      env.HA_IMPORT_PLATFORMS = integrations;
      env.HA_WS_URL = 'ws://supervisor/core/websocket';
      env.HA_TOKEN = supervisorToken ?? '';
      env.HA_CONFIG_DIR = HA_CONFIG_DIR;
      env.IR_DATA_DIR = IR_DATA_DIR;
    }
  }
  if (mode === 'video') {
    env.MEDIAMTX = 'true';
    // Relais figé : le boîtier s'arrête, run_video.sh relance le relais puis le boîtier.
    env.RELAY_RESTART_EXIT = '1';
    if (text(options.video_subnets)) env.VIDEO_SUBNETS = text(options.video_subnets);
  }
  if (text(options.ttlock_client_id)) {
    env.TTLOCK_CLIENT_ID = text(options.ttlock_client_id);
    env.TTLOCK_CLIENT_SECRET = text(options.ttlock_client_secret);
    env.TTLOCK_USERNAME = text(options.ttlock_username);
    env.TTLOCK_PASSWORD_MD5 = text(options.ttlock_password_md5);
  }
  return env;
}

/** Réglages du module yeedi lancé à côté de la passerelle (null : pas de robot). */
export function yeediFromAddonOptions(options) {
  if (!text(options.yeedi_email)) return null;
  return {
    YEEDI_EMAIL: text(options.yeedi_email),
    YEEDI_PASSWORD_MD5: text(options.yeedi_password_md5).toLowerCase(),
    YEEDI_COUNTRY: text(options.yeedi_country) || 'DZ',
    ...(text(options.yeedi_domain) ? { YEEDI_DOMAIN: text(options.yeedi_domain) } : {}),
    YEEDI_HOST: '127.0.0.1',
    YEEDI_PORT: String(YEEDI_PORT),
  };
}

/** Lit les options du module (null hors Home Assistant). */
export function readAddonOptions(file = ADDON_OPTIONS_FILE) {
  return existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : null;
}

/** Applique les options du module si le fichier existe ; sans effet hors Home Assistant. */
export function applyAddonOptions(env = process.env, file = ADDON_OPTIONS_FILE) {
  const options = readAddonOptions(file);
  if (!options) return false;
  Object.assign(env, envFromAddonOptions(options, env.SUPERVISOR_TOKEN));
  return true;
}

/**
 * Broker MQTT de Home Assistant (module Mosquitto) donné par le Supervisor : aucun
 * utilisateur ni mot de passe à créer. Renseigne HA_MQTT_URL si l'option ha_mqtt est active.
 */
export async function applyAddonMqtt(options, env = process.env, fetchImpl = fetch) {
  if (!options?.ha_mqtt || env.HA_MQTT_URL || addonMode(options) === 'home_assistant') return false;
  try {
    const res = await fetchImpl('http://supervisor/services/mqtt', { headers: { authorization: `Bearer ${env.SUPERVISOR_TOKEN ?? ''}` } });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const { data } = await res.json();
    const auth = data.username ? `${encodeURIComponent(data.username)}:${encodeURIComponent(data.password ?? '')}@` : '';
    env.HA_MQTT_URL = `mqtt://${auth}${data.host}:${data.port || 1883}`;
    return true;
  } catch (e) {
    log.warn('addon.mqtt_unavailable', { error: e.message, hint: 'Installez et démarrez le module « Mosquitto broker »' });
    return false;
  }
}

/**
 * Lance le module yeedi (programme séparé, licence GPL) dans le même conteneur et relie la
 * passerelle à son API locale. Relancé s'il s'arrête.
 */
export function startAddonYeedi(options, env = process.env, { spawnImpl = spawn, entry = YEEDI_ENTRY } = {}) {
  const yeedi = yeediFromAddonOptions(options ?? {});
  if (!yeedi || !existsSync(entry)) return null;
  const token = randomBytes(24).toString('hex');
  env.YEEDI_URL = `http://127.0.0.1:${YEEDI_PORT}`;
  env.YEEDI_TOKEN = token;
  let child = null;
  let stopped = false;
  const run = () => {
    child = spawnImpl(process.execPath, [entry], { env: { PATH: process.env.PATH, HOME: process.env.HOME ?? '/tmp', ...yeedi, YEEDI_TOKEN: token }, stdio: 'inherit' });
    child.on('exit', (code) => {
      if (stopped) return;
      log.warn('addon.yeedi_exited', { code, retry_seconds: 30 });
      setTimeout(run, 30_000);
    });
  };
  run();
  log.info('addon.yeedi_started', { module: env.YEEDI_URL });
  return { stop: () => { stopped = true; child?.kill(); } };
}
