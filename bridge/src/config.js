import { parseCameras } from './adapters/direct_cameras.js';
import { TUYA_REGIONS } from './adapters/tuya_api.js';

// Configuration par variables d'environnement (fichier .env chargé par Docker Compose
// ou `node --env-file=.env src/index.js`). Aucun secret n'est écrit dans les journaux.

function required(env, name) {
  const v = env[name];
  if (!v) throw new Error(`Variable d'environnement manquante : ${name}`);
  return v;
}

function int(env, name, fallback) {
  const v = Number.parseInt(env[name] ?? '', 10);
  return Number.isFinite(v) && v > 0 ? v : fallback;
}

export function loadConfig(env = process.env) {
  const adapter = env.ADAPTER ?? 'home_assistant';
  if (!['home_assistant', 'simulator', 'tuya_cloud'].includes(adapter)) {
    throw new Error(`ADAPTER inconnu : ${adapter} (home_assistant | tuya_cloud | simulator)`);
  }
  const tuya = adapter === 'tuya_cloud';
  const tuyaRegion = tuya ? (env.TUYA_REGION || 'eu').trim() : null;
  if (tuya && !TUYA_REGIONS[tuyaRegion]) {
    throw new Error(`TUYA_REGION inconnue : ${tuyaRegion} (${Object.keys(TUYA_REGIONS).join(' | ')})`);
  }
  return {
    supabaseUrl: required(env, 'SUPABASE_URL'),
    supabaseServiceKey: required(env, 'SUPABASE_SERVICE_ROLE_KEY'),
    integrationId: required(env, 'INTEGRATION_ID'),
    adapter,
    // HA_WS_URL (adresse WebSocket complète) remplace HA_URL, par ex. dans le module complémentaire HA.
    haWsUrl: adapter === 'home_assistant' && env.HA_WS_URL ? env.HA_WS_URL : null,
    haUrl: adapter === 'home_assistant' && !env.HA_WS_URL ? required(env, 'HA_URL').replace(/\/$/, '') : null,
    haToken: adapter === 'home_assistant' ? required(env, 'HA_TOKEN') : null,
    // Filtre facultatif : n'importer que les entités dont l'id correspond (ex. ^(light|switch|cover)\.)
    haEntityFilter: env.HA_ENTITY_FILTER ? new RegExp(env.HA_ENTITY_FILTER) : null,
    // Tuya Cloud (sans box) : identifiants du projet cloud sur platform.tuya.com > Overview.
    tuyaAccessId: tuya ? required(env, 'TUYA_ACCESS_ID').trim() : null,
    tuyaAccessSecret: tuya ? required(env, 'TUYA_ACCESS_SECRET').trim() : null,
    tuyaBaseUrl: tuya ? TUYA_REGIONS[tuyaRegion].url : null,
    tuyaImageUrl: tuya ? TUYA_REGIONS[tuyaRegion].images : null,
    // Caméras IP lues directement par la passerelle : "Nom=http://…/snapshot.jpg;Nom2=…"
    cameras: parseCameras(env.CAMERAS),
    cameraIntervalMs: int(env, 'CAMERA_INTERVAL_MS', 1000),
    tuyaPollMs: int(env, 'TUYA_POLL_SECONDS', 30) * 1000,
    commandTimeoutMs: int(env, 'COMMAND_TIMEOUT_MS', 10_000),
    pendingMaxAgeMs: int(env, 'PENDING_MAX_AGE_MS', 30_000),
    pollIntervalMs: int(env, 'POLL_INTERVAL_MS', 2_000),
    automationRefreshMs: int(env, 'AUTOMATION_REFRESH_MS', 30_000),
    logLevel: env.LOG_LEVEL ?? 'info',
  };
}
