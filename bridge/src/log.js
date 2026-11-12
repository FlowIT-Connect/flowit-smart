// Journaux structurés JSON sur stdout (§10 Observabilité). Jamais de jeton ni de clé.
// LOG_FILE (facultatif) : copie dans un fichier, pour retrouver la cause d'un arrêt après coup
// (fenêtre Windows refermée). Le fichier est renommé en .1 au-delà de 5 Mo.
import { appendFileSync, renameSync, statSync } from 'node:fs';

const LOG_FILE = process.env.LOG_FILE || null;
const MAX_FILE = 5 * 1024 * 1024;
let written = 0;

function toFile(line) {
  if (!LOG_FILE) return;
  try {
    if (written === 0) written = statSync(LOG_FILE, { throwIfNoEntry: false })?.size ?? 0;
    if (written > MAX_FILE) {
      renameSync(LOG_FILE, `${LOG_FILE}.1`);
      written = 0;
    }
    appendFileSync(LOG_FILE, `${line}\n`);
    written += line.length + 1;
  } catch {
    // Disque plein ou fichier verrouillé : les journaux restent dans la fenêtre.
  }
}

const LEVELS = { debug: 10, info: 20, warn: 30, error: 40 };
let threshold = LEVELS.info;

export function setLogLevel(level) {
  threshold = LEVELS[level] ?? LEVELS.info;
}

function emit(level, msg, fields) {
  if (LEVELS[level] < threshold) return;
  const line = JSON.stringify({ t: new Date().toISOString(), level, msg, ...fields });
  (level === 'error' || level === 'warn' ? console.error : console.log)(line);
  toFile(line);
}

export const log = {
  debug: (msg, fields = {}) => emit('debug', msg, fields),
  info: (msg, fields = {}) => emit('info', msg, fields),
  warn: (msg, fields = {}) => emit('warn', msg, fields),
  error: (msg, fields = {}) => emit('error', msg, fields),
};
