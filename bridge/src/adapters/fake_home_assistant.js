// Home Assistant simulé (ADAPTER=simulator) : même protocole WebSocket que le vrai,
// pour tester l'application de bout en bout sans matériel. Utilisé aussi par les tests.

const now = () => new Date().toISOString();

function st(entity_id, state, attributes = {}) {
  return { entity_id, state, attributes, last_changed: now(), last_updated: now() };
}

export function demoHome() {
  const states = [
    st('light.salon_plafonnier', 'on', { friendly_name: 'Plafonnier', supported_color_modes: ['color_temp'], brightness: 178, color_temp_kelvin: 3000, min_color_temp_kelvin: 2200, max_color_temp_kelvin: 4000 }),
    st('light.ruban_tv', 'off', { friendly_name: 'Ruban LED TV', supported_color_modes: ['hs'], brightness: 128, rgb_color: [63, 81, 181] }),
    st('switch.prise_cafe', 'off', { friendly_name: 'Prise café' }),
    st('sensor.prise_cafe_power', '0', { friendly_name: 'Prise café puissance', device_class: 'power', unit_of_measurement: 'W' }),
    st('cover.volet_salon', 'open', { friendly_name: 'Volet salon', current_position: 100, supported_features: 15 }),
    st('climate.thermostat', 'heat', { friendly_name: 'Thermostat', temperature: 21, current_temperature: 20.4, min_temp: 7, max_temp: 30, target_temp_step: 0.5, hvac_modes: ['off', 'heat', 'auto'] }),
    st('sensor.chambre_temperature', '19.8', { device_class: 'temperature', unit_of_measurement: '°C' }),
    st('sensor.chambre_humidity', '48', { device_class: 'humidity', unit_of_measurement: '%' }),
    st('binary_sensor.porte_entree', 'off', { friendly_name: 'Porte d\'entrée', device_class: 'door' }),
    st('lock.porte_entree', 'locked', { friendly_name: 'Serrure' }),
    st('light.ampoule_chevet', 'unavailable', { friendly_name: 'Ampoule chevet', supported_color_modes: ['brightness'] }),
    st('binary_sensor.couloir_motion', 'off', { friendly_name: 'Détecteur couloir', device_class: 'motion' }),
    st('sensor.couloir_battery', '76', { device_class: 'battery', unit_of_measurement: '%', friendly_name: 'Détecteur couloir batterie' }),
  ];
  const devices = [
    { id: 'd_plafonnier', name: 'Plafonnier', manufacturer: 'IKEA', model: 'LED1836G9', identifiers: [['mqtt', 'zigbee2mqtt_0x01']] },
    { id: 'd_ruban', name: 'Ruban LED TV', manufacturer: 'Tuya', model: 'LED strip RGB' },
    { id: 'd_cafe', name: 'Prise café', manufacturer: 'Shelly', model: 'Plug S' },
    { id: 'd_volet', name: 'Volet salon', manufacturer: 'Moes', model: 'Curtain switch', identifiers: [['mqtt', 'zigbee2mqtt_0x02']] },
    { id: 'd_thermostat', name: 'Thermostat', manufacturer: 'Netatmo', model: 'Smart Thermostat' },
    { id: 'd_chambre', name: 'Capteur chambre', manufacturer: 'Aqara', model: 'WSDCGQ11LM', identifiers: [['mqtt', 'zigbee2mqtt_0x03']] },
    { id: 'd_porte', name: 'Porte d\'entrée', manufacturer: 'Aqara', model: 'MCCGQ11LM', identifiers: [['mqtt', 'zigbee2mqtt_0x04']] },
    { id: 'd_serrure', name: 'Serrure', manufacturer: 'SwitchBot', model: 'Lock' },
    { id: 'd_ampoule', name: 'Ampoule chevet', manufacturer: 'Tuya', model: 'Smart bulb E27' },
    { id: 'd_couloir', name: 'Détecteur couloir', manufacturer: 'Sonoff', model: 'SNZB-03', identifiers: [['mqtt', 'zigbee2mqtt_0x05']] },
  ];
  const entities = [
    ['light.salon_plafonnier', 'd_plafonnier', 'mqtt'],
    ['light.ruban_tv', 'd_ruban', 'tuya'],
    ['switch.prise_cafe', 'd_cafe', 'shelly'],
    ['sensor.prise_cafe_power', 'd_cafe', 'shelly'],
    ['cover.volet_salon', 'd_volet', 'mqtt'],
    ['climate.thermostat', 'd_thermostat', 'netatmo'],
    ['sensor.chambre_temperature', 'd_chambre', 'mqtt'],
    ['sensor.chambre_humidity', 'd_chambre', 'mqtt'],
    ['binary_sensor.porte_entree', 'd_porte', 'mqtt'],
    ['lock.porte_entree', 'd_serrure', 'switchbot'],
    ['light.ampoule_chevet', 'd_ampoule', 'tuya'],
    ['binary_sensor.couloir_motion', 'd_couloir', 'mqtt'],
    ['sensor.couloir_battery', 'd_couloir', 'mqtt'],
  ].map(([entity_id, device_id, platform]) => ({ entity_id, device_id, platform }));
  return { states, devices, entities };
}

export class FakeHomeAssistant {
  constructor({ states, devices = [], entities = [] } = demoHome(), { latencyMs = 300, token = 'simulateur' } = {}) {
    this.states = new Map(states.map((s) => [s.entity_id, structuredClone(s)]));
    this.devices = devices;
    this.entities = entities;
    this.latencyMs = latencyMs;
    this.token = token;
    this.sockets = new Set();
    this.calls = [];
  }

  /** Fabrique compatible avec HomeAssistantAdapter({ wsFactory }). */
  socket() {
    const fake = {
      onmessage: null,
      onclose: null,
      onerror: null,
      send: (raw) => this.#handle(fake, JSON.parse(raw)),
      close: () => {
        this.sockets.delete(fake);
        setTimeout(() => fake.onclose?.(), 0);
      },
      subscribed: false,
    };
    this.sockets.add(fake);
    setTimeout(() => this.#emit(fake, { type: 'auth_required', ha_version: 'simulateur' }), 0);
    return fake;
  }

  #emit(sock, msg) {
    setTimeout(() => sock.onmessage?.({ data: JSON.stringify(msg) }), 0);
  }

  /** Change un état comme le ferait un appareil physique (capteurs, perte de connexion…). */
  setState(entityId, state, attributes) {
    const old = this.states.get(entityId);
    const next = { ...(old ?? { entity_id: entityId, attributes: {} }), state, attributes: { ...(old?.attributes ?? {}), ...(attributes ?? {}) }, last_updated: now() };
    this.states.set(entityId, next);
    for (const s of this.sockets) {
      if (s.subscribed) this.#emit(s, { type: 'event', event: { event_type: 'state_changed', data: { entity_id: entityId, old_state: old, new_state: next } } });
    }
  }

  #handle(sock, msg) {
    if (msg.type === 'auth') {
      this.#emit(sock, msg.access_token === this.token ? { type: 'auth_ok' } : { type: 'auth_invalid', message: 'Invalid access token' });
      return;
    }
    const reply = (result, success = true, error) => this.#emit(sock, { id: msg.id, type: 'result', success, result, error });
    switch (msg.type) {
      case 'get_states':
        return reply([...this.states.values()]);
      case 'config/entity_registry/list':
        return reply(this.entities);
      case 'config/device_registry/list':
        return reply(this.devices);
      case 'subscribe_events':
        if (msg.event_type === 'state_changed') sock.subscribed = true;
        return reply(null);
      case 'call_service':
        return this.#callService(msg, reply);
      default:
        return reply(null, false, { code: 'unknown_command', message: 'Commande inconnue' });
    }
  }

  #callService(msg, reply) {
    const entityId = msg.target?.entity_id;
    const cur = this.states.get(entityId);
    if (!cur) return reply(null, false, { code: 'not_found', message: `Entité inconnue : ${entityId}` });
    this.calls.push({ domain: msg.domain, service: msg.service, entityId, data: msg.service_data });
    reply({ context: { id: 'ctx' } });
    if (cur.state === 'unavailable') return; // appareil injoignable : aucun retour d'état
    const d = msg.service_data ?? {};
    const a = {};
    let state = cur.state;
    switch (`${msg.domain}.${msg.service}`) {
      case 'light.turn_on':
        state = 'on';
        if (d.brightness_pct != null) a.brightness = Math.round((d.brightness_pct / 100) * 255);
        if (d.color_temp_kelvin != null) a.color_temp_kelvin = d.color_temp_kelvin;
        if (d.rgb_color) a.rgb_color = d.rgb_color;
        break;
      case 'light.turn_off':
      case 'switch.turn_off':
      case 'fan.turn_off':
      case 'input_boolean.turn_off':
        state = 'off';
        break;
      case 'switch.turn_on':
      case 'fan.turn_on':
      case 'input_boolean.turn_on':
        state = 'on';
        break;
      case 'cover.open_cover':
        state = 'open';
        a.current_position = 100;
        break;
      case 'cover.close_cover':
        state = 'closed';
        a.current_position = 0;
        break;
      case 'cover.set_cover_position':
        state = d.position > 0 ? 'open' : 'closed';
        a.current_position = d.position;
        break;
      case 'climate.set_temperature':
        a.temperature = d.temperature;
        break;
      case 'climate.set_hvac_mode':
        state = d.hvac_mode;
        break;
      default:
        return;
    }
    setTimeout(() => {
      this.setState(entityId, state, a);
      if (entityId === 'switch.prise_cafe') this.setState('sensor.prise_cafe_power', state === 'on' ? '1180' : '0');
    }, this.latencyMs);
  }
}
