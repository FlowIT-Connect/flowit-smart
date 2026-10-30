// Assistant de configuration de la passerelle sur un PC (sans box) :
//   npm run configurer        (ou double-clic sur Demarrer-FlowIT-Tuya.cmd sous Windows)
//
// Pose les questions une par une, vérifie les identifiants Tuya auprès du cloud et écrit
// le fichier .env à côté. Les clés tapées ne s'affichent pas à l'écran et ne quittent
// jamais ce PC (sauf vers Supabase et Tuya, pour fonctionner).

import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { createInterface } from 'node:readline/promises';
import { Writable } from 'node:stream';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { DEFAULT_SUPABASE_URL } from './addon_options.js';
import { md5, TTLockClient } from './adapters/ttlock_api.js';
import { TUYA_REGIONS, TuyaClient } from './adapters/tuya_api.js';

const ENV_FILE = fileURLToPath(new URL('../.env', import.meta.url));

/** Lit un fichier .env simple (CLE=valeur). */
export function parseEnv(text) {
  const env = {};
  for (const line of text.split(/\r?\n/)) {
    const m = /^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/.exec(line);
    if (m) env[m[1]] = m[2];
  }
  return env;
}

/** Contenu du .env pour le mode Tuya Cloud. */
export function renderEnv(v) {
  return `# FlowIT Bridge — mode Tuya Cloud (sans box). Écrit par « npm run configurer ».
# Ne partagez jamais ce fichier : il contient des clés secrètes.
SUPABASE_URL=${v.SUPABASE_URL}
SUPABASE_SERVICE_ROLE_KEY=${v.SUPABASE_SERVICE_ROLE_KEY}
INTEGRATION_ID=${v.INTEGRATION_ID}

ADAPTER=tuya_cloud
TUYA_ACCESS_ID=${v.TUYA_ACCESS_ID}
TUYA_ACCESS_SECRET=${v.TUYA_ACCESS_SECRET}
TUYA_REGION=${v.TUYA_REGION}
# Relecture de l'état des appareils (secondes). Plus court = plus d'appels au cloud Tuya.
TUYA_POLL_SECONDS=${v.TUYA_POLL_SECONDS ?? 30}

${renderTTLock(v)}
RUN_AUTOMATIONS=true
LOG_LEVEL=info
`;
}

function renderTTLock(v) {
  if (!v.TTLOCK_CLIENT_ID) return '# Serrures TTLock : relancez « npm run configurer » pour les ajouter.\n';
  return `# Serrures TTLock (open.ttlock.com > votre application) et compte de l'app TTLock.
# Le mot de passe n'est jamais écrit en clair : TTLock demande son empreinte MD5.
TTLOCK_CLIENT_ID=${v.TTLOCK_CLIENT_ID}
TTLOCK_CLIENT_SECRET=${v.TTLOCK_CLIENT_SECRET}
TTLOCK_USERNAME=${v.TTLOCK_USERNAME}
TTLOCK_PASSWORD_MD5=${v.TTLOCK_PASSWORD_MD5}
`;
}

async function main() {
  const old = existsSync(ENV_FILE) ? parseEnv(readFileSync(ENV_FILE, 'utf8')) : {};
  const out = new Writable({
    write(chunk, enc, cb) {
      if (!out.muted) process.stdout.write(chunk, enc);
      cb();
    },
  });
  const rl = createInterface({ input: process.stdin, output: out, terminal: true });
  const ask = async (question, { secret = false, current = '' } = {}) => {
    const hint = current ? (secret ? ' [Entrée = garder la valeur actuelle]' : ` [${current}]`) : '';
    process.stdout.write(`\n${question}${hint}\n> `);
    out.muted = secret;
    const answer = (await rl.question('')).trim();
    out.muted = false;
    if (secret) process.stdout.write(answer ? '(reçu, caché)\n' : '\n');
    return answer || current;
  };

  console.log('=== Configuration de FlowIT Bridge (Tuya / Smart Life, sans box) ===');
  console.log('Les clés que vous tapez ou collez (clic droit) restent cachées et ne sont enregistrées que sur ce PC.');

  const v = { SUPABASE_URL: old.SUPABASE_URL || DEFAULT_SUPABASE_URL, TUYA_POLL_SECONDS: old.TUYA_POLL_SECONDS };
  v.INTEGRATION_ID = await ask('1/5  Identifiant d\'intégration (application FlowIT Smart > Paramètres > Intégrations > Ajouter > Tuya) :', { current: old.INTEGRATION_ID });
  v.SUPABASE_SERVICE_ROLE_KEY = await ask('2/5  Clé « service_role » (ou « secret ») de Supabase (supabase.com > projet > Project Settings > API Keys) :', { secret: true, current: old.SUPABASE_SERVICE_ROLE_KEY });
  v.TUYA_ACCESS_ID = await ask('3/5  Tuya « Access ID / Client ID » (platform.tuya.com > Cloud > votre projet > Overview) :', { current: old.TUYA_ACCESS_ID });
  v.TUYA_ACCESS_SECRET = await ask('4/5  Tuya « Access Secret / Client Secret » (même page) :', { secret: true, current: old.TUYA_ACCESS_SECRET });
  const regions = Object.entries(TUYA_REGIONS);
  const currentRegion = Math.max(1, regions.findIndex(([k]) => k === (old.TUYA_REGION || 'eu')) + 1);
  console.log('\n5/5  Data center du projet Tuya :');
  regions.forEach(([, r], i) => console.log(`     ${i + 1}. ${r.label}`));
  const choice = Number.parseInt(await ask('Numéro :', { current: String(currentRegion) }), 10);
  v.TUYA_REGION = regions[(choice >= 1 && choice <= regions.length ? choice : currentRegion) - 1][0];

  const wantsTTLock = await ask('Serrures / contrôles d\'accès TTLock : les ajouter ? (o = oui, n = non)', { current: old.TTLOCK_CLIENT_ID ? 'o' : 'n' });
  if (/^o/i.test(wantsTTLock)) {
    v.TTLOCK_CLIENT_ID = await ask('TTLock 1/4  « Client ID » (open.ttlock.com > Application > votre application) :', { current: old.TTLOCK_CLIENT_ID });
    v.TTLOCK_CLIENT_SECRET = await ask('TTLock 2/4  « Client Secret » (même page) :', { secret: true, current: old.TTLOCK_CLIENT_SECRET });
    v.TTLOCK_USERNAME = await ask('TTLock 3/4  Identifiant de l\'app TTLock (téléphone ou e-mail du compte qui gère la serrure) :', { current: old.TTLOCK_USERNAME });
    const password = await ask('TTLock 4/4  Mot de passe de l\'app TTLock :', { secret: true, current: old.TTLOCK_PASSWORD_MD5 ? '(inchangé)' : '' });
    v.TTLOCK_PASSWORD_MD5 = password === '(inchangé)' ? old.TTLOCK_PASSWORD_MD5 : password ? md5(password) : '';
    if (!v.TTLOCK_CLIENT_ID || !v.TTLOCK_CLIENT_SECRET || !v.TTLOCK_USERNAME || !v.TTLOCK_PASSWORD_MD5) {
      console.log('Informations TTLock incomplètes : serrures non ajoutées.');
      v.TTLOCK_CLIENT_ID = '';
    }
  }
  rl.close();

  const missing = ['INTEGRATION_ID', 'SUPABASE_SERVICE_ROLE_KEY', 'TUYA_ACCESS_ID', 'TUYA_ACCESS_SECRET'].filter((k) => !v[k]);
  if (missing.length) {
    console.error(`\nIl manque : ${missing.join(', ')}. Relancez la configuration.`);
    process.exit(1);
  }

  console.log('\nVérification auprès du cloud Tuya…');
  try {
    const client = new TuyaClient({ accessId: v.TUYA_ACCESS_ID, accessSecret: v.TUYA_ACCESS_SECRET, baseUrl: TUYA_REGIONS[v.TUYA_REGION].url });
    const devices = await client.listDevices();
    if (devices.length) {
      console.log(`OK : ${devices.length} appareil(s) trouvé(s) :`);
      for (const d of devices) console.log(`  - ${d.name} (${d.online === false ? 'hors ligne' : 'en ligne'})`);
    } else {
      console.log('Connexion OK mais aucun appareil. Vérifiez : Devices > Link App Account (QR code scanné avec Smart Life)');
      console.log('et que le data center choisi est celui de votre compte Smart Life.');
    }
  } catch (e) {
    console.error(`Échec : ${e.message}`);
    console.error('La configuration est quand même enregistrée ; corrigez puis relancez « npm run configurer ».');
  }

  if (v.TTLOCK_CLIENT_ID) {
    console.log('\nVérification auprès du cloud TTLock…');
    try {
      const client = new TTLockClient({ clientId: v.TTLOCK_CLIENT_ID, clientSecret: v.TTLOCK_CLIENT_SECRET, username: v.TTLOCK_USERNAME, passwordMd5: v.TTLOCK_PASSWORD_MD5 });
      const locks = await client.listLocks();
      console.log(locks.length ? `OK : ${locks.length} serrure(s) trouvée(s) :` : 'Connexion OK mais aucune serrure sur ce compte TTLock.');
      for (const l of locks) {
        console.log(`  - ${l.lockAlias || l.lockName} (batterie ${l.electricQuantity ?? '?'} %, ${l.hasGateway === 1 ? 'avec passerelle : ouverture à distance possible' : 'sans passerelle : codes d\'accès seulement'})`);
      }
    } catch (e) {
      console.error(`Échec TTLock : ${e.message}`);
    }
  }

  writeFileSync(ENV_FILE, renderEnv(v), { mode: 0o600 });
  console.log(`\nConfiguration enregistrée dans ${ENV_FILE}`);
}

const isMain = process.argv[1] && resolve(process.argv[1]).toLowerCase() === fileURLToPath(import.meta.url).toLowerCase();
if (isMain) {
  main().catch((e) => {
    console.error(e.message);
    process.exit(1);
  });
}
