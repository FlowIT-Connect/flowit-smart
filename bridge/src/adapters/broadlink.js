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

import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

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
 */
export function addBroadlink(list, remotes, learned, assumed) {
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
    const tempKey = Object.keys(hub.capMap).find((k) => hub.capMap[k].base === 'temperature');
    hub.capMap.ir_learn = { entityId: r.entityId, base: 'ir_learn', uniqueId: r.uniqueId, read: () => null };
    hub.capabilities.push({
      capability_key: 'ir_learn', type: 'string', writable: true,
      metadata: { kind: 'ir_learn', learned: codes },
    });

    for (const [sub, commands] of Object.entries(codes)) {
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
      const climate = irClimate(commands);
      if (climate) {
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
      const others = climate ? commands.filter((c) => c !== 'off' && !MODE_TEMP.test(c) && !IR_MODES.includes(c)) : commands;
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

/** Demande d'apprentissage : {device, command, action?: 'learn'|'delete'}. */
export function validateIrLearn(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return 'Demande d\'apprentissage invalide';
  if (Object.keys(value).some((k) => !['device', 'command', 'action'].includes(k))) return 'Demande d\'apprentissage invalide';
  if (value.action != null && !['learn', 'delete'].includes(value.action)) return 'Action non prise en charge';
  if (!validIrName(value.device)) return 'Nom de l\'appareil invalide (lettres, chiffres, 40 caractères au plus)';
  if (!validIrName(value.command)) return 'Nom de la touche invalide (lettres, chiffres, 40 caractères au plus)';
  return null;
}
