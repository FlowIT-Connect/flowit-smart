// Chauffage et climatisation par pièce (fonctions pures, testées).
//
// Ambiance d'une pièce : dérogation de la pièce > ambiance de la maison > Vacances (Absence)
// > programme de la semaine. Hiver = chauffage, Été = climatisation, sinon le mode en cours
// de chaque appareil décide (une clim en froid reçoit la consigne « froid »).

export const PRESETS = ['comfort', 'eco', 'sleep', 'away', 'frost'];

export const DEFAULT_PRESETS = {
  comfort: { heat: 21, cool: 24 },
  eco: { heat: 19, cool: 27 },
  sleep: { heat: 18, cool: 26 },
  away: { heat: 16, cool: 29 },
  frost: { heat: 7, cool: null },
};

const valid = (until, now) => !until || new Date(until).getTime() > now.getTime();
const toMinutes = (hhmm) => Number(hhmm.slice(0, 2)) * 60 + Number(hhmm.slice(3, 5));

/**
 * Ambiance du programme à un instant : la dernière plage commencée, en remontant jusqu'à 7 jours.
 * @param {Array<{days:number[],at:string,preset:string}>} schedule
 * @param {{weekday:number, minutes:number}} now heure locale (1 = lundi)
 */
export function scheduledPreset(schedule, now) {
  const entries = (Array.isArray(schedule) ? schedule : []).filter(
    (e) => PRESETS.includes(e?.preset) && /^\d\d:\d\d$/.test(e?.at ?? '') && Array.isArray(e?.days),
  );
  if (!entries.length) return null;
  for (let back = 0; back < 8; back++) {
    const day = ((now.weekday - 1 - back + 70) % 7) + 1;
    const limit = back === 0 ? now.minutes : 24 * 60;
    const today = entries
      .filter((e) => e.days.includes(day) && toMinutes(e.at) <= limit)
      .sort((a, b) => toMinutes(a.at) - toMinutes(b.at));
    if (today.length) return today[today.length - 1].preset;
  }
  return null;
}

/**
 * Ambiance d'une zone et sa raison.
 * @returns {{preset:string, source:'room'|'home'|'vacation'|'schedule'|'default'}}
 */
export function effectivePreset(zone, settings, modes, now, local) {
  if (zone.preset_override && PRESETS.includes(zone.preset_override) && valid(zone.override_until, now)) {
    return { preset: zone.preset_override, source: 'room' };
  }
  if (settings?.home_preset && PRESETS.includes(settings.home_preset) && valid(settings.home_preset_until, now)) {
    return { preset: settings.home_preset, source: 'home' };
  }
  if (modes.includes('vacation')) return { preset: 'away', source: 'vacation' };
  const scheduled = scheduledPreset(zone.schedule, local);
  if (scheduled) return { preset: scheduled, source: 'schedule' };
  return { preset: 'comfort', source: 'default' };
}

/** Température d'une ambiance en chauffage (« heat ») ou en climatisation (« cool »). */
export function presetTemperature(presets, preset, kind) {
  const p = presets?.[preset] ?? DEFAULT_PRESETS[preset];
  const v = p?.[kind];
  return typeof v === 'number' && Number.isFinite(v) ? v : null;
}

/** Saison du logement → mode voulu (null : on garde le mode de chaque appareil). */
export function seasonMode(modes) {
  if (modes.includes('winter')) return 'heat';
  if (modes.includes('summer')) return 'cool';
  return null;
}

function clampToCap(value, cap) {
  const m = cap?.metadata ?? {};
  let v = value;
  if (typeof m.min === 'number') v = Math.max(m.min, v);
  if (typeof m.max === 'number') v = Math.min(m.max, v);
  const step = typeof m.step === 'number' && m.step > 0 ? m.step : 0.5;
  const base = typeof m.min === 'number' ? m.min : 0;
  return Math.round((Math.round((v - base) / step) * step + base) * 100) / 100;
}

/**
 * Commandes qui mettent un appareil dans l'ambiance voulue (rien si déjà fait).
 * @param {{caps: Map<string, any>, state: object, availability?: string}} device
 * @returns {{commands: Array<{capability_key:string, value:any}>, target: number|null}}
 */
export function deviceCommands(device, presets, preset, mode) {
  const caps = device.caps;
  const tempCap = caps.get('target_temperature');
  const modeCap = caps.get('hvac_mode');
  if (!tempCap?.writable) return { commands: [], target: null };
  const options = modeCap?.writable ? modeCap.metadata?.options ?? [] : [];
  const current = device.state?.hvac_mode;
  // Saison que l'appareil ne sait pas faire (ex. Hiver, clim sans mode Chaud) : on n'y touche
  // pas, plutôt que de changer une consigne qui ne chauffera jamais.
  if (mode && options.length && !options.includes(mode)) return { commands: [], target: null };
  // Sans saison : une clim en froid suit la consigne « froid », le reste la consigne « chaud ».
  const kind = mode ?? (current === 'cool' ? 'cool' : 'heat');
  const t = presetTemperature(presets, preset, kind);
  const commands = [];
  if (t == null) {
    // Ex. Hors-gel en été : rien à rafraîchir, on arrête si possible.
    if (options.includes('off') && current !== 'off') commands.push({ capability_key: 'hvac_mode', value: 'off' });
    return { commands, target: null };
  }
  if (mode && options.includes(mode) && current !== mode) commands.push({ capability_key: 'hvac_mode', value: mode });
  const target = clampToCap(t, tempCap);
  if (device.state?.target_temperature !== target) commands.push({ capability_key: 'target_temperature', value: target });
  return { commands, target };
}

// ------------------------------------------------------------------ Fenêtre ouverte (phase 3)

/**
 * Une fenêtre de la pièce est-elle ouverte ? Capteurs d'ouverture associés (contact false =
 * ouvert) ou tête thermostatique qui le détecte elle-même (window_open true).
 * @returns {string|null} l'appareil qui signale l'ouverture, sinon null
 */
export function openWindow(zone, devices) {
  for (const id of zone.windows ?? []) {
    const s = devices.get(id)?.state;
    if (s?.contact === false || s?.window_open === true) return id;
  }
  for (const id of zone.devices ?? []) {
    if (devices.get(id)?.state?.window_open === true) return id;
  }
  return null;
}

/**
 * Commandes qui coupent un appareil pendant que la fenêtre est ouverte : arrêt par son mode
 * (jamais par l'alimentation électrique), sinon consigne Hors-gel.
 */
export function windowOffCommands(device, presets) {
  const modeCap = device.caps.get('hvac_mode');
  const options = modeCap?.writable ? modeCap.metadata?.options ?? [] : [];
  if (options.includes('off')) {
    return device.state?.hvac_mode === 'off' ? [] : [{ capability_key: 'hvac_mode', value: 'off' }];
  }
  const tempCap = device.caps.get('target_temperature');
  const frost = presetTemperature(presets, 'frost', 'heat') ?? DEFAULT_PRESETS.frost.heat;
  if (!tempCap?.writable) return [];
  const target = clampToCap(frost, tempCap);
  return device.state?.target_temperature === target ? [] : [{ capability_key: 'target_temperature', value: target }];
}

/**
 * Remet en marche un appareil coupé pour fenêtre ouverte, dans le mode qu'il avait
 * (ou celui de la saison s'il n'est plus connu). La consigne est remise par l'ambiance.
 */
export function windowRestoreCommands(device, savedMode, season) {
  const modeCap = device.caps.get('hvac_mode');
  const options = modeCap?.writable ? modeCap.metadata?.options ?? [] : [];
  if (device.state?.hvac_mode !== 'off') return [];
  const mode = savedMode && savedMode !== 'off' ? savedMode : season;
  return mode && options.includes(mode) ? [{ capability_key: 'hvac_mode', value: mode }] : [];
}

// ------------------------------------------------------------------ Températures intelligentes (phase 4)

/** Température mesurée dans la pièce : le premier appareil qui en donne une. */
export function zoneTemperature(zone, devices) {
  for (const id of zone.devices ?? []) {
    const s = devices.get(id)?.state ?? {};
    const v = s.current_temperature ?? s.temperature;
    if (typeof v === 'number' && Number.isFinite(v)) return v;
  }
  return null;
}

/** Chauffage ou clim pour la pièce : la saison, sinon une clim déjà en froid. */
export function zoneKind(zone, devices, season) {
  if (season) return season;
  return (zone.devices ?? []).some((id) => devices.get(id)?.state?.hvac_mode === 'cool') ? 'cool' : 'heat';
}

/** Marge météo : plus long quand il gèle dehors (ou fait très chaud en clim). */
export function weatherFactor(kind, outdoor) {
  if (typeof outdoor !== 'number') return 1;
  if (kind === 'cool') return outdoor >= 38 ? 1.5 : outdoor >= 32 ? 1.25 : 1;
  return outdoor < 0 ? 1.5 : outdoor < 8 ? 1.25 : 1;
}

export const DEFAULT_RATES = { heat: 15, cool: 10 };

/**
 * Minutes pour amener la pièce de measured à target. [rate] : minutes par degré apprises
 * pour la pièce (sinon 15 en chauffage, 10 en clim), puis la marge météo.
 */
export function warmupMinutes(measured, target, kind, outdoor, rate = null) {
  if (measured == null || target == null) return 0;
  const gap = kind === 'cool' ? measured - target : target - measured;
  if (!(gap > 0)) return 0;
  const base = typeof rate === 'number' && rate > 0 ? rate : DEFAULT_RATES[kind === 'cool' ? 'cool' : 'heat'];
  return Math.ceil(gap * base * weatherFactor(kind, outdoor));
}

const MAX_TRACK_MS = 8 * 3_600_000;

/**
 * Apprentissage : suit une montée en température (au moins 1 °C d'écart) jusqu'à la consigne
 * et en déduit les minutes par degré de la pièce, hors marge météo.
 * @returns {{track: object|null, rate?: number}}
 */
export function trackWarmup(track, { target, measured, kind, nowMs, outdoor }) {
  if (target == null || measured == null) return { track: null };
  const gap = kind === 'cool' ? measured - target : target - measured;
  let t = track && track.target === target && track.kind === kind ? track : null;
  if (!t) {
    return gap >= 1 ? { track: { target, kind, startMs: nowMs, startGap: gap, factor: weatherFactor(kind, outdoor) } } : { track: null };
  }
  const minutes = (nowMs - t.startMs) / 60_000;
  if (gap <= 0.2) {
    const degrees = t.startGap - Math.max(gap, 0);
    if (minutes < 5 || degrees < 0.8) return { track: null };
    const rate = minutes / degrees / t.factor;
    return { track: null, rate: Math.round(Math.min(60, Math.max(2, rate)) * 10) / 10 };
  }
  if (nowMs - t.startMs > MAX_TRACK_MS) return { track: null };
  return { track: t };
}

/** Moyenne glissante : la nouvelle mesure compte pour 30 %. */
export function blendRate(previous, measured) {
  const p = Number(previous);
  return Number.isFinite(p) && p > 0 ? Math.round((p * 0.7 + measured * 0.3) * 10) / 10 : measured;
}

const PREHEAT_STEP = 5;

/**
 * Ambiance à appliquer en tenant compte du préchauffage : si le prochain changement
 * (dans maxMinutes) demande plus de chaud (ou de froid) et que la pièce mettra au moins
 * ce temps à y arriver, on l'applique dès maintenant (source « preheat »). Un préchauffage
 * commencé ([ongoing]) continue jusqu'au changement, même si l'écart se réduit.
 */
export function anticipatedPreset({ zone, settings, modes, now, localAt, presets, kind, measured, outdoor, maxMinutes, ongoing = null, rate = null }) {
  const current = effectivePreset(zone, settings, modes, now, localAt(now));
  if (!(maxMinutes > 0) || (measured == null && !ongoing)) return current;
  const curT = presetTemperature(presets, current.preset, kind);
  for (let m = PREHEAT_STEP; m <= maxMinutes; m += PREHEAT_STEP) {
    const at = new Date(now.getTime() + m * 60_000);
    const next = effectivePreset(zone, settings, modes, at, localAt(at));
    if (next.preset === current.preset) continue;
    const t = presetTemperature(presets, next.preset, kind);
    const warmer = t != null && (curT == null || (kind === 'cool' ? t < curT : t > curT));
    if (!warmer) return current;
    if (ongoing === next.preset || warmupMinutes(measured, t, kind, outdoor, rate) >= m) return { preset: next.preset, source: 'preheat' };
    return current;
  }
  return current;
}

// ------------------------------------------------------------------ Absence automatique (géolocalisation)

export const GEO_LEAVE_DELAY_MS = 10 * 60_000;

/**
 * Absence automatique : « leave » quand tous les membres qui partagent leur présence sont
 * partis depuis 10 minutes (et qu'aucune ambiance n'a été choisie pour la maison),
 * « back » dès que l'un revient (ou que la fonction est coupée) si c'est la passerelle
 * qui avait mis l'Absence ; sinon null.
 */
export function geoDecision(settings, presence, nowMs) {
  if (!settings) return null;
  const rows = Array.isArray(presence) ? presence : [];
  if (settings.geo_away) {
    if (!settings.geo_enabled || rows.length === 0 || rows.some((p) => p.at_home)) return 'back';
    return null;
  }
  if (!settings.geo_enabled || rows.length === 0 || rows.some((p) => p.at_home)) return null;
  if (settings.home_preset && valid(settings.home_preset_until, new Date(nowMs))) return null; // choix fait à la main
  const lastLeft = Math.max(...rows.map((p) => new Date(p.since).getTime() || 0));
  return nowMs - lastLeft >= GEO_LEAVE_DELAY_MS ? 'leave' : null;
}
