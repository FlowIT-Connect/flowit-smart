// Découverte Dahua (« DHIP », port UDP 37810) : c'est la méthode de l'outil ConfigTool de Dahua.
// Elle trouve aussi les caméras grand public (gammes Hero, Imou) qui ne répondent pas forcément
// en ONVIF. Chaque réponse donne l'adresse IP, le numéro de série, l'adresse MAC et le modèle :
// le numéro de série lu dans le QR code de l'étiquette suffit donc à retrouver la caméra.
//
// Format d'un paquet : en-tête de 32 octets (« DHIP », longueur du JSON deux fois) puis le JSON.
// Rien ne sort du réseau local.

import dgram from 'node:dgram';

export const DHIP = { port: 37810, multicast: '239.255.255.251', broadcast: '255.255.255.255' };

/** Paquet DHIP contenant `payload` (objet JSON). */
export function dhipPacket(payload) {
  const body = Buffer.from(JSON.stringify(payload), 'utf8');
  const head = Buffer.alloc(32);
  head.writeUInt32LE(0x20, 0);
  head.write('DHIP', 4, 'ascii');
  // 8 octets de session à zéro, puis la longueur, 4 octets à zéro, la longueur, 4 octets à zéro.
  head.writeUInt32LE(body.length, 16);
  head.writeUInt32LE(body.length, 24);
  return Buffer.concat([head, body]);
}

export const searchPacket = () => dhipPacket({ method: 'DHDiscover.search', params: { mac: '', uni: 1 } });

const normMac = (m) => (m ? String(m).toLowerCase().replace(/[^0-9a-f]/g, '').replace(/(..)(?!$)/g, '$1:') : null);
export const sameSerial = (a, b) => Boolean(a && b) && String(a).trim().toUpperCase() === String(b).trim().toUpperCase();

/**
 * Réponse DHIP → { host, serial, mac, model, httpPort, name } ou null (datagramme étranger,
 * ou notre propre requête de recherche renvoyée par le multicast).
 */
export function parseDhipReply(buf, fallbackHost = null) {
  if (!Buffer.isBuffer(buf) || buf.length < 34 || buf.toString('ascii', 4, 8) !== 'DHIP') return null;
  const text = buf.subarray(32).toString('utf8');
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start === -1 || end <= start) return null;
  let json;
  try {
    json = JSON.parse(text.slice(start, end + 1));
  } catch {
    return null;
  }
  const info = json?.params?.deviceInfo;
  if (!info || typeof info !== 'object') return null;
  const host = info.IPv4Address?.IPAddress ?? fallbackHost;
  if (!host || !/^\d+\.\d+\.\d+\.\d+$/.test(host)) return null;
  return {
    host,
    serial: info.SerialNo ? String(info.SerialNo).trim() : null,
    mac: normMac(info.Mac ?? json.mac),
    model: info.DeviceType ?? info.DetailType ?? null,
    httpPort: Number(info.HttpPort) || 80,
    name: info.MachineName ?? info.DeviceType ?? null,
    vendor: info.Vendor ?? 'Dahua',
  };
}

/**
 * Lance une recherche DHIP et renvoie les appareils trouvés (dédoublonnés par numéro de série
 * ou adresse) dans les sous-réseaux autorisés.
 * @param {{timeoutMs?:number, allowed?:(ip:string)=>boolean, socketFactory?:()=>any}} [opts]
 */
export function discoverDahua({ timeoutMs = 3000, allowed = () => true, socketFactory = () => dgram.createSocket({ type: 'udp4', reuseAddr: true }) } = {}) {
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
      const d = parseDhipReply(buf, rinfo?.address ?? null);
      if (!d || !allowed(d.host)) return;
      const key = d.serial ?? d.host;
      if (!found.has(key)) found.set(key, d);
    });
    socket.on('error', finish);
    // Les caméras répondent sur le groupe multicast, port 37810 : on écoute ce port.
    socket.bind(DHIP.port, () => {
      try {
        socket.setBroadcast?.(true);
        socket.addMembership?.(DHIP.multicast);
      } catch {
        /* pas de multicast sur cette interface : la diffusion suffit souvent */
      }
      const msg = searchPacket();
      socket.send(msg, 0, msg.length, DHIP.port, DHIP.multicast);
      socket.send(msg, 0, msg.length, DHIP.port, DHIP.broadcast);
    });
    setTimeout(finish, timeoutMs);
  });
}
