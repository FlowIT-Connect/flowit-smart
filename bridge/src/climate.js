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
