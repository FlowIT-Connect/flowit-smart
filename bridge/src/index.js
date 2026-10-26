// FlowIT Bridge — point d'entrée.
//   node --env-file=.env src/index.js        (ou docker compose up -d)

import { FakeHomeAssistant } from './adapters/fake_home_assistant.js';
import { HomeAssistantAdapter } from './adapters/home_assistant.js';
import { Bridge } from './bridge.js';
import { loadConfig } from './config.js';
import { log, setLogLevel } from './log.js';
import { SupabaseStore } from './store.js';

const config = loadConfig();
setLogLevel(config.logLevel);
config.runAutomations = process.env.RUN_AUTOMATIONS !== 'false';

let adapter;
if (config.adapter === 'simulator') {
  const fake = new FakeHomeAssistant();
  adapter = new HomeAssistantAdapter({ url: 'http://simulateur', token: 'simulateur', wsFactory: () => fake.socket() });
  // Les capteurs simulés évoluent pour montrer le temps réel dans l'application.
  setInterval(() => {
    const t = Number(fake.states.get('sensor.chambre_temperature').state);
    fake.setState('sensor.chambre_temperature', (t + (Math.random() - 0.5) * 0.4).toFixed(1));
  }, 15_000);
  log.warn('bridge.simulator', { message: 'Mode simulateur : appareils fictifs, aucun matériel piloté.' });
} else {
  adapter = new HomeAssistantAdapter({ url: config.haUrl, token: config.haToken, filter: config.haEntityFilter });
}

const bridge = new Bridge({ store: new SupabaseStore(config.supabaseUrl, config.supabaseServiceKey), adapter, config });

const shutdown = async (signal) => {
  log.info('bridge.stop', { signal });
  await bridge.stop();
  process.exit(0);
};
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

bridge.start().catch((e) => {
  log.error('bridge.fatal', { error: e.message });
  process.exit(1);
});
