// Configuration sans questions dans la console (Configurer-Yeedi.cmd) :
//   node src/setup.js preparer   crée yeedi.txt, que l'on remplit dans le Bloc-notes
//   node src/setup.js appliquer  vérifie le compte yeedi, écrit .env, relie la passerelle
//                                Solea (../bridge/.env) et efface yeedi.txt
//
// Le mot de passe yeedi n'est enregistré que sous forme d'empreinte MD5.
//
// Copyright (C) 2026 FlowIT Connect
// Ce programme est un logiciel libre : GPL version 3 ou ultérieure (voir LICENSE).

import { randomBytes } from 'node:crypto';
import { existsSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ENV_FILE = fileURLToPath(new URL('../.env', import.meta.url));
const FORM_FILE = fileURLToPath(new URL('../yeedi.txt', import.meta.url));
const BRIDGE_ENV = fileURLToPath(new URL('../../bridge/.env', import.meta.url));

const FORM = `# Remplissez les lignes juste après le signe =, puis enregistrez (Ctrl + S)
# et fermez le Bloc-notes. Ce fichier est effacé dès qu'il a été lu.
#
# Le compte de l'application yeedi (celui qui voit le robot)
EMAIL_YEEDI=
MOT_DE_PASSE_YEEDI=
# Pays du compte, en 2 lettres (DZ pour l'Algérie, FR pour la France…)
PAYS=DZ
`;

/** Fichier .env très simple : CLE=valeur par ligne. */
export function parseEnv(text) {
  const out = {};
  for (const line of text.replace(/^﻿/, '').split(/\r?\n/)) {
    const m = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$/.exec(line);
    if (m) out[m[1]] = m[2].trim();
  }
  return out;
}

/** Remplace (ou ajoute) des lignes dans un .env en gardant le reste tel quel. */
export function setEnvLines(text, values) {
  const lines = text.length ? text.replace(/\r?\n$/, '').split(/\r?\n/) : [];
  const done = new Set();
  const out = lines.map((line) => {
    const m = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=/.exec(line);
    if (m && m[1] in values) {
      done.add(m[1]);
      return `${m[1]}=${values[m[1]]}`;
    }
    return line;
  });
  for (const [k, v] of Object.entries(values)) if (!done.has(k)) out.push(`${k}=${v}`);
  return `${out.join('\n')}\n`;
}

export function readForm(text) {
  const f = parseEnv(text);
  const missing = ['EMAIL_YEEDI', 'MOT_DE_PASSE_YEEDI'].filter((k) => !f[k]);
  const country = (f.PAYS || 'DZ').toUpperCase();
  if (!/^[A-Z]{2}$/.test(country)) missing.push('PAYS (2 lettres)');
  return { email: f.EMAIL_YEEDI, password: f.MOT_DE_PASSE_YEEDI, country, missing };
}

async function apply() {
  if (!existsSync(FORM_FILE)) throw new Error('yeedi.txt introuvable : relancez Configurer-Yeedi.cmd');
  const form = readForm(readFileSync(FORM_FILE, 'utf8'));
  if (form.missing.length) throw new Error(`Il manque dans yeedi.txt : ${form.missing.join(', ')}. Relancez Configurer-Yeedi.cmd`);

  const { md5, yeediCloud } = await import('./cloud.js');
  const passwordMd5 = md5(form.password);
  console.log('\nVérification auprès du cloud yeedi…');
  try {
    const cloud = yeediCloud({ email: form.email, passwordMd5, country: form.country });
    await cloud.login();
    const robots = await cloud.robots();
    console.log(robots.length ? `OK : ${robots.length} robot(s) trouvé(s) :` : 'Connexion OK mais aucun robot sur ce compte yeedi.');
    for (const r of robots) console.log(`  - ${r.name} (${r.model})`);
  } catch (e) {
    // Le formulaire est gardé pour corriger la faute sans tout retaper.
    throw new Error(`Échec yeedi : ${e.message}\nCorrigez yeedi.txt en relançant Configurer-Yeedi.cmd.`);
  }

  const old = existsSync(ENV_FILE) ? parseEnv(readFileSync(ENV_FILE, 'utf8')) : {};
  const token = old.YEEDI_TOKEN || randomBytes(24).toString('hex');
  const port = old.YEEDI_PORT || '8790';
  const env = { YEEDI_EMAIL: form.email, YEEDI_PASSWORD_MD5: passwordMd5, YEEDI_COUNTRY: form.country, YEEDI_PORT: port, YEEDI_TOKEN: token };
  writeFileSync(ENV_FILE, setEnvLines(existsSync(ENV_FILE) ? readFileSync(ENV_FILE, 'utf8') : '', env), { mode: 0o600 });
  unlinkSync(FORM_FILE);

  if (existsSync(BRIDGE_ENV)) {
    writeFileSync(BRIDGE_ENV, setEnvLines(readFileSync(BRIDGE_ENV, 'utf8'), { YEEDI_URL: `http://127.0.0.1:${port}`, YEEDI_TOKEN: token }), { mode: 0o600 });
    console.log('Passerelle Solea reliée au module yeedi (relancez-la pour voir le robot).');
  } else {
    console.log(`Passerelle Solea non trouvée à côté : ajoutez dans son .env\n  YEEDI_URL=http://127.0.0.1:${port}\n  YEEDI_TOKEN=${token}`);
  }
}

const isMain = process.argv[1] && resolve(process.argv[1]).toLowerCase() === fileURLToPath(import.meta.url).toLowerCase();
if (isMain) {
  const step = process.argv[2];
  if (step === 'preparer') {
    if (!existsSync(FORM_FILE)) writeFileSync(FORM_FILE, FORM, { mode: 0o600 });
  } else if (step === 'appliquer') {
    apply()
      .then(() => process.exit(0))
      .catch((e) => {
        console.error(`\n${e.message}`);
        process.exit(1);
      });
  } else {
    console.error('Usage : node src/setup.js preparer | appliquer');
    process.exit(1);
  }
}
