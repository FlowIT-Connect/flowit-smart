// Solea Universal Device Integration (UDI) : contrat commun à tous les adaptateurs vidéo,
// interphonie et contrôle d'accès. Chaque fabricant a son propre pilote (« driver ») qui
// implémente ces méthodes ; le concentrateur (hub.js) les fait tourner isolément, de sorte
// qu'une panne chez un fabricant n'arrête jamais les autres.
//
//   connect()       connexion + authentification + identification + capacités
//   identity()      { manufacturer, model, firmware, serial }
//   capabilities()  drapeaux UDI réellement utilisables (voir UDI_CAPABILITIES)
//   streams()       { main: rtspUrl, sub: rtspUrl|null } — sans identifiants
//   snapshot()      { bytes, contentType } image fixe
//   diagnose()      [{ step, ok, detail }] étapes du diagnostic
//   disconnect()    arrête les abonnements
//   onEvent(cb)     cb({ type:'motion', value:boolean }) …
//
// Règle du cahier des charges (§3.4) : un drapeau n'est vrai que si Solea sait réellement s'en
// servir aujourd'hui. Ce que l'appareil annonce sans que Solea le pilote encore va dans
// `detected` du diagnostic, jamais dans les capacités.

export const UDI_CAPABILITIES = Object.freeze([
  'video_stream',
  'snapshot',
  'audio_input',
  'audio_output',
  'sip_call',
  'door_relay',
  'motion_detection',
  'human_detection',
  'ptz_control',
  'rfid_reader',
  'keypad',
  'qr_reader',
  'face_recognition',
]);

export const UDI_DRIVERS = Object.freeze(['onvif', 'rtsp']);
export const UDI_CATEGORIES = Object.freeze(['camera', 'intercom', 'access', 'monitor', 'sensor']);

/** Tous les drapeaux à false sauf ceux donnés (les clés inconnues sont ignorées). */
export function capabilityFlags(partial = {}) {
  const out = {};
  for (const k of UDI_CAPABILITIES) out[k] = partial[k] === true;
  return out;
}

/** Codecs audio que WebRTC sait lire directement (l'AAC, fréquent sur les caméras, ne passe pas). */
export function webrtcAudio(codec) {
  return ['PCMU', 'PCMA', 'OPUS', 'G722'].includes(String(codec ?? '').toUpperCase());
}

/** Erreur d'un pilote, avec un type compréhensible pour le diagnostic. */
export class UdiError extends Error {
  /** @param {string} message @param {'auth'|'unreachable'|'protocol'|'unsupported'} kind */
  constructor(message, kind = 'protocol') {
    super(message);
    this.kind = kind;
  }
}
