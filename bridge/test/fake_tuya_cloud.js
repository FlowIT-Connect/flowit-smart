// Cloud Tuya simulé pour les tests : mêmes routes et même signature que l'API réelle.

import { sign } from '../src/adapters/tuya_api.js';

export const ACCESS_ID = 'test-access-id';
export const ACCESS_SECRET = 'test-access-secret';

const spec = (category, functions, status = []) => ({ category, functions, status });
const fn = (code, type, values = {}) => ({ code, type, values: JSON.stringify(values) });

export function demoTuyaDevices() {
  return [
    {
      id: 'plug1', name: 'Prise salon', category: 'cz', product_name: 'Smart Plug 16A', online: true,
      status: [{ code: 'switch_1', value: false }, { code: 'cur_power', value: 0 }, { code: 'add_ele', value: 125 }],
      spec: spec('cz', [fn('switch_1', 'Boolean')], [
        fn('switch_1', 'Boolean'),
        fn('cur_power', 'Integer', { unit: 'W', min: 0, max: 50000, scale: 1, step: 1 }),
        fn('add_ele', 'Integer', { unit: 'kwh', min: 0, max: 50000, scale: 3, step: 100 }),
      ]),
    },
    {
      id: 'bulb1', name: 'Ampoule bureau', category: 'dj', product_name: 'RGBCW Bulb E27', online: true,
      status: [
        { code: 'switch_led', value: true }, { code: 'work_mode', value: 'white' }, { code: 'bright_value_v2', value: 505 },
        { code: 'temp_value_v2', value: 0 }, { code: 'colour_data_v2', value: '{"h":0,"s":1000,"v":1000}' },
      ],
      spec: spec('dj', [
        fn('switch_led', 'Boolean'),
        fn('work_mode', 'Enum', { range: ['white', 'colour', 'scene', 'music'] }),
        fn('bright_value_v2', 'Integer', { min: 10, max: 1000, scale: 0, step: 1 }),
        fn('temp_value_v2', 'Integer', { min: 0, max: 1000, scale: 0, step: 1 }),
        fn('colour_data_v2', 'Json', {}),
      ]),
    },
    {
      id: 'multi1', name: 'Multiprise', category: 'pc', product_name: 'Power strip', online: true,
      status: [{ code: 'switch_1', value: true }, { code: 'switch_2', value: false }],
      spec: spec('pc', [fn('switch_2', 'Boolean'), fn('switch_1', 'Boolean')]),
    },
    {
      id: 'th1', name: 'Capteur chambre', category: 'wsdcg', product_name: 'T&H Sensor', online: true,
      status: [{ code: 'va_temperature', value: 215 }, { code: 'va_humidity', value: 48 }, { code: 'battery_percentage', value: 90 }],
      spec: spec('wsdcg', [], [
        fn('va_temperature', 'Integer', { unit: '℃', min: -200, max: 600, scale: 1, step: 1 }),
        fn('va_humidity', 'Integer', { unit: '%', min: 0, max: 100, scale: 0, step: 1 }),
        fn('battery_percentage', 'Integer', { unit: '%', min: 0, max: 100, scale: 0, step: 1 }),
      ]),
    },
    {
      id: 'lock1', name: 'Serrure', category: 'ms', product_name: 'Smart Lock', online: true,
      status: [{ code: 'switch', value: false }, { code: 'battery_percentage', value: 70 }],
      spec: spec('ms', [fn('switch', 'Boolean')], [fn('battery_percentage', 'Integer', { min: 0, max: 100, scale: 0 })]),
    },
    {
      id: 'off1', name: 'Prise garage', category: 'cz', product_name: 'Smart Plug', online: false,
      status: [{ code: 'switch_1', value: false }],
      spec: spec('cz', [fn('switch_1', 'Boolean')]),
    },
    {
      id: 'ir1', name: 'Télécommande IR', category: 'wnykq', product_name: 'IR Blaster', online: true,
      status: [], spec: spec('wnykq', []),
    },
  ];
}

export class FakeTuyaCloud {
  constructor(devices = demoTuyaDevices(), { latencyMs = 30 } = {}) {
    this.devices = new Map(devices.map((d) => [d.id, structuredClone(d)]));
    this.latencyMs = latencyMs; // délai avant que l'appareil applique une commande
    this.ignoreCommands = false; // appareil qui accepte mais ne change jamais d'état
    this.token = 'tok-1';
    this.calls = [];
    this.commands = [];
    this.fetch = this.fetch.bind(this);
  }

  setStatus(id, code, value) {
    const d = this.devices.get(id);
    const s = d.status.find((x) => x.code === code);
    if (s) s.value = value;
    else d.status.push({ code, value });
  }

  async fetch(url, init) {
    const u = new URL(url);
    const pathWithQuery = u.pathname + (u.search ? decodeURIComponent(u.search) : '');
    const h = init.headers;
    const accessToken = h.access_token ?? '';
    const expected = sign({ clientId: ACCESS_ID, secret: ACCESS_SECRET, accessToken, t: h.t, nonce: h.nonce, method: init.method, body: init.body ?? '', pathWithQuery });
    this.calls.push(`${init.method} ${u.pathname}`);
    const reply = (body) => ({ ok: true, status: 200, json: async () => body });
    if (h.client_id !== ACCESS_ID || h.sign !== expected) return reply({ success: false, code: 1004, msg: 'sign invalid' });

    if (u.pathname === '/v1.0/token') return reply({ success: true, result: { access_token: this.token, expire_time: 7200, uid: 'u1' } });
    if (accessToken !== this.token) return reply({ success: false, code: 1010, msg: 'token invalid' });

    if (u.pathname === '/v1.0/iot-01/associated-users/devices') {
      const devices = [...this.devices.values()].map(({ spec, ...d }) => structuredClone(d));
      return reply({ success: true, result: { devices, has_more: false, last_row_key: '' } });
    }
    const m = /^\/v1\.0\/devices\/([^/]+)(\/specifications|\/commands)?$/.exec(u.pathname);
    const dev = m && this.devices.get(m[1]);
    if (!dev) return reply({ success: false, code: 2001, msg: 'device not exist' });
    if (m[2] === '/specifications') return reply({ success: true, result: dev.spec });
    if (m[2] === '/commands') {
      if (!dev.online) return reply({ success: false, code: 2009, msg: 'device is offline' });
      const { commands } = JSON.parse(init.body);
      this.commands.push({ id: dev.id, commands });
      if (!this.ignoreCommands) {
        setTimeout(() => {
          for (const c of commands) this.setStatus(dev.id, c.code, typeof c.value === 'object' ? JSON.stringify(c.value) : c.value);
        }, this.latencyMs);
      }
      return reply({ success: true, result: true });
    }
    const { spec, ...info } = dev;
    return reply({ success: true, result: structuredClone(info) });
  }
}
