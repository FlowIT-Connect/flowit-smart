// Export des appareils Solea vers Home Assistant par MQTT (découverte automatique).
//
// Tout ce que voit la passerelle (robot yeedi, serrures TTLock, appareils Smart Life et
// leurs sous-appareils Zigbee…) apparaît dans Home Assistant, dans l'intégration MQTT,
// sans module complémentaire à écrire côté HA. Les ordres donnés depuis HA passent par la
// même exécution que ceux de l'application. Les appareils sensibles (serrures) restent en
// lecture seule dans HA : leur ouverture n'est possible que depuis Solea.

import { log } from './log.js';

/** Capacités qui n'ont pas d'équivalent simple dans HA (gérées depuis Solea). */
const SKIPPED = new Set(['vacuum_map', 'vacuum_clean', 'access_code', 'ekey', 'access_log', 'lock_action', 'color']);

const BINARY_CLASSES = { motion: 'occupancy', contact: 'door', smoke: 'smoke', water_leak: 'moisture', gas: 'gas', window_open: 'window' };
const SENSOR_CLASSES = {
  battery: ['battery', 'measurement'],
  temperature: ['temperature', 'measurement'],
  current_temperature: ['temperature', 'measurement'],
  humidity: ['humidity', 'measurement'],
  power: ['power', 'measurement'],
  energy: ['energy', 'total_increasing'],
  illuminance: ['illuminance', 'measurement'],
  target_distance: ['distance', 'measurement'],
};
const LABELS = {
  switch: 'Interrupteur', battery: 'Batterie', temperature: 'Température', current_temperature: 'Température',
  humidity: 'Humidité', power: 'Puissance', energy: 'Énergie', illuminance: 'Luminosité', motion: 'Présence',
  contact: 'Porte', smoke: 'Fumée', water_leak: 'Fuite d\'eau', gas: 'Gaz', window_open: 'Fenêtre ouverte',
  sensitivity: 'Sensibilité', detection_min: 'Distance minimale', detection_range: 'Distance maximale',
  target_distance: 'Distance de la personne', activity: 'Activité', water_level: 'Débit d\'eau',
  vacuum_error: 'Erreur', lock_state: 'Serrure', brightness: 'Luminosité', color_temp: 'Température de couleur',
  target_temperature: 'Consigne', hvac_mode: 'Mode', preset: 'Préréglage', fan_mode: 'Ventilation',
  hvac_action: 'Activité', last_access: 'Dernière ouverture',
};
/** États Solea du robot → états d'un aspirateur dans HA. */
const VACUUM_STATES = { cleaning: 'cleaning', charging: 'docked', returning: 'returning', paused: 'paused', idle: 'idle', error: 'error' };
const VACUUM_COMMANDS = { start: 'start', pause: 'pause', stop: 'stop', return_to_base: 'charge' };
const COVER_COMMANDS = { OPEN: 'open', CLOSE: 'close', STOP: 'stop' };

const slug = (s) => String(s).replace(/[^a-zA-Z0-9_]/g, '');

/**
 * Entités Home Assistant d'un appareil Solea.
 * @returns {Array<{component:string, key:string, config:object, state?:(st:object)=>string|null}>}
 */
export function entitiesFor(dev, base) {
  const t = (key, what) => `${base}/${dev.id}/${key}/${what}`;
  const caps = dev.caps;
  const out = [];
  const used = new Set();

  if (caps.has('vacuum_action')) {
    const suction = caps.get('suction');
    out.push({
      component: 'vacuum',
      key: 'vacuum',
      config: {
        name: null,
        schema: 'state',
        command_topic: t('vacuum', 'set'),
        state_topic: t('vacuum', 'state'),
        supported_features: ['start', 'pause', 'stop', 'return_home', 'status', ...(suction ? ['fan_speed'] : [])],
        ...(suction ? { fan_speed_list: suction.metadata?.options ?? [], set_fan_speed_topic: t('suction', 'set') } : {}),
      },
      state: (st) =>
        JSON.stringify({
          state: VACUUM_STATES[st.vacuum_state] ?? (st.vacuum_error ? 'error' : 'idle'),
          ...(st.suction ? { fan_speed: st.suction } : {}),
        }),
    });
    used.add('vacuum_action').add('vacuum_state').add('suction');
  }

  if (caps.has('cover_control') || caps.has('cover_position')) {
    const control = caps.get('cover_control');
    const position = caps.get('cover_position');
    out.push({
      component: 'cover',
      key: 'cover',
      config: {
        name: null,
        device_class: 'curtain',
        ...(control || position?.writable ? { command_topic: t('cover', 'set') } : {}),
        ...(control && !(control.metadata?.options ?? []).includes('stop') ? { payload_stop: null } : {}),
        ...(position ? { position_topic: t('cover_position', 'state'), ...(position.writable ? { set_position_topic: t('cover_position', 'set') } : {}) } : {}),
        ...(!position ? { optimistic: true } : {}),
      },
      state: () => null,
    });
    if (position) out.push({ component: null, key: 'cover_position', state: (st) => (st.cover_position == null ? null : String(st.cover_position)) });
    used.add('cover_control').add('cover_position');
  }

  for (const [key, cap] of caps) {
    if (used.has(key) || SKIPPED.has(key)) continue;
    const md = cap.metadata ?? {};
    const name = LABELS[key] ?? key.replace(/_/g, ' ');
    const stateTopic = t(key, 'state');
    if (cap.type === 'boolean' && cap.writable) {
      out.push({ component: 'switch', key, config: { name: key === 'switch' ? null : name, command_topic: t(key, 'set'), state_topic: stateTopic }, state: onOff(key) });
    } else if (cap.type === 'sensor' && md.kind === 'binary') {
      out.push({ component: 'binary_sensor', key, config: { name, state_topic: stateTopic, ...(BINARY_CLASSES[key] ? { device_class: BINARY_CLASSES[key] } : {}) }, state: onOff(key) });
    } else if (cap.type === 'number' && cap.writable) {
      out.push({
        component: 'number',
        key,
        config: {
          name, command_topic: t(key, 'set'), state_topic: stateTopic,
          ...(md.min != null ? { min: md.min } : {}), ...(md.max != null ? { max: md.max } : {}),
          ...(md.step != null ? { step: md.step } : {}), ...(md.unit ? { unit_of_measurement: md.unit } : {}),
          ...(md.setting ? { entity_category: 'config' } : {}),
        },
        state: plain(key),
      });
    } else if (cap.type === 'enum' && cap.writable && (md.options ?? []).length) {
      out.push({ component: 'select', key, config: { name, command_topic: t(key, 'set'), state_topic: stateTopic, options: md.options.map(String), ...(md.setting ? { entity_category: 'config' } : {}) }, state: plain(key) });
    } else if (cap.type === 'sensor' || cap.type === 'enum' || (!cap.writable && ['number', 'string', 'boolean'].includes(cap.type))) {
      const [device_class, state_class] = md.unit ? (SENSOR_CLASSES[key] ?? [null, 'measurement']) : [null, null];
      out.push({
        component: 'sensor',
        key,
        config: {
          name, state_topic: stateTopic,
          ...(md.unit ? { unit_of_measurement: md.unit } : {}),
          ...(device_class ? { device_class } : {}), ...(state_class ? { state_class } : {}),
          ...(key === 'battery' || key === 'vacuum_error' ? { entity_category: 'diagnostic' } : {}),
        },
        state: plain(key),
      });
    }
  }

  // Serrures : dernière ouverture lue dans l'historique (aucune commande depuis HA).
  if (caps.has('access_log')) {
    out.push({
      component: 'sensor',
      key: 'last_access',
      config: { name: LABELS.last_access, state_topic: t('last_access', 'state'), device_class: 'timestamp' },
      state: (st) => (Array.isArray(st.access_log) && st.access_log[0]?.at ? st.access_log[0].at : null),
    });
  }
  return out;
}

function onOff(key) {
  return (st) => (typeof st[key] === 'boolean' ? (st[key] ? 'ON' : 'OFF') : null);
}
function plain(key) {
  return (st) => {
    const v = st[key];
    if (v == null || typeof v === 'object') return null;
    return String(v);
  };
}

/** Valeur Solea d'un ordre reçu de Home Assistant (null : ordre ignoré). */
export function commandFromHa(dev, key, payload) {
  const p = String(payload).trim();
  if (key === 'vacuum') return VACUUM_COMMANDS[p] ? { key: 'vacuum_action', value: VACUUM_COMMANDS[p] } : null;
  if (key === 'cover') {
    if (COVER_COMMANDS[p] && dev.caps.has('cover_control')) return { key: 'cover_control', value: COVER_COMMANDS[p] };
    if (dev.caps.has('cover_position') && (p === 'OPEN' || p === 'CLOSE')) return { key: 'cover_position', value: p === 'OPEN' ? 100 : 0 };
    return null;
  }
  const cap = dev.caps.get(key);
  if (!cap?.writable) return null;
  if (cap.type === 'boolean') return p === 'ON' ? { key, value: true } : p === 'OFF' ? { key, value: false } : null;
  if (cap.type === 'number') return Number.isFinite(Number(p)) && p !== '' ? { key, value: Number(p) } : null;
  if (cap.type === 'enum') return { key, value: p };
  return null;
}

export class HaExporter {
  /**
   * @param {{client:import('./mqtt_client.js').MqttClient, prefix?:string, base?:string,
   *          devices:()=>Iterable<[string, any]>, execute:(deviceId:string, key:string, value:any)=>Promise<any>}} deps
   */
  constructor({ client, prefix = 'homeassistant', base = 'solea', devices, execute }) {
    Object.assign(this, { client, prefix, base, listDevices: devices, execute });
    this.status = `${base}/bridge/status`;
    this.configs = new Map(); // topic de config -> JSON publié
    this.states = new Map(); // topic d'état -> dernière valeur publiée
    this.entities = new Map(); // deviceId -> entités
  }

  start() {
    this.client.on('connect', () => {
      this.client.publish(this.status, 'online', { retain: true });
      this.configs.clear();
      this.states.clear();
      this.inventory();
    });
    this.client.on('message', (topic, payload) => this.#onMessage(topic, payload).catch((e) => log.error('ha_mqtt.command_failed', { error: e.message })));
    // Home Assistant redémarré : il redemande les configurations.
    this.client.subscribe(`${this.prefix}/status`);
    this.client.subscribe(`${this.base}/+/+/set`);
    this.client.start();
  }

  stop() {
    this.client.publish(this.status, 'offline', { retain: true });
    this.client.stop();
  }

  /** Publie (ou retire) les appareils après chaque inventaire de la passerelle. */
  inventory() {
    if (!this.client.connected) return;
    const live = new Set();
    let count = 0;
    for (const [id, dev] of this.listDevices()) {
      const entities = entitiesFor({ ...dev, id }, this.base);
      this.entities.set(id, entities);
      const device = {
        identifiers: [`solea_${id}`],
        name: String(dev.name ?? 'Appareil Solea').trim(),
        manufacturer: dev.vendor ?? 'Solea',
        ...(dev.model ? { model: dev.model } : {}),
      };
      for (const e of entities) {
        if (!e.component) continue;
        const topic = `${this.prefix}/${e.component}/solea_${slug(id)}/${e.key}/config`;
        live.add(topic);
        const config = {
          ...e.config,
          unique_id: `solea_${slug(id)}_${e.key}`,
          object_id: `solea_${slug(device.name.toLowerCase().replace(/\s+/g, '_'))}_${e.key}`,
          availability: [{ topic: this.status }, { topic: `${this.base}/${id}/availability` }],
          availability_mode: 'all',
          device,
          origin: { name: 'Solea' },
        };
        const json = JSON.stringify(config);
        if (this.configs.get(topic) !== json) this.client.publish(topic, json, { retain: true });
        this.configs.set(topic, json);
      }
      count++;
      this.state(id);
    }
    for (const topic of [...this.configs.keys()]) {
      if (!live.has(topic)) {
        this.client.publish(topic, '', { retain: true }); // appareil disparu : retiré de HA
        this.configs.delete(topic);
      }
    }
    log.info('ha_mqtt.published', { devices: count, entities: live.size });
  }

  /** Publie l'état courant d'un appareil (seulement ce qui a changé). */
  state(deviceId) {
    if (!this.client.connected) return;
    const dev = new Map(this.listDevices()).get(deviceId);
    if (!dev) return;
    const entities = this.entities.get(deviceId) ?? entitiesFor({ ...dev, id: deviceId }, this.base);
    this.#put(`${this.base}/${deviceId}/availability`, dev.availability === 'available' ? 'online' : 'offline');
    for (const e of entities) {
      const v = e.state?.(dev.state ?? {});
      if (v != null) this.#put(`${this.base}/${deviceId}/${e.key}/state`, v);
    }
  }

  #put(topic, value) {
    if (this.states.get(topic) === value) return;
    if (this.client.publish(topic, value, { retain: true })) this.states.set(topic, value);
  }

  async #onMessage(topic, payload) {
    if (topic === `${this.prefix}/status`) {
      if (payload === 'online') {
        this.configs.clear();
        this.states.clear();
        this.inventory();
      }
      return;
    }
    const m = topic.match(new RegExp(`^${this.base}/([^/]+)/([^/]+)/set$`));
    if (!m) return;
    const [, deviceId, key] = m;
    const dev = new Map(this.listDevices()).get(deviceId);
    if (!dev) return;
    const cmd = key === 'suction' ? (dev.caps.get('suction') ? { key: 'suction', value: String(payload).trim() } : null) : commandFromHa(dev, key, payload);
    if (!cmd) {
      log.warn('ha_mqtt.command_ignored', { device_id: deviceId, key });
      return;
    }
    const result = await this.execute(deviceId, cmd.key, cmd.value);
    log.info('ha_mqtt.command', { device_id: deviceId, capability: cmd.key, status: result?.status, ...(result?.error ? { error: result.error } : {}) });
    // Ordre refusé ou échoué : HA revient à l'état réel.
    for (const t of [...this.states.keys()]) if (t.startsWith(`${this.base}/${deviceId}/`)) this.states.delete(t);
    this.state(deviceId);
  }
}
