// FlowIT Bridge — point d'entrée.
//   node --env-file=.env src/index.js        (ou docker compose up -d, ou npm run local)

import { existsSync } from 'node:fs';

import { addDirectCameras } from './adapters/direct_cameras.js';
import { FakeHomeAssistant } from './adapters/fake_home_assistant.js';
import { HomeAssistantAdapter } from './adapters/home_assistant.js';
import { addTTLock } from './adapters/ttlock.js';
import { TTLockClient } from './adapters/ttlock_api.js';
import { TuyaClient } from './adapters/tuya_api.js';
import { TuyaCloudAdapter } from './adapters/tuya_cloud.js';
import { addYeedi, YeediClient } from './adapters/yeedi.js';
import { Bridge } from './bridge.js';
import { HaExporter } from './ha_export.js';
import { MqttClient } from './mqtt_client.js';
import { loadConfig } from './config.js';
import { PlatformSupervisor } from './platform.js';
import { applyAddonMqtt, applyAddonOptions, readAddonOptions, startAddonYeedi } from './addon_options.js';
import { log, setLogLevel } from './log.js';
import { simulatedFrame } from './png.js';
import { SupabaseStore } from './store.js';
import { VideoOnlyAdapter } from './adapters/video_only.js';
import { addUdi, UdiHub } from './udi/index.js';
import { MediaMtx } from './udi/media/mediamtx.js';
import { discoverDahua } from './udi/dahua/dhip.js';
import { discoverOnvif, subnetFilter } from './udi/onvif/discovery.js';

applyAddonOptions();
// Module complémentaire en mode passerelle complète : broker MQTT de HA et robot yeedi.
const addonOptions = readAddonOptions();
await applyAddonMqtt(addonOptions);
const addonYeedi = startAddonYeedi(addonOptions);
// Réglages Home Assistant (HA_MQTT_URL…) dans un fichier à part, à côté de .env : facultatif.
if (existsSync('homeassistant.env')) process.loadEnvFile('homeassistant.env');
const config = loadConfig();
setLogLevel(config.logLevel);
config.runAutomations = process.env.RUN_AUTOMATIONS !== 'false';
// Boîtier vidéo (ADAPTER=video) : déclencheurs horaires désactivés par défaut, la passerelle
// principale du logement s'en charge (sinon chaque automatisation horaire partirait deux fois).
config.runTimeTriggers = config.adapter === 'video' ? process.env.RUN_TIME_TRIGGERS === 'true' : process.env.RUN_TIME_TRIGGERS !== 'false';

let adapter;
if (config.adapter === 'simulator') {
  const fake = new FakeHomeAssistant();
  adapter = new HomeAssistantAdapter({
    url: 'http://simulateur',
    token: 'simulateur',
    wsFactory: () => fake.socket(),
    fetchImpl: async () => new Response(simulatedFrame(), { headers: { 'content-type': 'image/png' } }),
  });
  // Les capteurs simulés évoluent pour montrer le temps réel dans l'application.
  setInterval(() => {
    const t = Number(fake.states.get('sensor.chambre_temperature').state);
    fake.setState('sensor.chambre_temperature', (t + (Math.random() - 0.5) * 0.4).toFixed(1));
  }, 15_000);
  log.warn('bridge.simulator', { message: 'Mode simulateur : appareils fictifs, aucun matériel piloté.' });
} else if (config.adapter === 'tuya_cloud') {
  const client = new TuyaClient({ accessId: config.tuyaAccessId, accessSecret: config.tuyaAccessSecret, baseUrl: config.tuyaBaseUrl });
  adapter = new TuyaCloudAdapter({ client, pollMs: config.tuyaPollMs, imageBase: config.tuyaImageUrl });
  log.info('bridge.tuya_cloud', { region: config.tuyaBaseUrl, poll_seconds: config.tuyaPollMs / 1000 });
} else if (config.adapter === 'video') {
  adapter = new VideoOnlyAdapter();
} else {
  adapter = new HomeAssistantAdapter({ url: config.haUrl, wsUrl: config.haWsUrl ?? undefined, token: config.haToken, filter: config.haEntityFilter });
}

if (config.cameras.length) {
  addDirectCameras(adapter, config.cameras);
  log.info('bridge.direct_cameras', { count: config.cameras.length });
}

if (config.ttlock) {
  addTTLock(adapter, new TTLockClient(config.ttlock), { pollMs: config.ttlock.pollMs });
  log.info('bridge.ttlock', { api: config.ttlock.baseUrl, poll_seconds: config.ttlock.pollMs / 1000 });
}

if (config.yeedi) {
  addYeedi(adapter, new YeediClient(config.yeedi), { pollMs: config.yeedi.pollMs });
  log.info('bridge.yeedi', { module: config.yeedi.url, poll_seconds: config.yeedi.pollMs / 1000 });
}

if (config.video) {
  const v = config.video;
  const allowed = subnetFilter(v.subnets);
  const hub = new UdiHub({
    mediamtx: v.relay ? new MediaMtx({ apiUrl: v.mediamtxApiUrl, webrtcUrl: v.mediamtxWebrtcUrl }) : null,
    discover: v.discovery ? (opts) => discoverOnvif(opts) : null,
    // Recherche Dahua toujours active : elle sert à retrouver les caméras ajoutées par QR code.
    discoverDahua: (opts) => discoverDahua(opts),
    allowedSubnet: allowed,
    stun: v.stun,
    turn: v.turn,
    turnSecret: v.turnSecret,
  });
  addUdi(adapter, hub);
  log.info('bridge.video', { relay: v.relay, discovery: v.discovery, turn: v.turn.length > 0 });
}

const store = new SupabaseStore(config.supabaseUrl, config.supabaseServiceKey);
const bridge = config.platform ? new PlatformSupervisor({ store, adapter, config }) : new Bridge({ store, adapter, config });
if (config.haMqtt && !config.platform) {
  const m = config.haMqtt;
  const exporter = new HaExporter({
    client: new MqttClient({
      host: m.host,
      port: m.port,
      username: m.username,
      password: m.password,
      clientId: `solea-${config.integrationId.slice(0, 8)}`,
      will: { topic: `${m.base}/bridge/status`, payload: 'offline', retain: true },
    }),
    prefix: m.prefix,
    base: m.base,
    devices: () => bridge.devices.entries(),
    execute: (deviceId, key, value) => bridge.executeLocal(deviceId, key, value),
  });
  bridge.exporter = exporter;
  exporter.start();
  log.info('bridge.ha_mqtt', { broker: `${m.host}:${m.port}`, discovery: m.prefix });
}
if (config.platform) log.info('bridge.platform', { message: 'Passerelle unique : appareils attribués aux logements depuis Solea' });

const shutdown = async (signal) => {
  log.info('bridge.stop', { signal });
  bridge.exporter?.stop();
  addonYeedi?.stop();
  await bridge.stop();
  process.exit(0);
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

bridge.start().catch((e) => {
  log.error('bridge.fatal', { error: e.message });
  process.exit(1);
});
