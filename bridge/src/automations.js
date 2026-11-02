import { weatherMetric } from './weather.js';

// Évaluation des automatisations (format JSON défini dans la migration Supabase, §5.9).
//   trigger    : {type:"manual"} | {type:"time", at:"07:30", days:[1..7]} (ISO, 1 = lundi)
//              | {type:"device_state", device_id, capability_key, op, value}
//   conditions : [{type:"device_state",…} | {type:"time_range", from:"22:00", to:"06:00"}]
//              | {type:"weather", metric, op, value, for_minutes}   (météo lue par la passerelle)
//              | {type:"sun", event:"sunrise"|"sunset", offset_minutes}
//   conditions : … | {type:"weather", metric, op, value} | {type:"sun", is:"night"|"day"}
//   exceptions : « SAUF SI » : mêmes formes que les conditions ; une seule vraie suffit à bloquer
//   actions    : [{device_id, capability_key, value} | {scene_id}]
//   follow_up  : « PUIS » {after_minutes, actions, conditions, restart_on_trigger}

const WEEKDAYS = { Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 };

/** Heure locale de la maison : { hhmm: "07:30", minutes: 450, weekday: 1..7, key: "2026-10-26T07:30" } */
export function localTime(date, timeZone) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-GB', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      weekday: 'short',
      hourCycle: 'h23',
    })
      .formatToParts(date)
      .map((p) => [p.type, p.value]),
  );
  const hhmm = `${parts.hour}:${parts.minute}`;
  return {
    hhmm,
    minutes: Number(parts.hour) * 60 + Number(parts.minute),
    weekday: WEEKDAYS[parts.weekday],
    key: `${parts.year}-${parts.month}-${parts.day}T${hhmm}`,
  };
}

function toMinutes(hhmm) {
  const [h, m] = String(hhmm).split(':').map(Number);
  return h * 60 + (m || 0);
}

export function compare(op, actual, expected) {
  if (actual === undefined || actual === null) return false;
  switch (op ?? 'eq') {
    case 'eq':
      return typeof expected === 'number' ? Number(actual) === expected : actual === expected;
    case 'ne':
      return typeof expected === 'number' ? Number(actual) !== expected : actual !== expected;
    case 'gt':
      return Number(actual) > Number(expected);
    case 'lt':
      return Number(actual) < Number(expected);
    default:
      return false;
  }
}

export function inTimeRange(minutes, from, to) {
  const a = toMinutes(from);
  const b = toMinutes(to);
  return a <= b ? minutes >= a && minutes < b : minutes >= a || minutes < b; // plage de nuit
}

/** Déclencheur horaire : vrai à la minute exacte, les jours choisis. */
export function timeTriggerDue(trigger, now) {
  if (trigger?.type !== 'time') return false;
  const days = Array.isArray(trigger.days) && trigger.days.length ? trigger.days : [1, 2, 3, 4, 5, 6, 7];
  return now.hhmm === trigger.at && days.includes(now.weekday);
}

/** Déclencheur d'état : vrai sur la transition (ne correspondait pas → correspond). */
export function stateTriggerFired(trigger, deviceId, before, after) {
  if (trigger?.type !== 'device_state' || trigger.device_id !== deviceId) return false;
  const key = trigger.capability_key;
  return !compare(trigger.op, before?.[key], trigger.value) && compare(trigger.op, after?.[key], trigger.value);
}

/** Il fait nuit : d'après la météo (is_day) ou les heures du soleil du jour. */
export function isNight(ctx, date) {
  const w = ctx?.weather;
  if (w?.sunrise instanceof Date && w?.sunset instanceof Date) {
    const t = date.getTime();
    return t < w.sunrise.getTime() || t >= w.sunset.getTime();
  }
  if (typeof w?.is_day === 'boolean') return !w.is_day;
  return null; // inconnu
}

function conditionHolds(c, states, now, ctx) {
  switch (c?.type) {
    case 'time_range':
      return inTimeRange(now.minutes, c.from, c.to);
    case 'device_state':
      return compare(c.op, states[c.device_id]?.[c.capability_key], c.value);
    case 'weather':
      return compare(c.op, weatherMetric(ctx?.weather, c.metric), c.value);
    case 'sun': {
      const night = isNight(ctx, ctx?.date ?? new Date());
      if (night === null) return false;
      return c.is === 'night' ? night : !night;
    }
    case 'mode':
      return Array.isArray(ctx?.modes) && ctx.modes.includes(c.mode);
    default:
      return false; // type inconnu : prudence
  }
}

/**
 * Conditions (toutes vraies). `states` : { deviceId: state }.
 * `ctx` : { weather, date, modes } pour les conditions météo, soleil et mode.
 */
export function conditionsHold(conditions, states, now, ctx = {}) {
  for (const c of conditions ?? []) {
    if (!conditionHolds(c, states, now, ctx)) return false;
  }
  return true;
}

/** « SAUF SI » : vrai si au moins une exception est vraie (l'automatisation ne s'exécute pas). */
export function exceptionHolds(exceptions, states, now, ctx = {}) {
  return (exceptions ?? []).some((c) => conditionHolds(c, states, now, ctx));
}

/** Déclencheur météo : la mesure dépasse le seuil (sans le délai de confirmation). */
export function weatherTriggerHolds(trigger, weather) {
  if (trigger?.type !== 'weather') return false;
  return compare(trigger.op ?? 'gt', weatherMetric(weather, trigger.metric), trigger.value);
}

/** Déclencheur soleil : vrai à la minute du lever / coucher (+ décalage) du jour. */
export function sunTriggerDue(trigger, now, weather, timeZone) {
  if (trigger?.type !== 'sun') return false;
  const base = trigger.event === 'sunrise' ? weather?.sunrise : weather?.sunset;
  if (!(base instanceof Date)) return false;
  const at = new Date(base.getTime() + (Number(trigger.offset_minutes) || 0) * 60_000);
  return localTime(at, timeZone).key === now.key;
}

/** Nombre de volets fermés par une liste d'actions (notification « volets fermés »). */
export function closedCovers(actions) {
  return (actions ?? []).filter(
    (a) =>
      (a.capability_key === 'cover_position' && Number(a.value) === 0) ||
      (a.capability_key === 'cover_control' && a.value === 'close'),
  ).length;
}

/** Modes actifs d'après le réglage du logement : 'summer' | 'winter', 'vacation' (entre les dates). */
export function activeModes(row, date) {
  if (!row) return [];
  const modes = [];
  if (row.season === 'summer' || row.season === 'winter') modes.push(row.season);
  if (row.vacation) {
    const t = date.getTime();
    const from = row.vacation_from ? Date.parse(row.vacation_from) : null;
    const to = row.vacation_to ? Date.parse(row.vacation_to) : null;
    if ((from == null || t >= from) && (to == null || t < to)) modes.push('vacation');
  }
  return modes;
}

/** Déclencheur de mode : vrai quand le mode commence (start) ou se termine (end). */
export function modeTriggerFired(trigger, before, after) {
  if (trigger?.type !== 'mode') return false;
  const was = before.includes(trigger.mode);
  const is = after.includes(trigger.mode);
  return trigger.event === 'end' ? was && !is : !was && is;
}

/**
 * Plan de simulation de présence pour une soirée : chaque lumière s'allume à une
 * heure tirée au hasard entre `startMin` et 22 h, pour 20 à 90 minutes, et tout
 * est éteint à 23 h 30 au plus tard. Minutes depuis minuit, heure du logement.
 */
export function presencePlan(deviceIds, startMin, random = Math.random) {
  const end = 23 * 60 + 30;
  const latestOn = Math.max(startMin, 22 * 60);
  return deviceIds.map((id) => {
    const on = Math.round(startMin + random() * (latestOn - startMin));
    const off = Math.min(end, on + 20 + Math.round(random() * 70));
    return { id, on, off };
  });
}
