import assert from 'node:assert/strict';
import { test } from 'node:test';

import { compare, conditionsHold, inTimeRange, localTime, stateTriggerFired, timeTriggerDue } from '../src/automations.js';
import { validateValue } from '../src/validate.js';

test('heure locale de la maison (fuseau Africa/Algiers, UTC+1)', () => {
  const t = localTime(new Date('2026-10-26T05:45:00Z'), 'Africa/Algiers');
  assert.equal(t.hhmm, '06:45');
  assert.equal(t.weekday, 1); // lundi
  assert.equal(t.key, '2026-10-26T06:45');
});

test('déclencheur horaire : jour et minute', () => {
  const now = { hhmm: '06:45', weekday: 1 };
  assert.equal(timeTriggerDue({ type: 'time', at: '06:45', days: [1, 2, 3, 4, 5] }, now), true);
  assert.equal(timeTriggerDue({ type: 'time', at: '06:45', days: [6, 7] }, now), false);
  assert.equal(timeTriggerDue({ type: 'time', at: '06:46' }, now), false);
});

test('déclencheur d\'état : seulement sur la transition', () => {
  const trig = { type: 'device_state', device_id: 'd', capability_key: 'contact', op: 'eq', value: false };
  assert.equal(stateTriggerFired(trig, 'd', { contact: true }, { contact: false }), true);
  assert.equal(stateTriggerFired(trig, 'd', { contact: false }, { contact: false }), false);
  assert.equal(stateTriggerFired(trig, 'autre', { contact: true }, { contact: false }), false);
  const temp = { type: 'device_state', device_id: 'd', capability_key: 'temperature', op: 'gt', value: 26 };
  assert.equal(stateTriggerFired(temp, 'd', { temperature: 25.9 }, { temperature: 26.4 }), true);
});

test('plage horaire de nuit et conditions', () => {
  assert.equal(inTimeRange(23 * 60, '22:00', '06:00'), true);
  assert.equal(inTimeRange(5 * 60, '22:00', '06:00'), true);
  assert.equal(inTimeRange(12 * 60, '22:00', '06:00'), false);
  const states = { d: { switch: true } };
  assert.equal(conditionsHold([{ type: 'device_state', device_id: 'd', capability_key: 'switch', op: 'eq', value: true }], states, { minutes: 0 }), true);
  assert.equal(conditionsHold([{ type: 'inconnu' }], states, { minutes: 0 }), false);
  assert.equal(compare('lt', undefined, 3), false);
});

test('validation des valeurs de commande (liste blanche)', () => {
  assert.equal(validateValue({ type: 'boolean', writable: true }, true), null);
  assert.match(validateValue({ type: 'boolean', writable: true }, 'on'), /booléenne/);
  assert.match(validateValue({ type: 'number', writable: true, metadata: { min: 1, max: 100 } }, 500), /maximum/);
  assert.match(validateValue({ type: 'enum', writable: true, metadata: { options: ['heat'] } }, 'cool'), /Option/);
  assert.equal(validateValue({ type: 'color', writable: true }, '#00FF00'), null);
  assert.match(validateValue({ type: 'sensor', writable: false }, 1), /lecture seule/);
  assert.match(validateValue(undefined, 1), /non prise en charge/);
});
