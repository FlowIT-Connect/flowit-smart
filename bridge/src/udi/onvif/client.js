// Client ONVIF minimal (SOAP 1.2 + WS-Security UsernameToken « PasswordDigest »).
// Couvre ce dont Solea a besoin pour une caméra ou un visiophone ONVIF Profile S / T :
// identification, capacités, profils, adresse RTSP, image fixe et événements (mouvement).

import { createHash, randomBytes, randomUUID } from 'node:crypto';

import { escapeXml, find, findAll, parseXml, path, textOf } from '../xml.js';

const NS = {
  soap: 'http://www.w3.org/2003/05/soap-envelope',
  wsse: 'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd',
  wsu: 'http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd',
  wsa: 'http://www.w3.org/2005/08/addressing',
  tds: 'http://www.onvif.org/ver10/device/wsdl',
  trt: 'http://www.onvif.org/ver10/media/wsdl',
  tev: 'http://www.onvif.org/ver10/events/wsdl',
  tt: 'http://www.onvif.org/ver10/schema',
};

export class OnvifError extends Error {
  /** @param {string} message @param {{code?:string, status?:number}} [info] */
  constructor(message, { code, status } = {}) {
    super(message);
    this.code = code ?? null;
    this.status = status ?? null;
  }
  get isAuth() {
    return this.status === 401 || /NotAuthorized|FailedAuthentication|Sender\b.*auth/i.test(`${this.code} ${this.message}`);
  }
}

/** Jeton WS-Security : Digest = Base64(SHA1(nonce + created + mot de passe)). */
export function usernameToken(username, password, created, nonce = randomBytes(16)) {
  const digest = createHash('sha1').update(Buffer.concat([nonce, Buffer.from(created), Buffer.from(password)])).digest('base64');
  return (
    `<wsse:Security s:mustUnderstand="1" xmlns:wsse="${NS.wsse}" xmlns:wsu="${NS.wsu}"><wsse:UsernameToken>` +
    `<wsse:Username>${escapeXml(username)}</wsse:Username>` +
    `<wsse:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">${digest}</wsse:Password>` +
    `<wsse:Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-soap-message-security-1.0#Base64Binary">${nonce.toString('base64')}</wsse:Nonce>` +
    `<wsu:Created>${created}</wsu:Created></wsse:UsernameToken></wsse:Security>`
  );
}

export function envelope(body, { security = '', addressing = '' } = {}) {
  return (
    `<?xml version="1.0" encoding="UTF-8"?><s:Envelope xmlns:s="${NS.soap}" xmlns:tds="${NS.tds}" xmlns:trt="${NS.trt}" ` +
    `xmlns:tev="${NS.tev}" xmlns:tt="${NS.tt}" xmlns:wsa="${NS.wsa}"><s:Header>${security}${addressing}</s:Header><s:Body>${body}</s:Body></s:Envelope>`
  );
}

/** Données d'un message d'événement ONVIF : { topic, time, source:{}, data:{} }. */
export function parseNotifications(doc) {
  return findAll(doc, 'NotificationMessage').map((msg) => {
    const items = (parent) => {
      const out = {};
      for (const it of findAll(parent, 'SimpleItem')) if (it.attrs.Name) out[it.attrs.Name] = it.attrs.Value ?? '';
      return out;
    };
    const message = path(msg, 'Message', 'Message') ?? find(msg, 'Message');
    return {
      topic: textOf(msg, 'Topic') ?? '',
      time: message?.attrs.UtcTime ?? null,
      source: items(find(message, 'Source')),
      data: items(find(message, 'Data')),
    };
  });
}

/**
 * Interprète un événement de mouvement (VideoSource/MotionAlarm, RuleEngine/CellMotionDetector,
 * détection humaine des modèles récents). Renvoie true/false, ou null si ce n'est pas du mouvement.
 */
export function motionFromNotification(n) {
  if (!/motion|human|people|person/i.test(n.topic)) return null;
  for (const key of ['IsMotion', 'State', 'IsPeople', 'IsHuman', 'Value']) {
    const v = n.data[key];
    if (v === undefined) continue;
    if (/^(true|1|on)$/i.test(v)) return true;
    if (/^(false|0|off)$/i.test(v)) return false;
  }
  return null;
}

export class OnvifClient {
  /**
   * @param {{host:string, port?:number, username?:string, password?:string, https?:boolean,
   *          fetchImpl?:typeof fetch, timeoutMs?:number, deviceUrl?:string}} opts
   */
  constructor({ host, port = 80, username = '', password = '', https = false, fetchImpl = (...a) => fetch(...a), timeoutMs = 8000, deviceUrl } = {}) {
    this.username = username;
    this.password = password;
    this.fetchImpl = fetchImpl;
    this.timeoutMs = timeoutMs;
    this.deviceUrl = deviceUrl ?? `${https ? 'https' : 'http'}://${host}:${port}/onvif/device_service`;
    this.clockOffsetMs = 0;
    this.services = { media: null, events: null, ptz: null, deviceio: null };
  }

  /** Remplace l'hôte annoncé par l'appareil quand il est faux (caméra derrière NAT, IP changée). */
  #fixHost(xaddr) {
    if (!xaddr) return null;
    try {
      const announced = new URL(xaddr);
      const real = new URL(this.deviceUrl);
      announced.host = real.host;
      announced.protocol = real.protocol;
      return announced.toString();
    } catch {
      return null;
    }
  }

  #security() {
    if (!this.username) return '';
    const created = new Date(Date.now() + this.clockOffsetMs).toISOString().replace(/\.\d{3}Z$/, 'Z');
    return usernameToken(this.username, this.password, created);
  }

  async call(url, body, { auth = true, action, addressing = '' } = {}) {
    const xml = envelope(body, { security: auth ? this.#security() : '', addressing });
    let res;
    try {
      res = await this.fetchImpl(url, {
        method: 'POST',
        headers: { 'Content-Type': `application/soap+xml; charset=utf-8${action ? `; action="${action}"` : ''}` },
        body: xml,
        signal: AbortSignal.timeout(this.timeoutMs),
      });
    } catch (e) {
      throw new OnvifError(`Appareil injoignable (${e.name === 'TimeoutError' ? 'délai dépassé' : e.message})`);
    }
    const text = await res.text();
    let doc = null;
    try {
      doc = parseXml(text);
    } catch {
      /* réponse non XML : traitée ci-dessous */
    }
    const fault = doc && find(doc, 'Fault');
    if (fault || !res.ok) {
      const code = [...findAll(fault, 'Value')].map((v) => v.text.trim()).filter(Boolean).pop() ?? null;
      const reason = textOf(fault, 'Text') ?? `HTTP ${res.status}`;
      throw new OnvifError(`ONVIF : ${reason}`, { code, status: res.status });
    }
    if (!doc) throw new OnvifError('ONVIF : réponse illisible');
    return doc;
  }

  /** Heure de l'appareil : le jeton WS-Security est refusé si l'écart dépasse quelques secondes. */
  async syncClock() {
    const doc = await this.call(this.deviceUrl, '<tds:GetSystemDateAndTime/>', { auth: false });
    const utc = find(doc, 'UTCDateTime');
    if (!utc) return null;
    const n = (name) => Number(textOf(utc, name));
    const device = Date.UTC(n('Year'), n('Month') - 1, n('Day'), n('Hour'), n('Minute'), n('Second'));
    if (Number.isFinite(device)) this.clockOffsetMs = device - Date.now();
    return this.clockOffsetMs;
  }

  async getDeviceInformation() {
    const doc = await this.call(this.deviceUrl, '<tds:GetDeviceInformation/>');
    return {
      manufacturer: textOf(doc, 'Manufacturer'),
      model: textOf(doc, 'Model'),
      firmware: textOf(doc, 'FirmwareVersion'),
      serial: textOf(doc, 'SerialNumber'),
      hardwareId: textOf(doc, 'HardwareId'),
    };
  }

  async getCapabilities() {
    const doc = await this.call(this.deviceUrl, '<tds:GetCapabilities><tds:Category>All</tds:Category></tds:GetCapabilities>');
    const caps = find(doc, 'Capabilities');
    const xaddr = (name) => this.#fixHost(textOf(find(caps, name), 'XAddr'));
    this.services = { media: xaddr('Media'), events: xaddr('Events'), ptz: xaddr('PTZ'), deviceio: xaddr('DeviceIO') };
    const io = find(caps, 'DeviceIO');
    return {
      services: { ...this.services },
      pullPoint: /true/i.test(textOf(find(caps, 'Events'), 'WSPullPointSupport') ?? ''),
      relayOutputs: Number(textOf(io, 'RelayOutputs') ?? 0),
      audioOutputs: Number(textOf(io, 'AudioOutputs') ?? 0),
      audioSources: Number(textOf(io, 'AudioSources') ?? 0),
    };
  }

  async getProfiles() {
    const doc = await this.call(this.services.media ?? this.deviceUrl, '<trt:GetProfiles/>');
    return findAll(doc, 'Profiles').map((p) => {
      const venc = find(p, 'VideoEncoderConfiguration');
      const res = find(venc, 'Resolution');
      return {
        token: p.attrs.token,
        name: textOf(p, 'Name') ?? p.attrs.token,
        encoding: textOf(venc, 'Encoding'),
        width: Number(textOf(res, 'Width')) || null,
        height: Number(textOf(res, 'Height')) || null,
        audio: Boolean(find(p, 'AudioEncoderConfiguration')),
        audioOutput: Boolean(find(p, 'AudioOutputConfiguration')),
        ptz: Boolean(find(p, 'PTZConfiguration')),
      };
    });
  }

  async getStreamUri(profileToken) {
    const doc = await this.call(
      this.services.media ?? this.deviceUrl,
      '<trt:GetStreamUri><trt:StreamSetup><tt:Stream>RTP-Unicast</tt:Stream><tt:Transport><tt:Protocol>RTSP</tt:Protocol></tt:Transport></trt:StreamSetup>' +
        `<trt:ProfileToken>${escapeXml(profileToken)}</trt:ProfileToken></trt:GetStreamUri>`,
    );
    return this.#fixHost(textOf(doc, 'Uri'));
  }

  async getSnapshotUri(profileToken) {
    const doc = await this.call(
      this.services.media ?? this.deviceUrl,
      `<trt:GetSnapshotUri><trt:ProfileToken>${escapeXml(profileToken)}</trt:ProfileToken></trt:GetSnapshotUri>`,
    );
    return this.#fixHost(textOf(doc, 'Uri'));
  }

  /** Abonnement « pull point » : renvoie l'adresse à interroger. */
  async createPullPoint(terminationSeconds = 120) {
    const doc = await this.call(
      this.services.events ?? this.deviceUrl,
      `<tev:CreatePullPointSubscription><tev:InitialTerminationTime>PT${terminationSeconds}S</tev:InitialTerminationTime></tev:CreatePullPointSubscription>`,
    );
    const address = this.#fixHost(textOf(find(doc, 'SubscriptionReference'), 'Address'));
    if (!address) throw new OnvifError('ONVIF : abonnement aux événements refusé');
    return address;
  }

  #addressing(to, action) {
    return `<wsa:Action>${action}</wsa:Action><wsa:MessageID>urn:uuid:${randomUUID()}</wsa:MessageID><wsa:To>${escapeXml(to)}</wsa:To>`;
  }

  async pullMessages(address, { timeoutSeconds = 10, limit = 20 } = {}) {
    const action = 'http://www.onvif.org/ver10/events/wsdl/PullPointSubscription/PullMessagesRequest';
    const doc = await this.call(
      address,
      `<tev:PullMessages><tev:Timeout>PT${timeoutSeconds}S</tev:Timeout><tev:MessageLimit>${limit}</tev:MessageLimit></tev:PullMessages>`,
      { action, addressing: this.#addressing(address, action) },
    );
    return parseNotifications(doc);
  }

  async renew(address, terminationSeconds = 120) {
    const action = 'http://docs.oasis-open.org/wsn/bw-2/SubscriptionManager/RenewRequest';
    await this.call(
      address,
      `<wsnt:Renew xmlns:wsnt="http://docs.oasis-open.org/wsn/b-2"><wsnt:TerminationTime>PT${terminationSeconds}S</wsnt:TerminationTime></wsnt:Renew>`,
      { action, addressing: this.#addressing(address, action) },
    );
  }

  async unsubscribe(address) {
    const action = 'http://docs.oasis-open.org/wsn/bw-2/SubscriptionManager/UnsubscribeRequest';
    await this.call(address, '<wsnt:Unsubscribe xmlns:wsnt="http://docs.oasis-open.org/wsn/b-2"/>', {
      action,
      addressing: this.#addressing(address, action),
    }).catch(() => {});
  }
}
