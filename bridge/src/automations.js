// Évaluation des automatisations (format JSON défini dans la migration Supabase, §5.9).
//   trigger    : {type:"manual"} | {type:"time", at:"07:30", days:[1..7]} (ISO, 1 = lundi)
//              | {type:"device_state", device_id, capability_key, op, value}
//   conditions : [{type:"device_state",…} | {type:"time_range", from:"22:00", to:"06:00"}]
//   actions    : [{device_id, capability_key, value} | {scene_id}]

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

/** Conditions (toutes vraies). `states` : { deviceId: state }. */
export function conditionsHold(conditions, states, now) {
  for (const c of conditions ?? []) {
    if (c.type === 'time_range') {
      if (!inTimeRange(now.minutes, c.from, c.to)) return false;
    } else if (c.type === 'device_state') {
      if (!compare(c.op, states[c.device_id]?.[c.capability_key], c.value)) return false;
    } else {
      return false; // type inconnu : prudence
    }
  }
  return true;
}
