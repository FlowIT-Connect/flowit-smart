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

const ALARMS = [
  [['smoke_sensor_status', 'smoke_sensor_state'], 'smoke'],
  [['watersensor_state', 'water_leak_state'], 'water_leak'],
  [['gas_sensor_status', 'gas_sensor_state'], 'gas'],
];
/** Tuya : alarm / normal, ou '1' (alarme) / '2' (normal), ou booléen. */
function alarmValue(v) {
  if (typeof v === 'boolean') return v;
  if (v === 'alarm' || v === '1' || v === 1) return true;
  if (v === 'normal' || v === '2' || v === 2) return false;
  return null;
}
const BATTERY_LEVELS = { low: 10, middle: 50, high: 100 };

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

// ---------------------------------------------------------------- Climatisation / chauffage
/** Modes Tuya → modes FlowIT (mêmes noms que Home Assistant). */
const TUYA_HVAC = {
  cold: 'cool', cool: 'cool', cooling: 'cool',
  hot: 'heat', heat: 'heat', heating: 'heat',
  wet: 'dry', dehumidification: 'dry', dehumidify: 'dry', dry: 'dry',
  wind: 'fan_only', fan: 'fan_only', fan_only: 'fan_only', air: 'fan_only',
  auto: 'auto',
};
/** Ordre d'affichage des modes. */
export const HVAC_ORDER = ['off', 'auto', 'cool', 'heat', 'dry', 'fan_only', 'heat_cool'];
/** Vitesses de ventilation Tuya → FlowIT. */
const TUYA_FAN = {
  auto: 'auto', mute: 'quiet', sleep: 'quiet', quiet: 'quiet', silent: 'quiet',
  low: 'low', '1': 'low', level_1: 'low',
  mid: 'medium', middle: 'medium', medium: 'medium', '2': 'medium', level_2: 'medium',
  high: 'high', strong: 'high', '3': 'high', level_3: 'high', turbo: 'turbo', '4': 'turbo', level_4: 'turbo',
};
const FAN_ORDER = ['auto', 'quiet', 'low', 'medium', 'high', 'turbo'];
/** Programmes Tuya des thermostats / vannes → ambiances FlowIT. */
const TUYA_PRESET = {
  auto: 'schedule', program: 'schedule', programming: 'schedule', smart: 'schedule',
  manual: 'manual', hand: 'manual', temp_manual: 'manual',
  eco: 'eco', comfort: 'comfort', holiday: 'away', away: 'away', leave: 'away',
  sleep: 'sleep', boost: 'boost', antifreeze: 'frost', frost: 'frost', frost_protection: 'frost',
};
const TUYA_ACTION = {
  heating: 'heating', heat: 'heating', hot: 'heating', opened: 'heating', open: 'heating',
  cooling: 'cooling', cold: 'cooling', cool: 'cooling',
  standby: 'idle', idle: 'idle', stop: 'idle', closed: 'idle', close: 'idle', warming: 'idle',
  drying: 'drying', fan: 'fan', wind: 'fan', off: 'off',
};

const enumRange = (c) => (Array.isArray(c?.values?.range) ? c.values.range.map(String) : []);
const firstCode = (list, ok) => list.find(ok);

/**
 * Énumération Tuya traduite : options FlowIT ordonnées, lecture et écriture via la table.
 * Les valeurs inconnues sont gardées telles quelles (l'app les affiche en brut).
 */
function translatedEnum(code, c, table, order) {
  const raw = enumRange(c);
  const toFlow = new Map();
  const toTuya = new Map();
  for (const r of raw) {
    const f = table[r.toLowerCase()] ?? r;
    if (!toTuya.has(f)) toTuya.set(f, r);
    toFlow.set(r, f);
  }
  const options = [...toTuya.keys()].sort((a, b) => (order.indexOf(a) + 1 || 99) - (order.indexOf(b) + 1 || 99));
  return { options, read: (st) => toFlow.get(String(st.get(code))) ?? null, write: (v) => [{ code, value: toTuya.get(v) }] };
}

function climateCapabilities(codes, writable, has) {
  const caps = [];
  const tempCode = firstCode(['temp_set', 'temp', 'temp_set_c'], (k) => writable(k) && codes.get(k).type === 'Integer');
  if (!tempCode) return caps;
  const c = codes.get(tempCode);
  const s = scaleOf(c);
  caps.push({
    key: 'target_temperature', type: 'number', writable: true,
    metadata: { min: (c.values.min ?? 50) / s, max: (c.values.max ?? 350) / s, step: (c.values.step ?? 5) / s || 0.5, unit: '°C' },
    read: (st) => {
      const v = num(st.get(tempCode));
      return v == null ? null : round(v / s, 2);
    },
    write: (v) => [{ code: tempCode, value: Math.round(v * s) }],
  });
  if (has('temp_current')) caps.push({ key: 'current_temperature', type: 'sensor', writable: false, ...scaled('temp_current', codes.get('temp_current'), '°C') });

  // Mode : « mode » décrit soit un mode de clim (froid, chaud…), soit un programme de thermostat.
  const powerCode = firstCode(['switch', 'switch_1', 'power'], (k) => writable(k) && codes.get(k).type === 'Boolean');
  const modeCode = firstCode(['mode', 'work_mode', 'mode_set'], (k) => writable(k) && codes.get(k).type === 'Enum');
  const modeRange = modeCode ? enumRange(codes.get(modeCode)) : [];
  const isHvac = modeRange.some((r) => ['cold', 'cool', 'wet', 'wind', 'dehumidification'].includes(r.toLowerCase()));
  if (modeCode && isHvac) {
    const e = translatedEnum(modeCode, codes.get(modeCode), TUYA_HVAC, HVAC_ORDER);
    const options = powerCode ? ['off', ...e.options.filter((o) => o !== 'off')] : e.options;
    caps.push({
      key: 'hvac_mode', type: 'enum', writable: true, metadata: { options },
      read: (st) => (powerCode && st.get(powerCode) === false ? 'off' : e.read(st)),
      write: (v) => {
        if (v === 'off') return [{ code: powerCode, value: false }];
        return [...(powerCode ? [{ code: powerCode, value: true }] : []), ...e.write(v)];
      },
    });
  } else if (powerCode) {
    // Radiateur, chaudière, thermostat simple : arrêt ou chauffe.
    caps.push({
      key: 'hvac_mode', type: 'enum', writable: true, metadata: { options: ['off', 'heat'] },
      read: (st) => (st.get(powerCode) === false ? 'off' : st.get(powerCode) === true ? 'heat' : null),
      write: (v) => [{ code: powerCode, value: v !== 'off' }],
    });
  }
  if (modeCode && !isHvac && modeRange.length > 1) {
    const e = translatedEnum(modeCode, codes.get(modeCode), TUYA_PRESET, ['schedule', 'manual', 'comfort', 'eco', 'sleep', 'away', 'frost', 'boost']);
    caps.push({ key: 'preset', type: 'enum', writable: true, metadata: { options: e.options }, read: e.read, write: e.write });
  }

  const fanCode = firstCode(['windspeed', 'fan_speed_enum', 'fan_speed', 'wind', 'fan_level'], (k) => writable(k) && codes.get(k).type === 'Enum');
  if (fanCode) {
    const e = translatedEnum(fanCode, codes.get(fanCode), TUYA_FAN, FAN_ORDER);
    caps.push({ key: 'fan_mode', type: 'enum', writable: true, metadata: { options: e.options }, read: e.read, write: e.write });
  }
  const swingCode = firstCode(['swing', 'switch_vertical', 'shake', 'switch_horizontal', 'windshake'], (k) => writable(k) && codes.get(k).type === 'Boolean');
  if (swingCode) caps.push(boolCap('swing', swingCode));
  if (writable('eco') && codes.get('eco').type === 'Boolean') caps.push(boolCap('eco', 'eco'));
  if (writable('sleep') && codes.get('sleep').type === 'Boolean') caps.push(boolCap('sleep', 'sleep'));
  if (writable('window_check') && codes.get('window_check').type === 'Boolean') caps.push(boolCap('window_detection', 'window_check'));
  if (writable('child_lock') && codes.get('child_lock').type === 'Boolean') caps.push(boolCap('child_lock', 'child_lock'));
  // Hors-gel des thermostats de chaudière (souvent un simple interrupteur à côté du programme).
  const frostCode = firstCode(['frost', 'antifreeze', 'frost_protection'], (k) => writable(k) && codes.get(k).type === 'Boolean');
  if (frostCode) caps.push(boolCap('frost_protection', frostCode));
  // Étalonnage de la sonde (± quelques degrés) : réglage, pas une commande du quotidien.
  const calibCode = firstCode(['temp_correction', 'temp_calibration', 'temp_calibrate'], (k) => writable(k) && codes.get(k).type === 'Integer');
  if (calibCode) {
    const cc = codes.get(calibCode);
    const cs = scaleOf(cc);
    caps.push({
      key: 'temp_calibration', type: 'number', writable: true,
      metadata: { min: (cc.values.min ?? -9) / cs, max: (cc.values.max ?? 9) / cs, step: (cc.values.step ?? 1) / cs || 0.5, unit: '°C', setting: true },
      read: (st) => {
        const v = num(st.get(calibCode));
        return v == null ? null : round(v / cs, 2);
      },
      write: (v) => [{ code: calibCode, value: Math.round(v * cs) }],
    });
  }
  if (has('window_state')) {
    caps.push({
      key: 'window_open', type: 'sensor', writable: false, metadata: { kind: 'binary' },
      read: (st) => {
        const v = st.get('window_state');
        return v === 'open' || v === true ? true : v === 'close' || v === 'closed' || v === false ? false : null;
      },
    });
  }
  const actionCode = firstCode(['work_state', 'valve_state'], (k) => has(k) && codes.get(k).type === 'Enum');
  const relayCode = firstCode(['valve_state', 'relay_status', 'heating_state'], (k) => has(k) && codes.get(k).type === 'Boolean');
  if (!actionCode && relayCode) {
    // Récepteur RF / relais de chaudière : true = la chaudière est appelée.
    caps.push({ key: 'hvac_action', type: 'enum', writable: false, metadata: {}, read: (st) => (typeof st.get(relayCode) === 'boolean' ? (st.get(relayCode) ? 'heating' : 'idle') : null) });
  }
  if (actionCode) {
    caps.push({
      key: 'hvac_action', type: 'enum', writable: false, metadata: {},
      read: (st) => {
        const v = st.get(actionCode);
        return v == null ? null : TUYA_ACTION[String(v).toLowerCase()] ?? null;
      },
    });
  }
  return caps;
}

// ---------------------------------------------------------------- Détecteurs de présence
/** Codes Tuya des réglages, selon les fabricants (le premier présent est pris). */
const PRESENCE_SETTINGS = [
  // [clé FlowIT, codes possibles, unité par défaut]
  ['sensitivity', ['sensitivity', 'presence_sensitivity', 'motion_sensitivity', 'sensitivity_level', 'move_sensitivity'], null],
  ['detection_range', ['far_detection', 'detection_distance_max', 'maximum_range', 'max_distance', 'detection_range', 'large_motion_detection_distance'], 'm'],
  ['detection_min', ['near_detection', 'detection_distance_min', 'minimum_range', 'min_distance'], 'm'],
  ['presence_delay', ['fading_time', 'presence_delay', 'none_delay_time', 'presence_time', 'delay_time', 'hold_time', 'pir_delay', 'unmanned_delay', 'nobody_time'], 's'],
];
const ACTIVITY_CODES = ['human_motion_state', 'motion_state', 'person_state'];
const DISTANCE_CODES = ['target_dis_closest', 'dis_current', 'target_distance', 'distance'];

/** Unité Tuya → unité affichée (les distances en cm sont converties en m). */
function presenceUnit(c, fallback) {
  const u = String(c?.values?.unit ?? '').toLowerCase();
  if (u === 'cm') return { unit: 'm', factor: 100 };
  if (u === 'm' || u === 'meter') return { unit: 'm', factor: 1 };
  if (u === 's' || u === 'sec' || u === 'second') return { unit: 's', factor: 1 };
  if (u === 'min' || u === 'minute') return { unit: 'min', factor: 1 };
  return { unit: fallback ?? (u || null), factor: 1 };
}

function presenceCapabilities(codes, writable, has) {
  const caps = [];
  for (const [key, list, fallbackUnit] of PRESENCE_SETTINGS) {
    const code = list.find((k) => writable(k) && ['Integer', 'Enum'].includes(codes.get(k).type));
    if (!code) continue;
    const c = codes.get(code);
    if (c.type === 'Enum') {
      const options = enumRange(c);
      if (options.length < 2) continue;
      caps.push({ key, type: 'enum', writable: true, metadata: { options, setting: true }, read: (st) => (st.get(code) == null ? null : String(st.get(code))), write: (v) => [{ code, value: v }] });
      continue;
    }
    const s = scaleOf(c);
    const { unit, factor } = presenceUnit(c, fallbackUnit);
    const div = s * factor;
    const step = Math.max((Number(c.values.step) || 1) / div, 0.01);
    caps.push({
      key, type: 'number', writable: true,
      metadata: { min: round((c.values.min ?? 0) / div, 2), max: round((c.values.max ?? 10) / div, 2), step: round(step, 2), ...(unit ? { unit } : {}), setting: true },
      read: (st) => {
        const v = num(st.get(code));
        return v == null ? null : round(v / div, 2);
      },
      write: (v) => [{ code, value: Math.round(v * div) }],
    });
  }
  const activity = ACTIVITY_CODES.find((k) => has(k) && codes.get(k).type === 'Enum');
  if (activity) caps.push({ key: 'activity', type: 'sensor', writable: false, metadata: { kind: 'text' }, read: (st) => (st.get(activity) == null ? null : String(st.get(activity))) });
  const distance = DISTANCE_CODES.find((k) => has(k) && codes.get(k).type === 'Integer');
  if (distance) {
    const c = codes.get(distance);
    const { unit, factor } = presenceUnit(c, 'm');
    const div = scaleOf(c) * factor;
    caps.push({ key: 'target_distance', type: 'sensor', writable: false, metadata: { unit }, read: (st) => { const v = num(st.get(distance)); return v == null ? null : round(v / div, 2); } });
  }
  return caps;
}

function boolCap(key, code) {
  return { key, type: 'boolean', writable: true, metadata: {}, read: (st) => (typeof st.get(code) === 'boolean' ? st.get(code) : null), write: (v) => [{ code, value: v }] };
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

  // Climatisation et chauffage : clim (kt), thermostat (wk), vanne de radiateur (wkf),
  // radiateur (qn), chauffe-eau / chaudière (rs), clim infrarouge (infrared_ac).
  caps.push(...climateCapabilities(codes, writable, has));

  // Capteurs (lecture seule).
  for (const [list, key, unit] of SENSORS) {
    const code = list.find(has);
    if (!code || (key === 'temperature' && ['temp_set', 'temp', 'temp_set_c'].some(writable))) continue;
    if (codes.get(code).type !== 'Integer') continue;
    caps.push({ key, type: 'sensor', writable: false, ...scaled(code, codes.get(code), unit) });
  }
  if (has('doorcontact_state')) {
    // Convention FlowIT : contact = true quand c'est fermé ; Tuya true = ouvert.
    caps.push({ key: 'contact', type: 'sensor', writable: false, metadata: { kind: 'binary' }, read: (st) => (typeof st.get('doorcontact_state') === 'boolean' ? !st.get('doorcontact_state') : null) });
  }
  if (has('pir')) {
    caps.push({ key: 'motion', type: 'sensor', writable: false, metadata: { kind: 'binary' }, read: (st) => (st.get('pir') === 'pir' ? true : st.get('pir') === 'none' ? false : null) });
  } else if (has('presence_state')) {
    // Détecteurs de présence Zigbee (radar) : presence, small_move, large_move… / none.
    caps.push({
      key: 'motion', type: 'sensor', writable: false, metadata: { kind: 'binary' },
      read: (st) => {
        const v = st.get('presence_state');
        return v == null ? null : !['none', 'no_presence', 'nobody', 'peaceful'].includes(String(v));
      },
    });
  }
  // Détecteurs de présence : activité, distance de la personne et réglages du capteur.
  if (caps.some((c) => c.key === 'motion')) caps.push(...presenceCapabilities(codes, writable, has));
  // Alarmes (fumée, fuite d'eau, gaz) : true = alarme en cours.
  for (const [codesList, key] of ALARMS) {
    const code = codesList.find(has);
    if (code) caps.push({ key, type: 'sensor', writable: false, metadata: { kind: 'binary' }, read: (st) => alarmValue(st.get(code)) });
  }
  // Luminosité ambiante (capteurs de lumière, détecteurs de présence).
  const luxCode = firstCode(['illuminance_value', 'bright_value'], (k) => has(k) && !codes.get(k).writable && codes.get(k).type === 'Integer');
  if (luxCode) caps.push({ key: 'illuminance', type: 'sensor', writable: false, ...scaled(luxCode, codes.get(luxCode), 'lx') });
  // Pile sans pourcentage (beaucoup de capteurs Zigbee) : low / middle / high.
  if (!caps.some((c) => c.key === 'battery') && has('battery_state')) {
    caps.push({ key: 'battery', type: 'sensor', writable: false, metadata: { unit: '%', approximate: true }, read: (st) => BATTERY_LEVELS[String(st.get('battery_state'))] ?? null });
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
    // Codes déclarés par l'appareil (plages comprises, aucune valeur) : pour diagnostiquer
    // un appareil mal reconnu sans accès au cloud Tuya.
    diagnostic: { category, codes: [...parseSpecification(spec)].map(([code, c]) => ({ code, type: c.type, writable: c.writable, ...(Object.keys(c.values ?? {}).length ? { values: c.values } : {}) })) },
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
