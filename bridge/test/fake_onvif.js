// Caméra ONVIF simulée pour les tests : répond aux requêtes SOAP comme une vraie caméra
// (vérifie le jeton WS-Security), sert une image fixe protégée par Digest et des événements.
import { createHash } from 'node:crypto';

import { simulatedFrame } from '../src/png.js';
import { parseXml, find, textOf } from '../src/udi/xml.js';

const ok = (body) =>
  new Response(
    `<?xml version="1.0"?><SOAP-ENV:Envelope xmlns:SOAP-ENV="http://www.w3.org/2003/05/soap-envelope" xmlns:tt="http://www.onvif.org/ver10/schema" ` +
      `xmlns:tds="http://www.onvif.org/ver10/device/wsdl" xmlns:trt="http://www.onvif.org/ver10/media/wsdl" xmlns:tev="http://www.onvif.org/ver10/events/wsdl" ` +
      `xmlns:wsnt="http://docs.oasis-open.org/wsn/b-2" xmlns:wsa5="http://www.w3.org/2005/08/addressing" xmlns:tns1="http://www.onvif.org/ver10/topics">` +
      `<SOAP-ENV:Body>${body}</SOAP-ENV:Body></SOAP-ENV:Envelope>`,
    { status: 200, headers: { 'content-type': 'application/soap+xml' } },
  );
const fault = (reason, status = 400, code = 'ter:NotAuthorized') =>
  new Response(
    `<?xml version="1.0"?><env:Envelope xmlns:env="http://www.w3.org/2003/05/soap-envelope" xmlns:ter="http://www.onvif.org/ver10/error"><env:Body><env:Fault>` +
      `<env:Code><env:Value>env:Sender</env:Value><env:Subcode><env:Value>${code}</env:Value></env:Subcode></env:Code>` +
      `<env:Reason><env:Text xml:lang="en">${reason}</env:Text></env:Reason></env:Fault></env:Body></env:Envelope>`,
    { status },
  );

export class FakeOnvifCamera {
  constructor({ host = '192.168.1.20', port = 80, username = 'admin', password = 'S3cret!', clockSkewMs = 0, relayOutputs = 1, digestSnapshot = true } = {}) {
    Object.assign(this, { host, port, username, password, clockSkewMs, relayOutputs, digestSnapshot });
    this.calls = [];
    this.pending = []; // événements en attente pour PullMessages
    this.online = true;
    this.base = `http://${host}:${port}`;
  }

  motion(value) {
    this.pending.push(value);
  }

  #authOk(doc) {
    const token = find(doc, 'UsernameToken');
    if (!token) return false;
    const nonce = Buffer.from(textOf(token, 'Nonce') ?? '', 'base64');
    const created = textOf(token, 'Created') ?? '';
    const expected = createHash('sha1').update(Buffer.concat([nonce, Buffer.from(created), Buffer.from(this.password)])).digest('base64');
    const skew = Math.abs(Date.parse(created) - (Date.now() + this.clockSkewMs));
    return textOf(token, 'Username') === this.username && textOf(token, 'Password') === expected && skew < 30_000;
  }

  fetch = async (url, init = {}) => {
    if (!this.online) throw new TypeError('fetch failed');
    const u = new URL(url);
    if (u.pathname === '/snapshot.jpg') return this.#snapshot(init);
    const doc = parseXml(String(init.body ?? ''));
    const body = find(doc, 'Body');
    const method = body?.children[0]?.name;
    this.calls.push(method);
    if (method === 'GetSystemDateAndTime') {
      const d = new Date(Date.now() + this.clockSkewMs);
      return ok(
        `<tds:GetSystemDateAndTimeResponse><tds:SystemDateAndTime><tt:UTCDateTime><tt:Time><tt:Hour>${d.getUTCHours()}</tt:Hour><tt:Minute>${d.getUTCMinutes()}</tt:Minute>` +
          `<tt:Second>${d.getUTCSeconds()}</tt:Second></tt:Time><tt:Date><tt:Year>${d.getUTCFullYear()}</tt:Year><tt:Month>${d.getUTCMonth() + 1}</tt:Month><tt:Day>${d.getUTCDate()}</tt:Day></tt:Date>` +
          '</tt:UTCDateTime></tds:SystemDateAndTime></tds:GetSystemDateAndTimeResponse>',
      );
    }
    if (!this.#authOk(doc)) return fault('Sender not Authorized', 400);
    switch (method) {
      case 'GetDeviceInformation':
        return ok('<tds:GetDeviceInformationResponse><tds:Manufacturer>HIKVISION</tds:Manufacturer><tds:Model>DS-2CD1043G2-I</tds:Model><tds:FirmwareVersion>V5.7.1 build 220715</tds:FirmwareVersion><tds:SerialNumber>DS-2CD1043G2-I20220801</tds:SerialNumber><tds:HardwareId>88</tds:HardwareId></tds:GetDeviceInformationResponse>');
      case 'GetCapabilities':
        // Adresses annoncées avec une mauvaise IP (caméra derrière un autre réseau) : le client doit les corriger.
        return ok(
          '<tds:GetCapabilitiesResponse><tds:Capabilities>' +
            '<tt:Device><tt:XAddr>http://10.0.0.99/onvif/device_service</tt:XAddr></tt:Device>' +
            '<tt:Events><tt:XAddr>http://10.0.0.99/onvif/Events</tt:XAddr><tt:WSSubscriptionPolicySupport>true</tt:WSSubscriptionPolicySupport><tt:WSPullPointSupport>true</tt:WSPullPointSupport></tt:Events>' +
            '<tt:Media><tt:XAddr>http://10.0.0.99/onvif/Media</tt:XAddr></tt:Media>' +
            `<tt:Extension><tt:DeviceIO><tt:XAddr>http://10.0.0.99/onvif/DeviceIO</tt:XAddr><tt:VideoSources>1</tt:VideoSources><tt:AudioOutputs>0</tt:AudioOutputs><tt:AudioSources>1</tt:AudioSources><tt:RelayOutputs>${this.relayOutputs}</tt:RelayOutputs></tt:DeviceIO></tt:Extension>` +
            '</tds:Capabilities></tds:GetCapabilitiesResponse>',
        );
      case 'GetProfiles':
        if (u.pathname !== '/onvif/Media') return fault('wrong service', 400, 'ter:ActionNotSupported');
        return ok(
          '<trt:GetProfilesResponse>' +
            '<trt:Profiles token="Profile_1" fixed="true"><tt:Name>mainStream</tt:Name><tt:VideoEncoderConfiguration token="V1"><tt:Name>V1</tt:Name><tt:Encoding>H264</tt:Encoding><tt:Resolution><tt:Width>2560</tt:Width><tt:Height>1440</tt:Height></tt:Resolution></tt:VideoEncoderConfiguration><tt:AudioEncoderConfiguration token="A1"><tt:Encoding>G711</tt:Encoding></tt:AudioEncoderConfiguration></trt:Profiles>' +
            '<trt:Profiles token="Profile_2" fixed="true"><tt:Name>subStream</tt:Name><tt:VideoEncoderConfiguration token="V2"><tt:Name>V2</tt:Name><tt:Encoding>H264</tt:Encoding><tt:Resolution><tt:Width>640</tt:Width><tt:Height>360</tt:Height></tt:Resolution></tt:VideoEncoderConfiguration></trt:Profiles>' +
            '</trt:GetProfilesResponse>',
        );
      case 'GetStreamUri': {
        const token = textOf(doc, 'ProfileToken');
        const ch = token === 'Profile_1' ? '101' : '102';
        return ok(`<trt:GetStreamUriResponse><trt:MediaUri><tt:Uri>rtsp://10.0.0.99:554/Streaming/Channels/${ch}?transportmode=unicast&amp;profile=${token}</tt:Uri></trt:MediaUri></trt:GetStreamUriResponse>`);
      }
      case 'GetSnapshotUri':
        return ok('<trt:GetSnapshotUriResponse><trt:MediaUri><tt:Uri>http://10.0.0.99/snapshot.jpg</tt:Uri></trt:MediaUri></trt:GetSnapshotUriResponse>');
      case 'CreatePullPointSubscription':
        return ok('<tev:CreatePullPointSubscriptionResponse><tev:SubscriptionReference><wsa5:Address>http://10.0.0.99/onvif/Events/PullSubManager_1</wsa5:Address></tev:SubscriptionReference></tev:CreatePullPointSubscriptionResponse>');
      case 'PullMessages': {
        const items = this.pending.splice(0).map(
          (v) =>
            '<wsnt:NotificationMessage><wsnt:Topic Dialect="http://www.onvif.org/ver10/tev/topicExpression/ConcreteSet">tns1:RuleEngine/CellMotionDetector/Motion</wsnt:Topic>' +
            `<wsnt:Message><tt:Message UtcTime="${new Date().toISOString()}" PropertyOperation="Changed"><tt:Source><tt:SimpleItem Name="VideoSourceConfigurationToken" Value="VideoSourceToken"/></tt:Source>` +
            `<tt:Data><tt:SimpleItem Name="IsMotion" Value="${v}"/></tt:Data></tt:Message></wsnt:Message></wsnt:NotificationMessage>`,
        );
        if (!items.length) await new Promise((r) => setTimeout(r, 20));
        return ok(`<tev:PullMessagesResponse><tev:CurrentTime>${new Date().toISOString()}</tev:CurrentTime>${items.join('')}</tev:PullMessagesResponse>`);
      }
      case 'Renew':
        return ok('<wsnt:RenewResponse/>');
      case 'Unsubscribe':
        return ok('<wsnt:UnsubscribeResponse/>');
      default:
        return fault(`Action non prise en charge : ${method}`, 400, 'ter:ActionNotSupported');
    }
  };

  #snapshot(init) {
    const auth = init.headers?.Authorization ?? '';
    if (this.digestSnapshot) {
      if (!auth.startsWith('Digest ') || !auth.includes(`username="${this.username}"`)) {
        return new Response('', { status: 401, headers: { 'www-authenticate': 'Digest realm="IP Camera", qop="auth", nonce="abc123", algorithm=MD5' } });
      }
    }
    return new Response(simulatedFrame(), { headers: { 'content-type': 'image/jpeg' } });
  }
}

/** Sonde RTSP simulée (pas de réseau) : flux H.264 + G.711. */
export const okProbe = async () => ({ ok: true, status: 200, video: { codec: 'H264' }, audio: { codec: 'PCMU' } });
