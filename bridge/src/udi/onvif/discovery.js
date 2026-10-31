// Découverte ONVIF (WS-Discovery) : une sonde multicast UDP 239.255.255.250:3702 sur le réseau
// local. Les caméras et visiophones ONVIF répondent avec leur adresse de service et leurs
// « scopes » (nom, modèle). Rien ne sort du réseau local ; seuls les sous-réseaux autorisés
// par l'administrateur sont retenus.

import dgram from 'node:dgram';
import { randomUUID } from 'node:crypto';

import { findAll, parseXml, textOf } from '../xml.js';

export const WS_DISCOVERY = { address: '239.255.255.250', port: 3702 };

export function probeMessage(type, messageId = randomUUID()) {
  return (
    '<?xml version="1.0" encoding="UTF-8"?>' +
    '<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope" xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing" ' +
    'xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery" xmlns:dn="http://www.onvif.org/ver10/network/wsdl" ' +
    'xmlns:tds="http://www.onvif.org/ver10/device/wsdl"><e:Header>' +
    `<w:MessageID>uuid:${messageId}</w:MessageID>` +
    '<w:To e:mustUnderstand="true">urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>' +
    '<w:Action e:mustUnderstand="true">http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>' +
    `</e:Header><e:Body><d:Probe><d:Types>${type}</d:Types></d:Probe></e:Body></e:Envelope>`
  );
}

const scopeValue = (scopes, key) => {
  const s = scopes.find((x) => x.toLowerCase().startsWith(`onvif://www.onvif.org/${key}/`));
  return s ? decodeURIComponent(s.split('/').slice(4).join('/')) : null;
};

/** Réponses ProbeMatch d'un datagramme → [{ endpoint, xaddrs, host, port, name, hardware, scopes }]. */
export function parseProbeMatches(xml) {
  const doc = parseXml(xml);
  return findAll(doc, 'ProbeMatch').map((m) => {
    const xaddrs = (textOf(m, 'XAddrs') ?? '').split(/\s+/).filter(Boolean);
    const scopes = (textOf(m, 'Scopes') ?? '').split(/\s+/).filter(Boolean);
    // Préfère une adresse IPv4 en http.
    const xaddr = xaddrs.find((x) => /^http:\/\/\d+\.\d+\.\d+\.\d+/.test(x)) ?? xaddrs[0] ?? null;
    let host = null;
    let port = null;
    try {
      const u = new URL(xaddr);
      host = u.hostname;
      port = Number(u.port) || (u.protocol === 'https:' ? 443 : 80);
    } catch {
      /* adresse absente */
    }
    return {
      endpoint: textOf(m, 'Address'),
      xaddrs,
      xaddr,
      host,
      port,
      name: scopeValue(scopes, 'name'),
      hardware: scopeValue(scopes, 'hardware'),
      types: textOf(m, 'Types'),
      scopes,
    };
  });
}

const ipToInt = (ip) => ip.split('.').reduce((acc, p) => (acc << 8) + Number(p), 0) >>> 0;

/** « 192.168.1.0/24, 10.0.0.0/8 » → fonction (ip) => bool. Liste vide = tout le réseau local privé. */
export function subnetFilter(spec) {
  const parts = String(spec ?? '')
    .split(/[,;\s]+/)
    .filter(Boolean);
  const nets = (parts.length ? parts : ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16']).map((cidr) => {
    const [base, bitsRaw] = cidr.split('/');
    if (!/^\d+\.\d+\.\d+\.\d+$/.test(base)) throw new Error(`Sous-réseau invalide : ${cidr}`);
    const bits = bitsRaw === undefined ? 32 : Number(bitsRaw);
    if (!(bits >= 0 && bits <= 32)) throw new Error(`Sous-réseau invalide : ${cidr}`);
    const mask = bits === 0 ? 0 : (0xffffffff << (32 - bits)) >>> 0;
    return { net: ipToInt(base) & mask, mask };
  });
  return (ip) => /^\d+\.\d+\.\d+\.\d+$/.test(ip ?? '') && nets.some((n) => (ipToInt(ip) & n.mask) >>> 0 === n.net >>> 0);
}

/**
 * Lance une découverte et renvoie les appareils trouvés (dédoublonnés) dans les sous-réseaux autorisés.
 * @param {{timeoutMs?:number, allowed?:(ip:string)=>boolean, socketFactory?:()=>any}} [opts]
 */
export function discoverOnvif({ timeoutMs = 4000, allowed = subnetFilter(''), socketFactory = () => dgram.createSocket({ type: 'udp4', reuseAddr: true }) } = {}) {
  return new Promise((resolve) => {
    const found = new Map();
    const socket = socketFactory();
    let done = false;
    const finish = () => {
      if (done) return;
      done = true;
      try {
        socket.close();
      } catch {
        /* déjà fermé */
      }
      resolve([...found.values()]);
    };
    socket.on('message', (buf, rinfo) => {
      let matches = [];
      try {
        matches = parseProbeMatches(buf.toString('utf8'));
      } catch {
        return; // datagramme étranger
      }
      for (const m of matches) {
        const host = m.host ?? rinfo?.address;
        if (!allowed(host)) continue;
        const key = m.endpoint ?? `${host}:${m.port}`;
        if (!found.has(key)) found.set(key, { ...m, host });
      }
    });
    socket.on('error', finish);
    socket.bind(0, () => {
      for (const type of ['dn:NetworkVideoTransmitter', 'tds:Device']) {
        const msg = Buffer.from(probeMessage(type));
        socket.send(msg, 0, msg.length, WS_DISCOVERY.port, WS_DISCOVERY.address);
      }
    });
    setTimeout(finish, timeoutMs);
  });
}
