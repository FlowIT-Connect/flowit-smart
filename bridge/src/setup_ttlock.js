// Ajout des serrures TTLock sans répondre aux questions dans la console (Ajouter-TTLock.cmd) :
//   node src/setup_ttlock.js preparer   crée ttlock.txt, que l'on remplit dans le Bloc-notes
//   node src/setup_ttlock.js appliquer  vérifie le compte TTLock, l'écrit dans .env et efface ttlock.txt
//
// Les réglages Tuya et Supabase du .env sont gardés. Le mot de passe de l'app TTLock n'est
// enregistré que sous forme d'empreinte MD5.

import { existsSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { md5, TTLockClient } from './adapters/ttlock_api.js';
import { parseEnv, renderEnv } from './setup.js';

const ENV_FILE = fileURLToPath(new URL('../.env', import.meta.url));
const FORM_FILE = fileURLToPath(new URL('../ttlock.txt', import.meta.url));

const FORM = `# Remplissez les 4 lignes juste après le signe =, puis enregistrez (Ctrl + S)
# et fermez le Bloc-notes. Ce fichier est effacé dès que la passerelle l'a lu.
#
# Client ID et Client Secret : open.ttlock.com > Application > votre application
CLIENT_ID=
CLIENT_SECRET=
# Le compte de l'app TTLock qui gère la serrure (téléphone avec indicatif, ou e-mail)
IDENTIFIANT_APP_TTLOCK=
MOT_DE_PASSE_APP_TTLOCK=
`;

/** Lit le formulaire rempli ; renvoie les champs manquants s'il est incomplet. */
export function readForm(text) {
  const f = {};
  for (const line of text.replace(/^﻿/, '').split(/\r?\n/)) {
    const m = /^\s*([A-Z_]+)\s*=(.*)$/.exec(line);
    if (m) f[m[1]] = m[2].trim();
  }
  const keys = ['CLIENT_ID', 'CLIENT_SECRET', 'IDENTIFIANT_APP_TTLOCK', 'MOT_DE_PASSE_APP_TTLOCK'];
  return { values: f, missing: keys.filter((k) => !f[k]) };
}

async function apply() {
  if (!existsSync(ENV_FILE)) throw new Error('Pas de fichier .env : lancez d\'abord Demarrer-FlowIT-Tuya.cmd');
  if (!existsSync(FORM_FILE)) throw new Error('ttlock.txt introuvable : relancez Ajouter-TTLock.cmd');
  const { values: f, missing } = readForm(readFileSync(FORM_FILE, 'utf8'));
  if (missing.length) throw new Error(`Il manque dans ttlock.txt : ${missing.join(', ')}. Relancez Ajouter-TTLock.cmd`);

  const v = {
    ...parseEnv(readFileSync(ENV_FILE, 'utf8')),
    TTLOCK_CLIENT_ID: f.CLIENT_ID,
    TTLOCK_CLIENT_SECRET: f.CLIENT_SECRET,
    TTLOCK_USERNAME: f.IDENTIFIANT_APP_TTLOCK,
    TTLOCK_PASSWORD_MD5: md5(f.MOT_DE_PASSE_APP_TTLOCK),
  };

  console.log('\nVérification auprès du cloud TTLock…');
  try {
    const client = new TTLockClient({ clientId: v.TTLOCK_CLIENT_ID, clientSecret: v.TTLOCK_CLIENT_SECRET, username: v.TTLOCK_USERNAME, passwordMd5: v.TTLOCK_PASSWORD_MD5 });
    const locks = await client.listLocks();
    console.log(locks.length ? `OK : ${locks.length} serrure(s) trouvée(s) :` : 'Connexion OK mais aucune serrure sur ce compte TTLock.');
    for (const l of locks) {
      console.log(`  - ${l.lockAlias || l.lockName} (batterie ${l.electricQuantity ?? '?'} %, ${l.hasGateway === 1 ? 'avec passerelle : ouverture à distance possible' : 'sans passerelle : codes d\'accès seulement'})`);
    }
  } catch (e) {
    // Le formulaire est gardé pour corriger la faute sans tout retaper.
    throw new Error(`Échec TTLock : ${e.message}\nCorrigez ttlock.txt en relançant Ajouter-TTLock.cmd.`);
  }

  writeFileSync(ENV_FILE, renderEnv(v), { mode: 0o600 });
  unlinkSync(FORM_FILE);
  console.log('Serrures TTLock ajoutées à la configuration.');
}

const isMain = process.argv[1] && resolve(process.argv[1]).toLowerCase() === fileURLToPath(import.meta.url).toLowerCase();
if (isMain) {
  const step = process.argv[2];
  if (step === 'preparer') {
    if (!existsSync(FORM_FILE)) writeFileSync(FORM_FILE, FORM, { mode: 0o600 });
  } else if (step === 'appliquer') {
    apply().catch((e) => {
      console.error(`\n${e.message}`);
      process.exit(1);
    });
  } else {
    console.error('Usage : node src/setup_ttlock.js preparer | appliquer');
    process.exit(1);
  }
}
