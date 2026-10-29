// Correspondance Home Assistant ↔ modèle FlowIT (fonctions pures, testées).
//
// Un appareil FlowIT = un appareil du registre HA (ou une entité isolée). Ses capacités
// sont déduites des entités réellement exposées : rien n'est supposé (§5.3, §5.6).

const LIGHT_BRIGHTNESS_MODES = new Set(['brightness', 'color_temp', 'hs', 'xy', 'rgb', 'rgbw', 'rgbww', 'white']);
const LIGHT_COLOR_MODES = new Set(['hs', 'xy', 'rgb', 'rgbw', 'rgbww']);
const COVER_SET_POSITION = 4;

const SENSOR_CLASSES = {
  temperature: 'temperature',
  humidity: 'humidity',
  battery: 'battery',
  power: 'power',
  energy: 'energy',
  illuminance: 'illuminance',
};
const CONTACT_CLASSES = new Set(['door', 'window', 'opening', 'garage_door']);
const MOTION_CLASSES = new Set(['motion', 'occupancy', 'presence']);

/** Plateformes HA → protocole et mode de connexion FlowIT (§6.2 : documenter local/cloud/BLE). */
const PLATFORMS = {
  tuya: ['tuya', 'cloud'],
  localtuya: ['tuya', 'local'],
  zha: ['zigbee', 'gateway'],
  deconz: ['zigbee', 'gateway'],
  shelly: ['wifi', 'local'],
  esphome: ['wifi', 'local'],
  tplink: ['wifi', 'local'],
  tasmota: ['wifi', 'local'],
  wled: ['wifi', 'local'],
  hue: ['zigbee', 'gateway'],
  matter: ['matter', 'local'],
  switchbot: ['ble', 'ble_direct'],
  bthome: ['ble', 'ble_direct'],
  xiaomi_ble: ['ble', 'ble_direct'],
  mqtt: ['mqtt', 'gateway'],
  // Caméras IP (Wi-Fi / Ethernet sur le réseau local)
  onvif: ['wifi', 'local'],
  generic: ['wifi', 'local'],
  reolink: ['wifi', 'local'],
  hikvision: ['wifi', 'local'],
  dahua: ['wifi', 'local'],
  amcrest: ['wifi', 'local'],
  tapo_control: ['wifi', 'local'],
  imou_life: ['wifi', 'cloud'],
  ezviz_cloud: ['wifi', 'cloud'],
};

export function hexToRgb(hex) {
  const n = Number.parseInt(hex.replace('#', ''), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

export function rgbToHex(rgb) {
  if (!Array.isArray(rgb) || rgb.length < 3) return null;
  return `#${rgb
    .slice(0, 3)
    .map((v) => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0'))
    .join('')
    .toUpperCase()}`;
}

function num(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

/**
 * Capacités d'une entité HA. Chaque capacité porte `read(stateObj)` pour extraire sa valeur.
 * @returns {Array<{key:string,type:string,writable:boolean,metadata:object,sensitive?:boolean,read:(s:any)=>any}>}
 */
export function entityCapabilities(stateObj) {
  const [domain] = stateObj.entity_id.split('.');
  const a = stateObj.attributes ?? {};
  const caps = [];
  switch (domain) {
    case 'light': {
      caps.push({ key: 'switch', type: 'boolean', writable: true, metadata: {}, read: (s) => onOff(s) });
      const modes = new Set(a.supported_color_modes ?? []);
      if ([...modes].some((m) => LIGHT_BRIGHTNESS_MODES.has(m))) {
        caps.push({
          key: 'brightness', type: 'number', writable: true, metadata: { min: 1, max: 100, step: 1, unit: '%' },
          read: (s) => (s.attributes?.brightness == null ? null : Math.round((s.attributes.brightness / 255) * 100)),
        });
      }
      if (modes.has('color_temp')) {
        caps.push({
          key: 'color_temp', type: 'number', writable: true,
          metadata: { min: a.min_color_temp_kelvin ?? 2000, max: a.max_color_temp_kelvin ?? 6500, step: 50, unit: 'K' },
          read: (s) => num(s.attributes?.color_temp_kelvin),
        });
      }
      if ([...modes].some((m) => LIGHT_COLOR_MODES.has(m))) {
        caps.push({ key: 'color', type: 'color', writable: true, metadata: {}, read: (s) => rgbToHex(s.attributes?.rgb_color) });
      }
      break;
    }
    case 'switch':
    case 'input_boolean':
    case 'fan':
      caps.push({ key: 'switch', type: 'boolean', writable: true, metadata: {}, read: (s) => onOff(s) });
      break;
    case 'cover': {
      const canSetPosition = ((a.supported_features ?? 0) & COVER_SET_POSITION) !== 0;
      caps.push({
        key: 'cover_position', type: 'number', writable: true,
        metadata: canSetPosition ? { min: 0, max: 100, step: 1, unit: '%' } : { min: 0, max: 100, step: 100, unit: '%' },
        read: (s) => {
          const p = num(s.attributes?.current_position);
          if (p != null) return p;
          return s.state === 'open' ? 100 : s.state === 'closed' ? 0 : null;
        },
      });
      break;
    }
    case 'climate': {
      caps.push({
        key: 'target_temperature', type: 'number', writable: true,
        metadata: { min: a.min_temp ?? 7, max: a.max_temp ?? 35, step: a.target_temp_step ?? 0.5, unit: '°C' },
        read: (s) => num(s.attributes?.temperature),
      });
      if (Array.isArray(a.hvac_modes) && a.hvac_modes.length) {
        caps.push({ key: 'hvac_mode', type: 'enum', writable: true, metadata: { options: a.hvac_modes }, read: (s) => s.state });
      }
      if (a.current_temperature != null) {
        caps.push({ key: 'current_temperature', type: 'sensor', writable: false, metadata: { unit: '°C' }, read: (s) => num(s.attributes?.current_temperature) });
      }
      break;
    }
    case 'lock':
      // Serrure : exposée mais bloquée par défaut (is_sensitive, §9).
      caps.push({ key: 'lock', type: 'boolean', writable: true, metadata: {}, sensitive: true, read: (s) => (s.state === 'locked' ? true : s.state === 'unlocked' ? false : null) });
      break;
    case 'sensor': {
      const key = SENSOR_CLASSES[a.device_class];
      if (key) {
        caps.push({ key, type: 'sensor', writable: false, metadata: a.unit_of_measurement ? { unit: a.unit_of_measurement } : {}, read: (s) => num(s.state) });
      }
      break;
    }
    case 'binary_sensor':
      if (CONTACT_CLASSES.has(a.device_class)) {
        // Convention FlowIT (Zigbee2MQTT) : contact = true quand c'est fermé ; HA "on" = ouvert.
        caps.push({ key: 'contact', type: 'sensor', writable: false, metadata: { kind: 'binary' }, read: (s) => (s.state === 'on' ? false : s.state === 'off' ? true : null) });
      } else if (MOTION_CLASSES.has(a.device_class)) {
        caps.push({ key: 'motion', type: 'sensor', writable: false, metadata: { kind: 'binary' }, read: (s) => (s.state === 'on' ? true : s.state === 'off' ? false : null) });
      }
      break;
    case 'camera':
      // Image récupérée à la demande par la passerelle (camera_proxy), jamais par l'application.
      caps.push({ key: 'camera', type: 'string', writable: false, metadata: { kind: 'camera' }, read: (s) => s.state });
      break;
    case 'alarm_control_panel':
      caps.push({ key: 'alarm', type: 'sensor', writable: false, metadata: {}, sensitive: true, read: (s) => s.state });
      break;
    default:
      break;
  }
  return caps;
}

function onOff(s) {
  return s.state === 'on' ? true : s.state === 'off' ? false : null;
}

function guessProtocol(platform, device) {
  const ids = (device?.identifiers ?? []).flat().map(String);
  if (platform === 'mqtt' && ids.some((i) => i.startsWith('zigbee2mqtt'))) return ['zigbee', 'gateway'];
  return PLATFORMS[platform] ?? ['other', 'gateway'];
}

/**
 * Construit l'inventaire FlowIT à partir des états et registres HA.
 * @param {Array} states        résultat de `get_states`
 * @param {Array} entityRegistry `config/entity_registry/list`
 * @param {Array} deviceRegistry `config/device_registry/list`
 * @param {RegExp|null} filter  filtre facultatif sur entity_id
 */
export function buildInventory(states, entityRegistry = [], deviceRegistry = [], filter = null) {
  const entities = new Map(entityRegistry.map((e) => [e.entity_id, e]));
  const devices = new Map(deviceRegistry.map((d) => [d.id, d]));
  const groups = new Map();

  for (const s of states) {
    if (filter && !filter.test(s.entity_id)) continue;
    const reg = entities.get(s.entity_id);
    if (reg?.disabled_by || reg?.hidden_by || reg?.entity_category) continue; // diagnostics/config ignorés
    const caps = entityCapabilities(s);
    if (!caps.length) continue;
    const externalId = reg?.device_id ? `device:${reg.device_id}` : `entity:${s.entity_id}`;
    const dev = reg?.device_id ? devices.get(reg.device_id) : null;
    if (!groups.has(externalId)) {
      const [protocol, connectionSource] = guessProtocol(reg?.platform, dev);
      groups.set(externalId, {
        externalId,
        name: dev?.name_by_user ?? dev?.name ?? s.attributes?.friendly_name ?? s.entity_id,
        vendor: dev?.manufacturer ?? null,
        model: dev?.model ?? null,
        protocol,
        connectionSource,
        isSensitive: false,
        capabilities: [],
        capMap: {},
      });
    }
    const g = groups.get(externalId);
    for (const c of caps) {
      let key = c.key;
      for (let i = 2; g.capMap[key]; i++) key = `${c.key}_${i}`; // ex. double relais : switch, switch_2
      g.capMap[key] = { entityId: s.entity_id, base: c.key, read: c.read };
      g.capabilities.push({ capability_key: key, type: c.type, writable: c.writable, metadata: c.metadata });
      if (c.sensitive) g.isSensitive = true;
    }
  }
  return [...groups.values()];
}

/** État et disponibilité courants d'un appareil FlowIT. */
export function deviceSnapshot(descriptor, statesById) {
  const state = {};
  let anyAvailable = false;
  let anyUnknown = false;
  for (const [key, entry] of Object.entries(descriptor.capMap)) {
    const s = statesById.get(entry.entityId);
    if (!s || s.state === 'unavailable') continue;
    if (s.state === 'unknown') anyUnknown = true;
    anyAvailable = true;
    const v = entry.read(s);
    if (v !== null && v !== undefined) state[key] = v;
  }
  const availability = anyAvailable ? (Object.keys(state).length || !anyUnknown ? 'available' : 'unknown') : 'unavailable';
  return { state, availability };
}

/** Appel de service HA correspondant à une commande FlowIT. */
export function serviceCall(entry, value) {
  const entityId = entry.entityId;
  const [domain] = entityId.split('.');
  const target = { entity_id: entityId };
  switch (entry.base) {
    case 'switch':
      return { domain: domain === 'input_boolean' ? 'input_boolean' : domain, service: value ? 'turn_on' : 'turn_off', target, data: {} };
    case 'brightness':
      return { domain: 'light', service: 'turn_on', target, data: { brightness_pct: value } };
    case 'color_temp':
      return { domain: 'light', service: 'turn_on', target, data: { color_temp_kelvin: value } };
    case 'color':
      return { domain: 'light', service: 'turn_on', target, data: { rgb_color: hexToRgb(value) } };
    case 'cover_position':
      if (value >= 100) return { domain: 'cover', service: 'open_cover', target, data: {} };
      if (value <= 0) return { domain: 'cover', service: 'close_cover', target, data: {} };
      return { domain: 'cover', service: 'set_cover_position', target, data: { position: value } };
    case 'target_temperature':
      return { domain: 'climate', service: 'set_temperature', target, data: { temperature: value } };
    case 'hvac_mode':
      return { domain: 'climate', service: 'set_hvac_mode', target, data: { hvac_mode: value } };
    default:
      return null; // lock et autres : jamais pilotés par la passerelle sans validation dédiée
  }
}

/** L'état HA reflète-t-il la valeur demandée ? (retour fiable avant de confirmer, §5.4) */
export function stateMatches(entry, stateObj, expected) {
  if (!stateObj || stateObj.state === 'unavailable') return false;
  const actual = entry.read(stateObj);
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
