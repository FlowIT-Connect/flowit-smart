// Petit client MQTT 3.1.1 (QoS 0), sans dépendance : il suffit pour parler au broker
// Mosquitto de Home Assistant (publier les appareils, recevoir les ordres).
// Reconnexion automatique ; les abonnements sont refaits à chaque connexion.

import { EventEmitter } from 'node:events';
import net from 'node:net';

import { log } from './log.js';

const CONNECT = 1, CONNACK = 2, PUBLISH = 3, SUBSCRIBE = 8, PINGREQ = 12, DISCONNECT = 14;

const CONNACK_ERRORS = {
  1: 'version du protocole refusée',
  2: 'identifiant client refusé',
  3: 'broker indisponible',
  4: 'utilisateur ou mot de passe MQTT incorrect',
  5: 'connexion non autorisée (utilisateur MQTT ?)',
};

function str(s) {
  const b = Buffer.from(String(s), 'utf8');
  const len = Buffer.alloc(2);
  len.writeUInt16BE(b.length);
  return Buffer.concat([len, b]);
}

export function encodeLength(n) {
  const out = [];
  do {
    let byte = n % 128;
    n = Math.floor(n / 128);
    if (n > 0) byte |= 0x80;
    out.push(byte);
  } while (n > 0);
  return Buffer.from(out);
}

export function packet(type, flags, body) {
  return Buffer.concat([Buffer.from([(type << 4) | flags]), encodeLength(body.length), body]);
}

/** Paquets complets lus dans le tampon, et le reste (paquet incomplet). */
export function readPackets(buf) {
  const packets = [];
  let pos = 0;
  while (pos + 2 <= buf.length) {
    let mult = 1, len = 0, i = pos + 1, byte;
    do {
      if (i >= buf.length) return { packets, rest: buf.subarray(pos) };
      byte = buf[i++];
      len += (byte & 0x7f) * mult;
      mult *= 128;
    } while (byte & 0x80);
    if (i + len > buf.length) break;
    packets.push({ type: buf[pos] >> 4, flags: buf[pos] & 0x0f, body: buf.subarray(i, i + len) });
    pos = i + len;
  }
  return { packets, rest: buf.subarray(pos) };
}

export function parseMqttUrl(url) {
  const u = new URL(url);
  if (!['mqtt:', 'tcp:'].includes(u.protocol)) throw new Error(`HA_MQTT_URL doit commencer par mqtt:// (reçu ${u.protocol})`);
  return {
    host: u.hostname,
    port: Number(u.port || 1883),
    username: u.username ? decodeURIComponent(u.username) : null,
    password: u.password ? decodeURIComponent(u.password) : null,
  };
}

export class MqttClient extends EventEmitter {
  /**
   * @param {{host:string, port?:number, username?:string|null, password?:string|null, clientId?:string,
   *          will?:{topic:string, payload:string, retain?:boolean}, keepalive?:number,
   *          connectImpl?:(opts:{host:string,port:number})=>import('node:net').Socket}} opts
   */
  constructor({ host, port = 1883, username = null, password = null, clientId = `solea-${process.pid}`, will = null, keepalive = 60, connectImpl = (o) => net.createConnection(o) }) {
    super();
    Object.assign(this, { host, port, username, password, clientId, will, keepalive, connectImpl });
    this.subscriptions = new Set();
    this.connected = false;
    this.stopped = false;
    this.retryMs = 2000;
    this.packetId = 1;
  }

  start() {
    this.stopped = false;
    this.#open();
  }

  stop() {
    this.stopped = true;
    clearTimeout(this.retryTimer);
    clearInterval(this.pingTimer);
    if (this.socket) {
      if (this.connected) this.socket.write(packet(DISCONNECT, 0, Buffer.alloc(0)));
      this.socket.end();
      this.socket.destroy();
    }
    this.connected = false;
  }

  publish(topic, payload, { retain = false } = {}) {
    if (!this.connected) return false;
    const body = Buffer.concat([str(topic), Buffer.isBuffer(payload) ? payload : Buffer.from(String(payload), 'utf8')]);
    this.socket.write(packet(PUBLISH, retain ? 1 : 0, body));
    return true;
  }

  subscribe(topic) {
    this.subscriptions.add(topic);
    if (this.connected) this.#sendSubscribe(topic);
  }

  #sendSubscribe(topic) {
    const id = Buffer.alloc(2);
    id.writeUInt16BE(this.packetId = (this.packetId % 65535) + 1);
    this.socket.write(packet(SUBSCRIBE, 2, Buffer.concat([id, str(topic), Buffer.from([0])])));
  }

  #open() {
    let buf = Buffer.alloc(0);
    const socket = this.connectImpl({ host: this.host, port: this.port });
    this.socket = socket;
    socket.on('connect', () => socket.write(this.#connectPacket()));
    socket.on('data', (chunk) => {
      buf = Buffer.concat([buf, chunk]);
      const { packets, rest } = readPackets(buf);
      buf = Buffer.from(rest);
      for (const p of packets) this.#handle(p);
    });
    socket.on('error', (e) => {
      if (!this.connected) log.warn('ha_mqtt.connect_failed', { host: this.host, port: this.port, error: e.message });
    });
    socket.on('close', () => {
      const was = this.connected;
      this.connected = false;
      clearInterval(this.pingTimer);
      if (was) {
        log.warn('ha_mqtt.disconnected', { host: this.host });
        this.emit('disconnect');
      }
      if (this.stopped || socket !== this.socket) return;
      this.retryTimer = setTimeout(() => this.#open(), this.retryMs);
      this.retryMs = Math.min(this.retryMs * 2, 60_000);
    });
  }

  #connectPacket() {
    let flags = 0x02; // session propre
    if (this.will) flags |= 0x04 | (this.will.retain ? 0x20 : 0);
    if (this.username) flags |= 0x80;
    if (this.password) flags |= 0x40;
    const ka = Buffer.alloc(2);
    ka.writeUInt16BE(this.keepalive);
    const parts = [str('MQTT'), Buffer.from([4, flags]), ka, str(this.clientId)];
    if (this.will) parts.push(str(this.will.topic), str(this.will.payload));
    if (this.username) parts.push(str(this.username));
    if (this.password) parts.push(str(this.password));
    return packet(CONNECT, 0, Buffer.concat(parts));
  }

  #handle({ type, body }) {
    if (type === CONNACK) {
      const code = body[1];
      if (code !== 0) {
        log.error('ha_mqtt.refused', { error: CONNACK_ERRORS[code] ?? `code ${code}` });
        this.socket.destroy();
        return;
      }
      this.connected = true;
      this.retryMs = 2000;
      for (const t of this.subscriptions) this.#sendSubscribe(t);
      this.pingTimer = setInterval(() => this.socket.write(packet(PINGREQ, 0, Buffer.alloc(0))), (this.keepalive * 1000) / 2);
      log.info('ha_mqtt.connected', { host: this.host, port: this.port });
      this.emit('connect');
    } else if (type === PUBLISH) {
      const len = body.readUInt16BE(0);
      const topic = body.subarray(2, 2 + len).toString('utf8');
      this.emit('message', topic, body.subarray(2 + len).toString('utf8')); // QoS 0 : pas d'identifiant
    }
    // SUBACK, PINGRESP : rien à faire.
  }
}
