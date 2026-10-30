// Validation d'une valeur de commande selon la capacité déclarée (liste blanche, §7).

/**
 * @param {{capability_key:string,type:string,writable:boolean,metadata:object}} cap
 * @param {unknown} value
 * @returns {string|null} message d'erreur, ou null si la valeur est acceptable
 */
export function validateValue(cap, value) {
  if (!cap) return 'Capacité non prise en charge par cet appareil';
  if (!cap.writable || cap.type === 'sensor') return 'Capacité en lecture seule';
  const meta = cap.metadata ?? {};
  switch (cap.type) {
    case 'boolean':
      return typeof value === 'boolean' ? null : 'Valeur booléenne attendue';
    case 'number': {
      if (typeof value !== 'number' || !Number.isFinite(value)) return 'Valeur numérique attendue';
      if (meta.min != null && value < meta.min) return `Valeur inférieure au minimum (${meta.min})`;
      if (meta.max != null && value > meta.max) return `Valeur supérieure au maximum (${meta.max})`;
      return null;
    }
    case 'enum':
      return Array.isArray(meta.options) && meta.options.includes(value) ? null : 'Option non prise en charge';
    case 'color':
      return typeof value === 'string' && /^#[0-9a-fA-F]{6}$/.test(value) ? null : 'Couleur #RRGGBB attendue';
    case 'string':
      if (meta.kind === 'access_code') return validateAccessCode(value, meta.options ?? []);
      if (meta.kind === 'ekey') return validateKey(value, meta.options ?? []);
      return 'Type de capacité non pilotable';
    default:
      return 'Type de capacité non pilotable';
  }
}

const MAX_PERIOD_MS = 366 * 24 * 3600_000;

/** Dates facultatives d'un accès programmé : les deux ou aucune. */
function validatePeriod(value, required) {
  if (value.start == null && value.end == null && !required) return null;
  const start = typeof value.start === 'string' ? Date.parse(value.start) : NaN;
  const end = typeof value.end === 'string' ? Date.parse(value.end) : NaN;
  if (!Number.isFinite(start) || !Number.isFinite(end)) return 'Dates de début et de fin attendues';
  if (end <= start) return 'La fin doit être après le début';
  if (end < Date.now()) return 'Cette période est déjà passée';
  return null;
}

/** Clé électronique : {action, key_id?, receiver?, name?, start?, end?}. */
function validateKey(value, options) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return 'Demande d\'accès invalide';
  if (Object.keys(value).some((k) => !['action', 'key_id', 'receiver', 'name', 'start', 'end'].includes(k))) return 'Demande d\'accès invalide';
  if (!options.includes(value.action)) return 'Action non prise en charge';
  if (value.name != null && (typeof value.name !== 'string' || value.name.length > 40)) return 'Nom trop long (40 caractères au plus)';
  if (value.action === 'send') {
    if (typeof value.receiver !== 'string' || !/^[^\s]{3,80}$/.test(value.receiver.trim())) return 'Compte TTLock du destinataire attendu (téléphone ou e-mail)';
    return validatePeriod(value, false);
  }
  if (!Number.isInteger(value.key_id) || value.key_id <= 0) return 'Clé électronique introuvable';
  return value.action === 'change_period' ? validatePeriod(value, false) : null;
}

/** Demande de code d'accès : {type, name?, start?, end?} (dates ISO pour une période). */
function validateAccessCode(value, options) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return 'Demande de code invalide';
  const extra = Object.keys(value).filter((k) => !['type', 'name', 'start', 'end'].includes(k));
  if (extra.length) return 'Demande de code invalide';
  if (!options.includes(value.type)) return 'Type de code non pris en charge';
  if (value.name != null && (typeof value.name !== 'string' || value.name.length > 40)) return 'Nom du code trop long (40 caractères au plus)';
  if (value.type !== 'period') return null;
  const start = typeof value.start === 'string' ? Date.parse(value.start) : NaN;
  const end = typeof value.end === 'string' ? Date.parse(value.end) : NaN;
  if (!Number.isFinite(start) || !Number.isFinite(end)) return 'Dates de début et de fin attendues';
  if (end <= start) return 'La fin doit être après le début';
  if (end < Date.now()) return 'Cette période est déjà passée';
  if (end - start > MAX_PERIOD_MS) return 'Période d\'un an au plus';
  return null;
}
