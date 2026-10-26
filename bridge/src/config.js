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
  if (!['home_assistant', 'simulator'].includes(adapter)) {
    throw new Error(`ADAPTER inconnu : ${adapter} (home_assistant | simulator)`);
  }
  return {
    supabaseUrl: required(env, 'SUPABASE_URL'),
    supabaseServiceKey: required(env, 'SUPABASE_SERVICE_ROLE_KEY'),
    integrationId: required(env, 'INTEGRATION_ID'),
    adapter,
    haUrl: adapter === 'home_assistant' ? required(env, 'HA_URL').replace(/\/$/, '') : null,
    haToken: adapter === 'home_assistant' ? required(env, 'HA_TOKEN') : null,
    // Filtre facultatif : n'importer que les entités dont l'id correspond (ex. ^(light|switch|cover)\.)
    haEntityFilter: env.HA_ENTITY_FILTER ? new RegExp(env.HA_ENTITY_FILTER) : null,
    commandTimeoutMs: int(env, 'COMMAND_TIMEOUT_MS', 10_000),
    pendingMaxAgeMs: int(env, 'PENDING_MAX_AGE_MS', 30_000),
    pollIntervalMs: int(env, 'POLL_INTERVAL_MS', 2_000),
    automationRefreshMs: int(env, 'AUTOMATION_REFRESH_MS', 30_000),
    logLevel: env.LOG_LEVEL ?? 'info',
  };
}
