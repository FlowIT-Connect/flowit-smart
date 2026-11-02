// Assistant du boîtier vidéo sur un PC Windows (double-clic sur Demarrer-Boitier-Video.cmd) :
//   node src/setup_video.js
//
// Trois questions seulement : la clé Supabase (reprise du .env de la passerelle s'il existe),
// l'e-mail du compte Solea, puis le logement. L'intégration « Boîtier vidéo » est créée toute
// seule : plus d'identifiant à copier depuis l'application. Écrit .env.video à côté.

import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { createInterface } from 'node:readline/promises';
import { Writable } from 'node:stream';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { createClient } from '@supabase/supabase-js';

import { DEFAULT_SUPABASE_URL } from './addon_options.js';
import { parseEnv } from './setup.js';

const HERE = fileURLToPath(new URL('..', import.meta.url));
const VIDEO_ENV = process.env.FLOWIT_VIDEO_ENV_FILE || resolve(HERE, '.env.video');
const MAIN_ENV = resolve(HERE, '.env');

export const VIDEO_LABEL = 'Boîtier vidéo';

/** Contenu de .env.video. */
export function renderVideoEnv(v) {
  return `# Boîtier vidéo Solea sur ce PC. Écrit par Demarrer-Boitier-Video.cmd.
# Ne partagez jamais ce fichier : il contient une clé secrète.
SUPABASE_URL=${v.SUPABASE_URL}
SUPABASE_SERVICE_ROLE_KEY=${v.SUPABASE_SERVICE_ROLE_KEY}
# Logement : ${v.HOME_NAME ?? ''}
INTEGRATION_ID=${v.INTEGRATION_ID}

ADAPTER=video
MEDIAMTX=true
LOG_LEVEL=info
`;
}

/** Logements que l'utilisateur gère (propriétaire ou gestionnaire), sans doublon, triés par nom. */
export function manageableHomes(owned, memberships) {
  const byId = new Map();
  for (const h of owned ?? []) byId.set(h.id, { id: h.id, name: h.name });
  for (const m of memberships ?? []) {
    if (!['owner', 'admin'].includes(m.role)) continue;
    const h = m.homes;
    if (h && !byId.has(h.id)) byId.set(h.id, { id: h.id, name: h.name });
  }
  return [...byId.values()].sort((a, b) => a.name.localeCompare(b.name, 'fr'));
}

async function findUserId(db, email) {
  const wanted = email.trim().toLowerCase();
  for (let page = 1; page <= 50; page++) {
    const { data, error } = await db.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw new Error(`Supabase refuse la clé : ${error.message}`);
    const hit = data.users.find((u) => (u.email ?? '').toLowerCase() === wanted);
    if (hit) return hit.id;
    if (data.users.length < 1000) return null;
  }
  return null;
}

async function videoIntegration(db, homeId) {
  const found = await db.from('integrations').select('id').eq('home_id', homeId).eq('provider', 'other').eq('label', VIDEO_LABEL).limit(1);
  if (found.error) throw new Error(found.error.message);
  if (found.data.length) return found.data[0].id;
  const made = await db.from('integrations').insert({ home_id: homeId, provider: 'other', label: VIDEO_LABEL }).select('id').single();
  if (made.error) throw new Error(made.error.message);
  return made.data.id;
}

async function main() {
  const old = existsSync(VIDEO_ENV) ? parseEnv(readFileSync(VIDEO_ENV, 'utf8')) : {};
  const mainEnv = existsSync(MAIN_ENV) ? parseEnv(readFileSync(MAIN_ENV, 'utf8')) : {};
  const out = new Writable({
    write(chunk, enc, cb) {
      if (!out.muted) process.stdout.write(chunk, enc);
      cb();
    },
  });
  const rl = createInterface({ input: process.stdin, output: out, terminal: true, crlfDelay: Infinity });
  const ask = async (question, { secret = false, current = '' } = {}) => {
    const hint = current ? (secret ? ' [Entrée = garder la clé déjà enregistrée]' : ` [${current}]`) : '';
    process.stdout.write(`\n${question}${hint}\n> `);
    out.muted = secret;
    const shownAt = Date.now();
    let answer = (await rl.question('')).trim();
    while (!answer && Date.now() - shownAt < 150) answer = (await rl.question('')).trim();
    out.muted = false;
    if (secret) process.stdout.write(answer ? '(reçue, cachée)\n' : '\n');
    return answer || current;
  };

  console.log('=== Boîtier vidéo Solea : configuration (une seule fois) ===');
  const url = old.SUPABASE_URL || mainEnv.SUPABASE_URL || DEFAULT_SUPABASE_URL;
  const knownKey = old.SUPABASE_SERVICE_ROLE_KEY || mainEnv.SUPABASE_SERVICE_ROLE_KEY || '';
  const key = await ask('1/3  Clé « service_role » de Supabase (supabase.com > projet > Project Settings > API Keys).\n     Collez-la avec un clic droit, elle reste cachée :', { secret: true, current: knownKey });
  if (!key) throw new Error('Clé manquante : relancez Demarrer-Boitier-Video.cmd.');
  const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

  const email = await ask('2/3  E-mail de votre compte Solea :');
  console.log('Recherche de vos logements…');
  const userId = await findUserId(db, email);
  if (!userId) throw new Error(`Aucun compte Solea avec l'e-mail ${email}.`);
  const owned = await db.from('homes').select('id, name').eq('owner_id', userId);
  const members = await db.from('home_members').select('role, homes(id, name)').eq('user_id', userId);
  if (owned.error) throw new Error(owned.error.message);
  const homes = manageableHomes(owned.data, members.data);
  if (!homes.length) throw new Error('Ce compte ne gère aucun logement.');

  console.log('\n3/3  Logement où se trouve ce PC (même Wi-Fi que les caméras) :');
  homes.forEach((h, i) => console.log(`     ${i + 1}. ${h.name}`));
  const current = 1;
  const n = Number.parseInt(await ask('Numéro :', { current: String(current) }), 10);
  const home = homes[(n >= 1 && n <= homes.length ? n : current) - 1];
  rl.close();

  const integrationId = await videoIntegration(db, home.id);
  writeFileSync(VIDEO_ENV, renderVideoEnv({ SUPABASE_URL: url, SUPABASE_SERVICE_ROLE_KEY: key, INTEGRATION_ID: integrationId, HOME_NAME: home.name }), { mode: 0o600 });
  console.log(`\nOK : boîtier vidéo rattaché à « ${home.name} ».`);
}

const isMain = process.argv[1] && resolve(process.argv[1]).toLowerCase() === fileURLToPath(import.meta.url).toLowerCase();
if (isMain) {
  main().catch((e) => {
    console.error(`\n${e.message}`);
    process.exit(1);
  });
}
