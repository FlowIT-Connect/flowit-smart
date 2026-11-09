// Diagnostic approfondi d'une caméra Dahua (Hero, Imou, IPC) depuis le boîtier vidéo :
//   node --env-file=.env.video src/diag_dahua.js                (lecture seule)
//   node --env-file=.env.video src/diag_dahua.js --activer-rtsp (réactive le RTSP s'il est coupé)
//
// Lit l'adresse et le code de sécurité dans Solea (comme le boîtier), puis teste : portes
// ouvertes, API HTTP cachée (CGI), réglage RTSP, ONVIF, flux RTSP et image fixe.
// Le code de sécurité n'est jamais affiché ni écrit. Rapport : diag-dahua.txt.

import net from 'node:net';
import { writeFileSync } from 'node:fs';

import { SupabaseStore } from './store.js';
import { fetchWithAuth } from './udi/auth.js';
import { discoverDahua, sameSerial } from './udi/dahua/dhip.js';
import { OnvifClient } from './udi/onvif/client.js';
import { probeRtsp } from './udi/rtsp.js';

const PORTS = [80, 443, 554, 8554, 10554, 37777, 37778, 37810, 8000, 8080, 8086, 9000, 34567];

export function redact(text, secrets) {
  let out = String(text ?? '');
  for (const s of secrets.filter((x) => x && x.length >= 3)) {
    out = out.split(s).join('***');
    out = out.split(encodeURIComponent(s)).join('***');
    out = out.split(Buffer.from(`admin:${s}`).toString('base64')).join('***');
  }
  return out.replace(/\/\/[^/@\s]+:[^/@\s]+@/g, '//***:***@');
}

/** Lignes « table.RTSP.Enable=false » → { 'RTSP.Enable': 'false' }. */
export function parseConfig(text) {
  const out = {};
  for (const line of String(text).split(/\r?\n/)) {
    const m = /^(?:table\.)?([\w.[\]]+)=(.*)$/.exec(line.trim());
    if (m) out[m[1]] = m[2];
  }
  return out;
}

function portOpen(host, port, timeoutMs = 1500) {
  return new Promise((resolve) => {
    const s = net.connect({ host, port });
    const done = (ok) => {
      s.destroy();
      resolve(ok);
    };
    s.setTimeout(timeoutMs, () => done(false));
    s.once('connect', () => done(true));
    s.once('error', () => done(false));
  });
}

async function main() {
  const activate = process.argv.includes('--activer-rtsp');
  const lines = [];
  const say = (t = '') => {
    lines.push(t);
    console.log(t);
  };

  const store = new SupabaseStore(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
  const integ = await store.getIntegration(process.env.INTEGRATION_ID);
  if (!integ) throw new Error('Intégration du boîtier introuvable (fichier .env.video)');
  const sources = (await store.listVideoSources(integ.home_id)).filter((s) => s.driver === 'dahua' || /dahua/i.test(s.manufacturer ?? ''));
  if (!sources.length) throw new Error('Aucune caméra Dahua dans ce logement : ajoutez-la d\'abord dans Solea (Scanner le QR code)');

  const secrets = sources.map((s) => s.password);
  const found = await discoverDahua({ timeoutMs: 3000 }).catch(() => []);

  for (const src of sources) {
    const user = src.username || 'admin';
    const pass = src.password ?? '';
    const creds = { username: user, password: pass };
    const host = src.host || found.find((d) => sameSerial(d.serial, src.serial))?.host;
    say(`=== ${src.name} (${src.model ?? '?'}, n° ${src.serial ?? '?'}) ===`);
    if (!host) {
      say('Introuvable sur le réseau (recherche Dahua sans réponse).');
      continue;
    }
    say(`Adresse : ${host}`);

    // 1. Portes
    const open = [];
    for (const p of PORTS) if (await portOpen(host, p)) open.push(p);
    say(`Portes ouvertes : ${open.join(', ') || 'aucune'}`);

    // 2. API HTTP cachée
    const cgi = async (path) => {
      try {
        const res = await fetchWithAuth((...a) => fetch(...a), `http://${host}${path}`, { signal: AbortSignal.timeout(6000) }, creds);
        const type = res.headers.get('content-type') ?? '';
        const body = type.startsWith('image/') ? `(image ${(await res.arrayBuffer()).byteLength} octets)` : (await res.text()).slice(0, 1500);
        return { status: res.status, body };
      } catch (e) {
        return { status: 0, body: e.message };
      }
    };
    for (const path of [
      '/cgi-bin/magicBox.cgi?action=getDeviceType',
      '/cgi-bin/magicBox.cgi?action=getSoftwareVersion',
      '/cgi-bin/magicBox.cgi?action=getProductDefinition',
      '/cgi-bin/configManager.cgi?action=getConfig&name=RTSP',
      '/cgi-bin/configManager.cgi?action=getConfig&name=Multicast',
      '/cgi-bin/snapshot.cgi?channel=1',
      '/onvifsnapshot/media_service/snapshot?channel=1&subtype=0',
    ]) {
      const r = await cgi(path);
      say(`HTTP ${path} → ${r.status}`);
      say(redact(r.body, secrets).split('\n').map((l) => `    ${l}`).join('\n'));
    }

    // 3. Réglage RTSP
    const rtspCfg = parseConfig((await cgi('/cgi-bin/configManager.cgi?action=getConfig&name=RTSP')).body);
    if (rtspCfg['RTSP.Enable'] === 'false') {
      say('Le RTSP est COUPÉ dans les réglages de la caméra.');
      if (activate) {
        const r = await cgi('/cgi-bin/configManager.cgi?action=setConfig&RTSP.Enable=true');
        say(`Réactivation du RTSP → ${r.status} ${redact(r.body, secrets).trim()}`);
      } else {
        say('Pour le réactiver : relancer avec --activer-rtsp');
      }
    }

    // 4. ONVIF
    try {
      const client = new OnvifClient({ host, port: 80, username: user, password: pass, fetchImpl: (...a) => fetch(...a) });
      await client.syncClock().catch(() => null);
      const info = await client.getDeviceInformation();
      say(`ONVIF : ${info.manufacturer ?? '?'} ${info.model ?? '?'} firmware ${info.firmware ?? '?'}`);
      await client.getCapabilities();
      for (const p of await client.getProfiles()) {
        const uri = await client.getStreamUri(p.token).catch((e) => `erreur ${e.message}`);
        const snap = await client.getSnapshotUri(p.token).catch(() => null);
        say(`  profil ${p.token} ${p.encoding ?? ''} ${p.width ?? '?'}x${p.height ?? '?'} → ${redact(uri, secrets)}${snap ? ` | image ${redact(snap, secrets)}` : ''}`);
      }
    } catch (e) {
      say(`ONVIF : ${redact(e.message, secrets)}`);
    }

    // 5. Flux RTSP
    const rtspPorts = open.filter((p) => [554, 8554, 10554].includes(p));
    for (const port of rtspPorts.length ? rtspPorts : [554]) {
      for (const path of ['/cam/realmonitor?channel=1&subtype=1', '/cam/realmonitor?channel=1&subtype=0', '/live', '/']) {
        for (const basicFirst of [false, true]) {
          const r = await probeRtsp(`rtsp://${host}:${port}${path}`, { ...creds, basicFirst, timeoutMs: 4000 });
          say(`RTSP :${port}${path}${basicFirst ? ' (Basic d\'emblée)' : ''} → ${r.ok ? `OK vidéo ${r.video?.codec ?? '?'}` : redact(r.error, secrets)}`);
          if (r.ok) break;
        }
      }
    }
    say();
  }
  writeFileSync('diag-dahua.txt', lines.join('\n'));
  console.log('Rapport enregistré dans diag-dahua.txt (sans le code de sécurité).');
}

const isMain = process.argv[1] && /diag_dahua\.js$/.test(process.argv[1]);
if (isMain) {
  main().catch((e) => {
    console.error(e.message);
    process.exit(1);
  });
}
