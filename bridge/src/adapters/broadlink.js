// Télécommande infrarouge Broadlink (RM4 Pro, RM4 mini…) reçue de Home Assistant.
//
// L'intégration Broadlink de HA expose une entité `remote.*` (envoi et apprentissage de
// codes) et, si le câble capteur est branché, la température et l'humidité. Les codes
// appris sont rangés par HA dans /config/.storage/broadlink_remote_<mac>_codes, sous la
// forme { "<appareil>": { "<touche>": "<code>" } } : chaque « appareil » (tv, clim…)
// devient un appareil Solea à part, avec ses touches.
//
// Clim infrarouge : une clim ne renvoie pas son état. Si les touches suivent la convention
// `off`, `cool_22`, `heat_24`, `dry`, `fan_only`, `auto`…, Solea en fait un vrai thermostat
// (mode + consigne, état supposé d'après le dernier ordre envoyé), utilisable par les
// ambiances, programmes et automatisations comme les autres clims.

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';

import CLIMATE_INDEX from './ir_climate_index.json' with { type: 'json' };

export const IR_MODES = ['cool', 'heat', 'dry', 'fan_only', 'auto', 'heat_cool'];
const MODE_TEMP = new RegExp(`^(${IR_MODES.join('|')})_(\\d{2}(?:[.,]5)?)$`);
const NAME = /^[\p{L}\p{N}][\p{L}\p{N} _+\-.]{0,39}$/u;

/** Nom d'appareil ou de touche acceptable (pas de chemin, pas de caractère spécial). */
export const validIrName = (s) => typeof s === 'string' && NAME.test(s.trim());

/** Fichier des codes appris d'une télécommande Broadlink (unique_id = adresse MAC). */
export const codesFile = (configDir, uniqueId) => join(configDir, '.storage', `broadlink_remote_${uniqueId}_codes`);

/**
 * Lit les codes appris : { appareil: [touches…] } (les codes eux-mêmes ne sortent jamais
 * de la box). {} si le fichier n'existe pas encore (rien d'appris).
 */
export async function readLearnedCommands(file, readImpl = readFile) {
  let raw;
  try {
    raw = await readImpl(file, 'utf8');
  } catch (e) {
    if (e.code === 'ENOENT') return {};
    throw e;
  }
  const data = JSON.parse(raw)?.data ?? {};
  const out = {};
  for (const [device, commands] of Object.entries(data)) {
    if (!commands || typeof commands !== 'object') continue;
    const names = Object.keys(commands).filter(validIrName).sort();
    if (names.length) out[device] = names;
  }
  return out;
}

/**
 * Touches d'une clim selon la convention : modes et températures appris.
 * @returns {{modes:string[], temps:Record<string,number[]>, min:number, max:number}|null} null si ce n'est pas une clim
 */
export function irClimate(commands) {
  const temps = {};
  const modes = new Set();
  for (const c of commands) {
    const m = MODE_TEMP.exec(c);
    if (m) {
      (temps[m[1]] ??= []).push(Number(m[2].replace(',', '.')));
      modes.add(m[1]);
    } else if (IR_MODES.includes(c)) modes.add(c);
  }
  const all = Object.values(temps).flat();
  if (!commands.includes('off') || !all.length) return null;
  for (const list of Object.values(temps)) list.sort((a, b) => a - b);
  return { modes: IR_MODES.filter((m) => modes.has(m)), temps, min: Math.min(...all), max: Math.max(...all) };
}

/** Touche à envoyer pour un mode et une consigne (température apprise la plus proche). */
export function climateCommand(climate, commands, mode, target) {
  if (mode === 'off') return 'off';
  const list = climate.temps[mode];
  if (list?.length) {
    const t = list.reduce((best, v) => (Math.abs(v - target) < Math.abs(best - target) ? v : best), list[0]);
    const name = `${mode}_${t}`;
    if (commands.includes(name)) return name;
    const comma = name.replace('.', ',');
    if (commands.includes(comma)) return comma;
  }
  return commands.includes(mode) ? mode : null;
}

// ---------------------------------------------------------------------------
// Télécommandes de clim prêtes à l'emploi (comme la bibliothèque de l'app Broadlink).
//
// Codes de la bibliothèque libre SmartIR (licence MIT, https://github.com/smartHomeHub/SmartIR) :
// pour chaque télécommande, un code infrarouge par réglage complet (mode × ventilation ×
// oscillation × température). Index des 395 télécommandes Broadlink dans ir_climate_index.json
// (tools/ir_climate_index.sh) ; les codes d'une télécommande sont téléchargés une fois, à son
// choix, puis gardés sur la box.

export const SMARTIR_COMMIT = '3dca407e3c475b57c02c08b97ae521a4ef0bbf43';
export const CLIMATE_PROFILES = new Map(CLIMATE_INDEX.map((p) => [p.id, p]));
export const profileUrl = (id) => `https://raw.githubusercontent.com/smartHomeHub/SmartIR/${SMARTIR_COMMIT}/codes/climate/${id}.json`;
const B64 = /^[A-Za-z0-9+/]+=*$/;

/** Fichier de codes SmartIR → profil utilisable (null s'il n'est pas pour Broadlink). */
export function parseProfile(id, json) {
  const ref = CLIMATE_PROFILES.get(id);
  if (!ref || json?.supportedController !== 'Broadlink' || json?.commandsEncoding !== 'Base64') return null;
  if (typeof json.commands?.off !== 'string') return null;
  return { ...ref, commands: json.commands };
}

/** Choisit dans un niveau de l'arbre des codes : ventilation, oscillation, puis température. */
function pick(node, { fan_mode, swing_mode, target_temperature }) {
  for (let depth = 0; depth < 6 && node && typeof node === 'object' && !Array.isArray(node); depth++) {
    const keys = Object.keys(node);
    if (!keys.length) return null;
    if (fan_mode != null && keys.includes(fan_mode)) node = node[fan_mode];
    else if (swing_mode != null && keys.includes(swing_mode)) node = node[swing_mode];
    else if (keys.every((k) => Number.isFinite(Number(k)))) {
      const t = Number(target_temperature);
      node = node[keys.reduce((best, k) => (Math.abs(Number(k) - t) < Math.abs(Number(best) - t) ? k : best), keys[0])];
    } else node = node[keys[0]];
  }
  return node;
}

const asCodes = (v) => {
  const list = (Array.isArray(v) ? v : [v]).filter((c) => typeof c === 'string' && B64.test(c));
  return list.length ? list : null;
};

/** Codes à envoyer pour un réglage complet de la clim (null si la télécommande ne l'a pas). */
export function profileCodes(profile, st) {
  if (st.hvac_mode === 'off') return asCodes(profile.commands.off);
  const node = profile.commands[st.hvac_mode];
  return node === undefined ? null : asCodes(pick(node, st));
}

/** Réglage de départ d'une clim de la bibliothèque. */
export function profileDefaults(profile) {
  const fans = profile.fans;
  return {
    hvac_mode: 'off',
    target_temperature: Math.min(Math.max(24, profile.min), profile.max),
    fan_mode: fans.includes('auto') ? 'auto' : (fans[0] ?? null),
    swing_mode: profile.swings[0] ?? null,
  };
}

/** Essai d'une télécommande : froid 24° (la clim doit s'allumer ou biper) ou arrêt. */
export function profileTestCodes(profile, mode = 'cool') {
  if (mode === 'off') return asCodes(profile.commands.off);
  const st = { ...profileDefaults(profile), hvac_mode: profile.modes.includes('cool') ? 'cool' : profile.modes[0] };
  return profileCodes(profile, st);
}

/**
 * Choix des télécommandes de clim (par Broadlink et par appareil) et cache des codes, gardés
 * dans `dir` (/data/broadlink sur la box). Sans dossier : en mémoire seulement.
 */
export class IrProfileStore {
  constructor({ dir = null, fetchImpl = (...a) => fetch(...a), readImpl = readFile, writeImpl = writeFile } = {}) {
    this.dir = dir;
    this.fetchImpl = fetchImpl;
    this.readImpl = readImpl;
    this.writeImpl = writeImpl;
    this.selections = {}; // uniqueId -> { appareil: id }
    this.cache = new Map(); // id -> profil
    this.loaded = false;
  }

  async load() {
    if (this.loaded) return;
    this.loaded = true;
    if (!this.dir) return;
    try {
      const raw = JSON.parse(await this.readImpl(join(this.dir, 'profiles.json'), 'utf8'));
      if (raw && typeof raw === 'object') this.selections = raw;
    } catch (e) {
      if (e.code !== 'ENOENT') throw e;
    }
  }

  selected(uniqueId) {
    return this.selections[uniqueId] ?? {};
  }

  async select(uniqueId, device, id) {
    const cur = { ...this.selected(uniqueId) };
    if (id == null) delete cur[device];
    else cur[device] = id;
    this.selections = { ...this.selections, [uniqueId]: cur };
    if (this.dir) {
      await mkdir(this.dir, { recursive: true });
      await this.writeImpl(join(this.dir, 'profiles.json'), JSON.stringify(this.selections, null, 2));
    }
  }

  /** Codes d'une télécommande : mémoire, puis box, puis téléchargement (une seule fois). */
  async profile(id) {
    if (this.cache.has(id)) return this.cache.get(id);
    if (!CLIMATE_PROFILES.has(id)) throw new Error('Télécommande inconnue');
    const file = this.dir ? join(this.dir, `climate_${id}.json`) : null;
    let json = null;
    if (file) {
      try {
        json = JSON.parse(await this.readImpl(file, 'utf8'));
      } catch {
        json = null;
      }
    }
    if (!json) {
      const res = await this.fetchImpl(profileUrl(id), { signal: AbortSignal.timeout(20_000) });
      if (!res.ok) throw new Error(`Codes de la télécommande indisponibles (HTTP ${res.status})`);
      const text = await res.text();
      json = JSON.parse(text);
      if (file && parseProfile(id, json)) {
        await mkdir(this.dir, { recursive: true });
        await this.writeImpl(file, text);
      }
    }
    const profile = parseProfile(id, json);
    if (!profile) throw new Error('Codes de la télécommande illisibles');
    this.cache.set(id, profile);
    return profile;
  }

  /** Profils choisis d'un Broadlink, chargés : { appareil: profil }. */
  async resolved(uniqueId) {
    const out = {};
    for (const [device, id] of Object.entries(this.selected(uniqueId))) {
      try {
        out[device] = await this.profile(id);
      } catch {
        // Box hors ligne au premier choix : nouvel essai au prochain inventaire.
      }
    }
    return out;
  }
}

const LABELS = { tv: 'Télé', television: 'Télé', tele: 'Télé', télé: 'Télé', clim: 'Clim', climatiseur: 'Clim', ac: 'Clim', decodeur: 'Décodeur', décodeur: 'Décodeur', ventilateur: 'Ventilateur', fan: 'Ventilateur' };

/** Nom affiché d'un sous-appareil appris (« tv » → « Télé »). */
export function irDeviceName(sub) {
  const k = sub.trim().toLowerCase();
  if (LABELS[k]) return LABELS[k];
  return k.charAt(0).toUpperCase() + sub.trim().slice(1).replace(/_/g, ' ');
}

/**
 * Ajoute à l'inventaire HA les fonctions Broadlink :
 *  - sur l'appareil Broadlink : la capacité `ir_learn` (apprendre ou oublier une touche) ;
 *  - un appareil Solea par sous-appareil appris (Télé, Clim…), avec ses touches, et un
 *    thermostat si c'est une clim (touches off / cool_22…).
 *
 * @param {Array} list        inventaire construit par buildInventory (modifié en place)
 * @param {Array} remotes     [{entityId, uniqueId, deviceId}] entités remote.* de la plateforme broadlink
 * @param {Map<string,Record<string,string[]>>} learned  uniqueId -> {appareil: [touches]}
 * @param {Map<string,{hvac_mode:string,target_temperature:number}>} assumed  état supposé des clims IR
 * @param {Map<string,Record<string,object>>} [profiles]  uniqueId -> {appareil: télécommande de clim de la bibliothèque}
 */
export function addBroadlink(list, remotes, learned, assumed, profiles = new Map()) {
  for (const r of remotes) {
    const hubId = r.deviceId ? `device:${r.deviceId}` : `entity:${r.entityId}`;
    let hub = list.find((d) => d.externalId === hubId);
    if (!hub) {
      hub = { externalId: hubId, name: r.name ?? 'Broadlink', vendor: 'Broadlink', model: r.model ?? null, protocol: 'wifi', connectionSource: 'local', isSensitive: false, capabilities: [], capMap: {} };
      list.push(hub);
    }
    hub.protocol = 'wifi';
    hub.connectionSource = 'local';
    const codes = learned.get(r.uniqueId) ?? {};
    const chosen = profiles.get(r.uniqueId) ?? {};
    const tempKey = Object.keys(hub.capMap).find((k) => hub.capMap[k].base === 'temperature');
    hub.capMap.ir_learn = { entityId: r.entityId, base: 'ir_learn', uniqueId: r.uniqueId, read: () => null };
    hub.capabilities.push({
      capability_key: 'ir_learn', type: 'string', writable: true,
      metadata: { kind: 'ir_learn', learned: codes, profiles: Object.fromEntries(Object.entries(chosen).map(([k, p]) => [k, p.id])) },
    });

    const subs = [...new Set([...Object.keys(codes), ...Object.keys(chosen)])];
    for (const sub of subs) {
      const commands = codes[sub] ?? [];
      const profile = chosen[sub];
      const externalId = `${hubId}:ir:${sub}`;
      const dev = {
        externalId,
        name: irDeviceName(sub),
        vendor: 'Broadlink',
        model: 'Télécommande infrarouge',
        protocol: 'wifi',
        connectionSource: 'local',
        isSensitive: false,
        capabilities: [],
        capMap: {},
        hubId,
      };
      const climate = profile ? null : irClimate(commands);
      if (profile) {
        // Clim de la bibliothèque : tous ses modes, températures et vitesses, sans rien apprendre.
        const st = assumed.get(externalId) ?? profileDefaults(profile);
        assumed.set(externalId, st);
        const entry = (key) => ({ entityId: r.entityId, base: 'ir_profile', key, sub, profile, read: () => st[key] });
        dev.model = `${profile.brand} ${profile.models[0] ?? ''}`.trim();
        dev.capMap.hvac_mode = entry('hvac_mode');
        dev.capMap.target_temperature = entry('target_temperature');
        dev.capabilities.push(
          { capability_key: 'hvac_mode', type: 'enum', writable: true, metadata: { options: ['off', ...profile.modes], assumed: true } },
          { capability_key: 'target_temperature', type: 'number', writable: true, metadata: { min: profile.min, max: profile.max, step: profile.step, unit: '°C', assumed: true } },
        );
        if (profile.fans.length) {
          dev.capMap.fan_mode = entry('fan_mode');
          dev.capabilities.push({ capability_key: 'fan_mode', type: 'enum', writable: true, metadata: { options: profile.fans, assumed: true } });
        }
        if (profile.swings.length) {
          dev.capMap.swing_mode = entry('swing_mode');
          dev.capabilities.push({ capability_key: 'swing_mode', type: 'enum', writable: true, metadata: { options: profile.swings, assumed: true } });
        }
        if (tempKey) {
          dev.capMap.current_temperature = { ...hub.capMap[tempKey], base: 'current_temperature' };
          dev.capabilities.push({ capability_key: 'current_temperature', type: 'sensor', writable: false, metadata: { unit: '°C' } });
        }
      } else if (climate) {
        const st = assumed.get(externalId) ?? { hvac_mode: 'off', target_temperature: Math.min(Math.max(22, climate.min), climate.max) };
        assumed.set(externalId, st);
        const steps = Object.values(climate.temps).flat();
        const half = steps.some((t) => !Number.isInteger(t));
        dev.capMap.hvac_mode = { entityId: r.entityId, base: 'ir_hvac_mode', sub, climate, commands, read: () => st.hvac_mode };
        dev.capMap.target_temperature = { entityId: r.entityId, base: 'ir_target_temperature', sub, climate, commands, read: () => st.target_temperature };
        dev.capabilities.push(
          { capability_key: 'hvac_mode', type: 'enum', writable: true, metadata: { options: ['off', ...climate.modes], assumed: true } },
          { capability_key: 'target_temperature', type: 'number', writable: true, metadata: { min: climate.min, max: climate.max, step: half ? 0.5 : 1, unit: '°C', assumed: true } },
        );
        // Le capteur du Broadlink sert de température de la pièce (préchauffage, ambiances).
        if (tempKey) {
          dev.capMap.current_temperature = { ...hub.capMap[tempKey], base: 'current_temperature' };
          dev.capabilities.push({ capability_key: 'current_temperature', type: 'sensor', writable: false, metadata: { unit: '°C' } });
        }
      }
      const others = climate || profile ? commands.filter((c) => c !== 'off' && !MODE_TEMP.test(c) && !IR_MODES.includes(c)) : commands;
      if (others.length) {
        dev.capMap.ir_command = { entityId: r.entityId, base: 'ir_command', sub, read: () => null };
        dev.capabilities.push({ capability_key: 'ir_command', type: 'enum', writable: true, metadata: { options: others, kind: 'ir_command' } });
      }
      if (dev.capabilities.length) list.push(dev);
    }
  }
  return list;
}

/**
 * Appel de service HA d'une commande infrarouge, et état supposé après succès.
 * @returns {{call?:{domain,service,target,data}, error?:string, after?:()=>void, learn?:{device,command,action}}}
 */
export function irServiceCall(entry, value, assumed, externalId) {
  const target = { entity_id: entry.entityId };
  switch (entry.base) {
    case 'ir_command':
      return { call: { domain: 'remote', service: 'send_command', target, data: { device: entry.sub, command: value } } };
    case 'ir_hvac_mode':
    case 'ir_target_temperature': {
      const st = assumed.get(externalId);
      const mode = entry.base === 'ir_hvac_mode' ? value : st.hvac_mode;
      const target_temperature = entry.base === 'ir_target_temperature' ? value : st.target_temperature;
      const after = () => Object.assign(st, { hvac_mode: mode, target_temperature });
      // Clim éteinte : la nouvelle consigne est retenue pour le prochain allumage, sans rien envoyer.
      if (entry.base === 'ir_target_temperature' && mode === 'off') return { after };
      const command = climateCommand(entry.climate, entry.commands, mode, target_temperature);
      if (!command) return { error: `Touche « ${mode} » non apprise pour cette clim` };
      return { call: { domain: 'remote', service: 'send_command', target, data: { device: entry.sub, command } }, after };
    }
    case 'ir_profile': {
      const st = assumed.get(externalId);
      const next = { ...st, [entry.key]: value };
      const after = () => Object.assign(st, next);
      // Clim éteinte : le réglage est retenu pour le prochain allumage, sans rien envoyer.
      if (entry.key !== 'hvac_mode' && st.hvac_mode === 'off') return { after };
      const codes = profileCodes(entry.profile, next);
      if (!codes) return { error: 'Réglage absent de cette télécommande' };
      // Certaines clims veulent d'abord « marche » quand elles sont éteintes.
      const on = entry.key === 'hvac_mode' && st.hvac_mode === 'off' && value !== 'off' ? asCodes(entry.profile.commands.on) ?? [] : [];
      return { call: { domain: 'remote', service: 'send_command', target, data: { command: [...on, ...codes].map((c) => `b64:${c}`) } }, after };
    }
    case 'ir_learn': {
      const action = value.action ?? 'learn';
      const data = { device: value.device.trim(), command: value.command.trim() };
      if (action === 'delete') return { call: { domain: 'remote', service: 'delete_command', target, data }, learn: { ...data, action } };
      return {
        call: { domain: 'remote', service: 'learn_command', target, data: { ...data, command_type: 'ir' } },
        learn: { ...data, action },
      };
    }
    default:
      return { error: 'Commande non prise en charge' };
  }
}

/** Choix d'une télécommande de clim de la bibliothèque : essai, choix, retrait. */
export const PROFILE_ACTIONS = ['profile_test', 'profile_set', 'profile_clear'];

/**
 * Demande d'apprentissage : {device, command, action?: 'learn'|'delete'},
 * ou télécommande de clim : {action: 'profile_test', profile, mode?: 'cool'|'off'},
 * {action: 'profile_set', device, profile}, {action: 'profile_clear', device}.
 */
export function validateIrLearn(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return 'Demande d\'apprentissage invalide';
  if (Object.keys(value).some((k) => !['device', 'command', 'action', 'profile', 'mode'].includes(k))) return 'Demande d\'apprentissage invalide';
  if (value.action != null && !['learn', 'delete', ...PROFILE_ACTIONS].includes(value.action)) return 'Action non prise en charge';
  if (PROFILE_ACTIONS.includes(value.action)) {
    if (value.action !== 'profile_clear' && !CLIMATE_PROFILES.has(value.profile)) return 'Télécommande de clim inconnue';
    if (value.action === 'profile_test' && value.mode != null && !['cool', 'off'].includes(value.mode)) return 'Essai non pris en charge';
    if (value.action !== 'profile_test' && !validIrName(value.device)) return 'Nom de l\'appareil invalide (lettres, chiffres, 40 caractères au plus)';
    return null;
  }
  if (!validIrName(value.device)) return 'Nom de l\'appareil invalide (lettres, chiffres, 40 caractères au plus)';
  if (!validIrName(value.command)) return 'Nom de la touche invalide (lettres, chiffres, 40 caractères au plus)';
  return null;
}
