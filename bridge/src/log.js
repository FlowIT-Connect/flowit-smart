// Journaux structurés JSON sur stdout (§10 Observabilité). Jamais de jeton ni de clé.
const LEVELS = { debug: 10, info: 20, warn: 30, error: 40 };
let threshold = LEVELS.info;

export function setLogLevel(level) {
  threshold = LEVELS[level] ?? LEVELS.info;
}

function emit(level, msg, fields) {
  if (LEVELS[level] < threshold) return;
  const line = JSON.stringify({ t: new Date().toISOString(), level, msg, ...fields });
  (level === 'error' || level === 'warn' ? console.error : console.log)(line);
}

export const log = {
  debug: (msg, fields = {}) => emit('debug', msg, fields),
  info: (msg, fields = {}) => emit('info', msg, fields),
  warn: (msg, fields = {}) => emit('warn', msg, fields),
  error: (msg, fields = {}) => emit('error', msg, fields),
};
