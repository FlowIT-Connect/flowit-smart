import { parseCameras } from './adapters/direct_cameras.js';
import { TTLOCK_DEFAULT_URL } from './adapters/ttlock_api.js';
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
  if (!['home_assistant', 'simulator', 'tuya_cloud', 'video'].includes(adapter)) {
    throw new Error(`ADAPTER inconnu : ${adapter} (home_assistant | tuya_cloud | simulator | video)`);
  }
  const tuya = adapter === 'tuya_cloud';
  const platform = ['true', '1', 'oui'].includes((env.PLATFORM ?? '').trim().toLowerCase());
  if (platform && adapter === 'home_assistant') {
    throw new Error('PLATFORM=true fonctionne avec ADAPTER=tuya_cloud (ou simulator), pas avec Home Assistant');
  }
  // Caméras et visiophones (UDI) : boîtier installé sur place, jamais la passerelle de la plateforme
  // (le serveur distant ne voit pas le réseau local des logements).
  const video = adapter === 'video' || ['true', '1', 'oui'].includes((env.VIDEO ?? '').trim().toLowerCase());
  if (video && platform) throw new Error('VIDEO=true : à utiliser sur le boîtier du logement, pas avec PLATFORM=true');
  const list = (v) => String(v ?? '').split(/[,\s]+/).filter(Boolean);
  const tuyaRegion = tuya ? (env.TUYA_REGION || 'eu').trim() : null;
  if (tuya && !TUYA_REGIONS[tuyaRegion]) {
    throw new Error(`TUYA_REGION inconnue : ${tuyaRegion} (${Object.keys(TUYA_REGIONS).join(' | ')})`);
  }
  // Serrures TTLock (facultatif, avec n'importe quel ADAPTER) : actif dès que TTLOCK_CLIENT_ID est renseigné.
  const ttlock = env.TTLOCK_CLIENT_ID?.trim()
    ? {
        clientId: env.TTLOCK_CLIENT_ID.trim(),
        clientSecret: required(env, 'TTLOCK_CLIENT_SECRET').trim(),
        username: required(env, 'TTLOCK_USERNAME').trim(),
        passwordMd5: required(env, 'TTLOCK_PASSWORD_MD5').trim().toLowerCase(),
        baseUrl: env.TTLOCK_API_URL?.trim() || TTLOCK_DEFAULT_URL,
        pollMs: int(env, 'TTLOCK_POLL_SECONDS', 300) * 1000,
      }
    : null;
  if (ttlock && !/^[0-9a-f]{32}$/.test(ttlock.passwordMd5)) {
    throw new Error('TTLOCK_PASSWORD_MD5 doit être le MD5 du mot de passe TTLock (relancez « npm run configurer »)');
  }
  return {
    supabaseUrl: required(env, 'SUPABASE_URL'),
    supabaseServiceKey: required(env, 'SUPABASE_SERVICE_ROLE_KEY'),
    // Passerelle unique pour tous les logements (serveur de l'exploitant) : pas d'INTEGRATION_ID,
    // les appareils du compte installateur sont attribués aux logements depuis Solea.
    platform,
    integrationId: platform ? null : required(env, 'INTEGRATION_ID'),
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
    ttlock,
    video: video
      ? {
          mediamtxApiUrl: env.MEDIAMTX_API_URL?.trim() || 'http://127.0.0.1:9997',
          mediamtxWebrtcUrl: env.MEDIAMTX_WEBRTC_URL?.trim() || 'http://127.0.0.1:8889',
          relay: !['false', '0', 'non'].includes((env.MEDIAMTX ?? '').trim().toLowerCase()),
          discovery: !['false', '0', 'non'].includes((env.VIDEO_DISCOVERY ?? '').trim().toLowerCase()),
          subnets: env.VIDEO_SUBNETS ?? '',
          stun: env.VIDEO_STUN_URLS !== undefined ? list(env.VIDEO_STUN_URLS) : ['stun:stun.l.google.com:19302'],
          turn: list(env.VIDEO_TURN_URLS),
          turnSecret: env.VIDEO_TURN_SECRET?.trim() || null,
        }
      : null,
    cameraIntervalMs: int(env, 'CAMERA_INTERVAL_MS', 1000),
    tuyaPollMs: int(env, 'TUYA_POLL_SECONDS', 30) * 1000,
    commandTimeoutMs: int(env, 'COMMAND_TIMEOUT_MS', 10_000),
    pendingMaxAgeMs: int(env, 'PENDING_MAX_AGE_MS', 30_000),
    // Plateforme : une passerelle par logement, le temps réel déclenche déjà les commandes.
    pollIntervalMs: int(env, 'POLL_INTERVAL_MS', platform ? 10_000 : 2_000),
    platformRefreshMs: int(env, 'PLATFORM_REFRESH_SECONDS', 20) * 1000,
    automationRefreshMs: int(env, 'AUTOMATION_REFRESH_MS', 30_000),
    // Ajout d'appareils depuis l'application : durée de recherche d'un appareil Smart Life.
    pairingScanMs: int(env, 'PAIRING_SCAN_SECONDS', 300) * 1000,
    pairingRetryMs: int(env, 'PAIRING_RETRY_SECONDS', 10) * 1000,
    logLevel: env.LOG_LEVEL ?? 'info',
  };
}
