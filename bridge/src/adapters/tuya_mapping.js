// Correspondance Tuya Cloud ↔ modèle FlowIT (fonctions pures, testées).
//
// Les capacités sont déduites des « codes » réellement déclarés par l'appareil dans sa
// spécification Tuya (switch_1, bright_value_v2, cur_power…), avec leurs plages et
// échelles : rien n'est supposé (§5.3, §5.6). Les codes inconnus sont ignorés.

import { hexToRgb, rgbToHex } from './ha_mapping.js';

/** Serrures, coffres, contrôle d'accès : exposés mais bloqués (is_sensitive, §9). */
const SENSITIVE_CATEGORIES = new Set(['ms', 'jtmspro', 'jtmsbh', 'mal', 'videolock', 'wf_ms', 'bxx', 'mk']);

const SWITCH_CODE = /^switch(?:_led)?(?:_(\d+))?$/;
const KELVIN_MIN = 2700;
const KELVIN_MAX = 6500;
/** Ordre d'affichage des boutons d'un rideau (le code Tuya `control` en déclare un sous-ensemble). */
const COVER_ACTIONS = ['open', 'stop', 'close'];

const SENSORS = [
  // [codes possibles, clé FlowIT, unité]
  [['va_temperature', 'temp_current'], 'temperature', '°C'],
  [['va_humidity', 'humidity_value'], 'humidity', '%'],
  [['battery_percentage', 'va_battery'], 'battery', '%'],
  [['cur_power'], 'power', 'W'],
  [['add_ele'], 'energy', 'kWh'],
];

function parseValues(v) {
  if (v && typeof v === 'object') return v;
  try {
    return JSON.parse(v || '{}');
  } catch {
    return {};
  }
}

function parseJson(v) {
  if (v && typeof v === 'object') return v;
  if (typeof v !== 'string') return null;
  try {
    return JSON.parse(v);
  } catch {
    return null;
  }
}

/** Spécification Tuya → Map code → { type, values, writable, readable }. */
export function parseSpecification(spec) {
  const codes = new Map();
  for (const f of spec?.status ?? []) codes.set(f.code, { type: f.type, values: parseValues(f.values), writable: false, readable: true });
  for (const f of spec?.functions ?? []) {
    const prev = codes.get(f.code);
    codes.set(f.code, { type: f.type, values: parseValues(f.values), writable: true, readable: prev?.readable ?? true });
  }
  return codes;
}

const scaleOf = (c) => 10 ** (Number(c?.values?.scale) || 0);
const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : typeof v === 'string' && v.trim() !== '' && Number.isFinite(Number(v)) ? Number(v) : null);
const round = (v, digits = 2) => Math.round(v * 10 ** digits) / 10 ** digits;

function scaled(code, c, unit) {
  const s = scaleOf(c);
  return {
    metadata: unit ? { unit } : {},
    read: (st) => {
      const v = num(st.get(code));
      return v == null ? null : round(v / s, 3);
    },
  };
}

// ---------------------------------------------------------------- Couleurs (HSV Tuya ↔ #RRGGBB)
export function hsvToHex(h, s, v) {
  const c = v * s;
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1));
  const m = v - c;
  const [r, g, b] = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x] : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
  return rgbToHex([(r + m) * 255, (g + m) * 255, (b + m) * 255]);
}

export function hexToHsv(hex) {
  const [r, g, b] = hexToRgb(hex).map((n) => n / 255);
  const max = Math.max(r, g, b);
  const d = max - Math.min(r, g, b);
  let h = 0;
  if (d) h = max === r ? 60 * (((g - b) / d) % 6) : max === g ? 60 * ((b - r) / d + 2) : 60 * ((r - g) / d + 4);
  return { h: Math.round((h + 360) % 360), s: max ? d / max : 0, v: max };
}

// ---------------------------------------------------------------- Capacités
/**
 * Capacités FlowIT d'un appareil Tuya.
 * Chaque entrée porte `read(status)` et, si pilotable, `write(value, status)` → commandes Tuya.
 * @param {string} category catégorie Tuya (cz = prise, dj = ampoule, cl = rideau…)
 * @param {Map<string, any>} codes résultat de parseSpecification
 */
export function tuyaCapabilities(category, codes) {
  const sensitive = SENSITIVE_CATEGORIES.has(category);
  const caps = [];
  const has = (code) => codes.has(code);
  const writable = (code) => codes.get(code)?.writable && !sensitive;

  // Interrupteurs : switch_led, switch, switch_1… (multiprises : switch, switch_2, …).
  const switches = [...codes.keys()]
    .filter((k) => SWITCH_CODE.test(k) && codes.get(k).type === 'Boolean' && codes.get(k).writable)
    .sort((a, b) => Number(SWITCH_CODE.exec(a)[1] ?? 0) - Number(SWITCH_CODE.exec(b)[1] ?? 0) || (a.includes('led') ? -1 : 1));
  for (const code of switches) {
    if (sensitive) break;
    caps.push({ key: 'switch', type: 'boolean', writable: true, metadata: {}, read: (st) => (typeof st.get(code) === 'boolean' ? st.get(code) : null), write: (v) => [{ code, value: v }] });
  }

  // Lumière : luminosité, température de blanc, couleur.
  const lightOn = has('switch_led') ? [{ code: 'switch_led', value: true }] : [];
  const whiteMode = codes.get('work_mode')?.values?.range?.includes('white') ? [{ code: 'work_mode', value: 'white' }] : [];
  const brightCode = ['bright_value_v2', 'bright_value'].find(writable);
  if (brightCode && has('switch_led')) {
    const { min = 10, max = 1000 } = codes.get(brightCode).values;
    caps.push({
      key: 'brightness', type: 'number', writable: true, metadata: { min: 1, max: 100, step: 1, unit: '%' },
      read: (st) => {
        const v = num(st.get(brightCode));
        return v == null ? null : Math.max(1, Math.min(100, Math.round(((v - min) / (max - min)) * 99 + 1)));
      },
      write: (pct) => [...lightOn, ...whiteMode, { code: brightCode, value: Math.round(min + ((pct - 1) / 99) * (max - min)) }],
    });
  }
  const tempCode = ['temp_value_v2', 'temp_value'].find(writable);
  if (tempCode && has('switch_led')) {
    const { min = 0, max = 1000 } = codes.get(tempCode).values;
    caps.push({
      key: 'color_temp', type: 'number', writable: true, metadata: { min: KELVIN_MIN, max: KELVIN_MAX, step: 50, unit: 'K' },
      read: (st) => {
        const v = num(st.get(tempCode));
        return v == null ? null : Math.round((KELVIN_MIN + ((v - min) / (max - min)) * (KELVIN_MAX - KELVIN_MIN)) / 10) * 10;
      },
      write: (k) => [...lightOn, ...whiteMode, { code: tempCode, value: Math.round(min + ((k - KELVIN_MIN) / (KELVIN_MAX - KELVIN_MIN)) * (max - min)) }],
    });
  }
  const colourCode = ['colour_data_v2', 'colour_data'].find(writable);
  if (colourCode && has('switch_led')) {
    const sv = colourCode === 'colour_data_v2' ? 1000 : 255;
    caps.push({
      key: 'color', type: 'color', writable: true, metadata: {},
      read: (st) => {
        const c = parseJson(st.get(colourCode));
        return c && num(c.h) != null ? hsvToHex(num(c.h), num(c.s) / sv, num(c.v) / sv) : null;
      },
      write: (hex) => {
        const { h, s, v } = hexToHsv(hex);
        return [...lightOn, ...(has('work_mode') ? [{ code: 'work_mode', value: 'colour' }] : []), { code: colourCode, value: { h, s: Math.round(s * sv), v: Math.max(1, Math.round(v * sv)) } }];
      },
    });
  }

  // Rideaux / volets avec position.
  if (writable('percent_control')) {
    const readCode = has('percent_state') ? 'percent_state' : 'percent_control';
    caps.push({
      key: 'cover_position', type: 'number', writable: true, metadata: { min: 0, max: 100, step: 1, unit: '%' },
      read: (st) => num(st.get(readCode)),
      write: (v) => [{ code: 'percent_control', value: Math.round(v) }],
    });
  }
  // Rideaux / volets : boutons Ouvrir / Stop / Fermer (seuls pilotes des moteurs sans position).
  const controlOptions = codes.get('control')?.values?.range?.filter((o) => COVER_ACTIONS.includes(o)) ?? [];
  if (writable('control') && controlOptions.length) {
    caps.push({
      key: 'cover_control', type: 'enum', writable: true, metadata: { options: COVER_ACTIONS.filter((o) => controlOptions.includes(o)) },
      read: (st) => (COVER_ACTIONS.includes(st.get('control')) ? st.get('control') : null),
      write: (v) => [{ code: 'control', value: v }],
    });
  }

  // Thermostat : consigne (échelle Tuya) et température mesurée.
  if (writable('temp_set')) {
    const c = codes.get('temp_set');
    const s = scaleOf(c);
    caps.push({
      key: 'target_temperature', type: 'number', writable: true,
      metadata: { min: (c.values.min ?? 50) / s, max: (c.values.max ?? 350) / s, step: (c.values.step ?? 5) / s || 0.5, unit: '°C' },
      read: (st) => {
        const v = num(st.get('temp_set'));
        return v == null ? null : round(v / s, 2);
      },
      write: (v) => [{ code: 'temp_set', value: Math.round(v * s) }],
    });
    if (has('temp_current')) caps.push({ key: 'current_temperature', type: 'sensor', writable: false, ...scaled('temp_current', codes.get('temp_current'), '°C') });
  }

  // Capteurs (lecture seule).
  for (const [list, key, unit] of SENSORS) {
    const code = list.find(has);
    if (!code || (key === 'temperature' && writable('temp_set'))) continue;
    if (codes.get(code).type !== 'Integer') continue;
    caps.push({ key, type: 'sensor', writable: false, ...scaled(code, codes.get(code), unit) });
  }
  if (has('doorcontact_state')) {
    // Convention FlowIT : contact = true quand c'est fermé ; Tuya true = ouvert.
    caps.push({ key: 'contact', type: 'sensor', writable: false, metadata: { kind: 'binary' }, read: (st) => (typeof st.get('doorcontact_state') === 'boolean' ? !st.get('doorcontact_state') : null) });
  }
  if (has('pir')) {
    caps.push({ key: 'motion', type: 'sensor', writable: false, metadata: { kind: 'binary' }, read: (st) => (st.get('pir') === 'pir' ? true : st.get('pir') === 'none' ? false : null) });
  }
  return { caps, sensitive };
}

/** Liste d'états Tuya [{code, value}] → Map. */
export function statusMap(list) {
  return new Map((list ?? []).map((s) => [s.code, s.value]));
}

/**
 * Descripteur FlowIT d'un appareil Tuya (même forme que l'inventaire Home Assistant).
 * @param {{id:string,name?:string,category?:string,product_name?:string,model?:string,icon?:string}} device
 * @param {object} spec réponse de /v1.0/devices/{id}/specifications
 * @param {{imageBase?:string|null}} [opts] CDN des photos produits de la région
 */
export function buildTuyaDevice(device, spec, { imageBase = null } = {}) {
  const category = spec?.category ?? device.category;
  const { caps, sensitive } = tuyaCapabilities(category, parseSpecification(spec));
  const desc = {
    externalId: `tuya:${device.id}`,
    tuyaId: device.id,
    name: device.name || device.product_name || device.id,
    vendor: 'Tuya',
    model: device.product_name || device.model || null,
    protocol: 'tuya',
    connectionSource: 'cloud',
    isSensitive: sensitive,
    imageUrl: productImageUrl(device.icon, imageBase),
    capabilities: [],
    capMap: {},
  };
  for (const c of caps) {
    let key = c.key;
    for (let i = 2; desc.capMap[key]; i++) key = `${c.key}_${i}`; // multiprise : switch, switch_2…
    desc.capMap[key] = { base: c.key, read: c.read, write: c.write };
    desc.capabilities.push({ capability_key: key, type: c.type, writable: c.writable, metadata: c.metadata });
  }
  return desc;
}

/** Photo officielle du produit (celle de l'app Smart Life), en https uniquement. */
export function productImageUrl(icon, imageBase) {
  if (typeof icon !== 'string' || !icon.trim()) return null;
  const v = icon.trim();
  if (/^https:\/\//.test(v)) return v;
  if (/^http:\/\//.test(v)) return v.replace(/^http:/, 'https:');
  if (!imageBase || v.includes('..')) return null;
  return `${imageBase}/${v.replace(/^\/+/, '')}`;
}

/** État et disponibilité FlowIT à partir des états Tuya et du drapeau `online`. */
export function tuyaSnapshot(desc, status, online) {
  if (!online) return { state: {}, availability: 'unavailable' };
  const state = {};
  for (const [key, entry] of Object.entries(desc.capMap)) {
    const v = entry.read(status);
    if (v !== null && v !== undefined) state[key] = v;
  }
  return { state, availability: 'available' };
}

/** L'état Tuya reflète-t-il la valeur demandée ? (retour fiable avant de confirmer, §5.4) */
export function tuyaStateMatches(entry, status, expected) {
  const actual = entry.read(status);
  switch (entry.base) {
    case 'brightness':
      return actual != null && Math.abs(actual - expected) <= 2;
    case 'color_temp':
      return actual != null && Math.abs(actual - expected) <= 100;
    case 'color': {
      if (!actual) return false;
      const [a, b] = [hexToRgb(actual), hexToRgb(expected)];
      return a.every((v, i) => Math.abs(v - b[i]) <= 24);
    }
    case 'cover_position':
      return actual != null && Math.abs(actual - expected) <= 2;
    case 'target_temperature':
      return actual != null && Math.abs(actual - expected) < 0.01;
    default:
      return actual === expected;
  }
}
