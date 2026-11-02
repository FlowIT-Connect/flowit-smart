// Solea Yeedi — point d'entrée : node --env-file=.env src/index.js
//
// Copyright (C) 2026 FlowIT Connect
// Ce programme est un logiciel libre : vous pouvez le redistribuer et le modifier selon
// les termes de la GNU General Public License version 3 ou ultérieure (voir LICENSE).
// Il est distribué SANS AUCUNE GARANTIE.

import { yeediCloud } from './cloud.js';
import { RobotHub } from './robots.js';
import { yeediServer } from './server.js';

const log = (event, data = {}) => console.log(JSON.stringify({ at: new Date().toISOString(), event, ...data }));

function need(name) {
  const v = process.env[name]?.trim();
  if (!v) {
    console.error(`Réglage manquant : ${name} (lancez Configurer-Yeedi.cmd ou « npm run configurer »)`);
    process.exit(1);
  }
  return v;
}

const cloud = yeediCloud({
  email: need('YEEDI_EMAIL'),
  passwordMd5: need('YEEDI_PASSWORD_MD5').toLowerCase(),
  country: process.env.YEEDI_COUNTRY?.trim() || 'DZ',
  domain: process.env.YEEDI_DOMAIN?.trim() ?? 'yeedi.com',
});
const hub = new RobotHub(cloud, { log });
const host = process.env.YEEDI_HOST?.trim() || '127.0.0.1';
const port = Number(process.env.YEEDI_PORT) || 8790;

try {
  await hub.start();
} catch (e) {
  log('yeedi.login_failed', { error: e.message, hint: 'Vérifiez l\'e-mail, le mot de passe et le pays du compte yeedi' });
  process.exit(1);
}
const server = yeediServer(hub, { token: need('YEEDI_TOKEN') });
server.listen(port, host, () => log('yeedi.listening', { url: `http://${host}:${port}` }));

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, async () => {
    server.close();
    await hub.stop();
    process.exit(0);
  });
}
