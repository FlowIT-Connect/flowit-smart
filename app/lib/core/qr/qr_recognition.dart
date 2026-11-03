import 'dart:convert';

import '../device_qr.dart';
import 'brand_catalog.dart';

/// Reconnaissance des QR codes collés sur les appareils.
///
/// Aucun format n'est supposé universel : chaque [QrParser] reconnaît un format précis
/// (standard, propriétaire ou simple numéro de série) et le premier qui répond l'emporte.
/// Reconnaître un QR code ne veut pas dire que l'appareil est compatible : la compatibilité
/// est décidée ensuite par la bibliothèque des marques ([BrandCatalog]).
///
/// Les secrets (mot de passe Wi-Fi, code d'appairage Matter / HomeKit, code de sécurité
/// Dahua, code d'installation Zigbee) sont gardés à part dans [QrRecognition.secrets] et
/// toujours masqués dans [QrRecognition.redactedPayload], seul texte enregistré ou journalisé.

/// Famille du QR code.
enum QrCodeType {
  /// Format ouvert et documenté (Matter, HomeKit, Wi-Fi, Zigbee).
  standard,

  /// Format propre à un fabricant (étiquette Dahua, lien Tuya…).
  proprietary,

  /// Simple lien web sans format connu.
  url,

  /// Numéro de série seul.
  serial,

  /// Texte illisible pour Solea.
  unknown,
}

class QrRecognition {
  const QrRecognition({
    required this.raw,
    required this.redactedPayload,
    required this.type,
    required this.parser,
    this.brand,
    this.manufacturerName,
    this.model,
    this.productId,
    this.serial,
    this.deviceType,
    this.protocol,
    this.secrets = const {},
    this.details = const {},
  });

  /// Texte lu tel quel (jamais enregistré ni journalisé : voir [redactedPayload]).
  final String raw;

  /// Texte lu, secrets masqués par des étoiles.
  final String redactedPayload;
  final QrCodeType type;

  /// Parseur qui a reconnu le code (matter, homekit, wifi, zigbee, dahua, tuya, url, json,
  /// fields, serial, unknown).
  final String parser;

  /// Marque reconnue dans la bibliothèque (null : inconnue).
  final Brand? brand;

  /// Nom du fabricant quand il est connu sans être dans la bibliothèque (ex. vendeur Matter).
  final String? manufacturerName;
  final String? model;
  final String? productId;
  final String? serial;

  /// Type d'équipement (clé de traduction `qr.type.<deviceType>`).
  final String? deviceType;

  /// Protocole : matter, homekit, wifi, zigbee, ble, onvif…
  final String? protocol;

  /// Informations de connexion présentes dans le code (gardées en mémoire, jamais affichées).
  final Map<String, String> secrets;

  /// Autres informations techniques lisibles (version, discriminateur…).
  final Map<String, String> details;

  bool get recognized => type != QrCodeType.unknown;
  bool get hasCredentials => secrets.isNotEmpty;

  /// Fabricant affiché.
  String? get manufacturer => brand?.name ?? manufacturerName;

  /// Statut enregistré dans device_qr_scans.
  String get recognitionStatus {
    if (!recognized) return 'unknown';
    return (brand?.support ?? BrandSupport.unsupported) == BrandSupport.unsupported ? 'unsupported' : 'recognized';
  }

  /// Valeur courte du code Dahua attendue par le boîtier vidéo.
  DeviceQr? get dahua => parser == 'dahua' ? DeviceQr.parse(raw) : null;
}

/// Un format de QR code.
abstract class QrParser {
  const QrParser();

  String get id;

  /// null si le texte n'est pas dans ce format.
  QrRecognition? parse(String raw);
}

/// Registre des parseurs, du plus précis au plus vague. Ajouter un fabricant = ajouter un
/// parseur ici (ou un nom d'hôte / préfixe dans [BrandCatalog]).
class QrRecognizer {
  const QrRecognizer([this.parsers = defaultParsers]);

  final List<QrParser> parsers;

  static const defaultParsers = <QrParser>[
    MatterQrParser(),
    HomeKitQrParser(),
    WifiQrParser(),
    ZigbeeQrParser(),
    DahuaQrParser(),
    TuyaQrParser(),
    UrlQrParser(),
    JsonQrParser(),
    FieldsQrParser(),
    SerialQrParser(),
  ];

  QrRecognition recognize(String? input) {
    final raw = (input ?? '').trim();
    if (raw.isNotEmpty && raw.length <= 4096) {
      for (final p in parsers) {
        final r = p.parse(raw);
        if (r != null) return r;
      }
    }
    return QrRecognition(raw: raw, redactedPayload: redactSecrets(raw), type: QrCodeType.unknown, parser: 'unknown');
  }
}

/// Masque tout ce qui ressemble à un secret dans un texte libre (P:, SC:, password=…).
String redactSecrets(String text) {
  var out = text.replaceAllMapped(
    RegExp(r'(^|[;,{&?\s])(p|sc|pwd|pass|password|passwd|key|secret|token|code)(\s*[:=]\s*)([^;,}&\s]+)', caseSensitive: false),
    (m) => '${m[1]}${m[2]}${m[3]}****',
  );
  if (out.length > 2000) out = out.substring(0, 2000);
  return out;
}

String? _clean(String? v, {int max = 80}) {
  final t = v?.trim();
  if (t == null || t.isEmpty) return null;
  return t.length > max ? t.substring(0, max) : t;
}

// ---------------------------------------------------------------------------- Matter
/// Matter : `MT:` suivi d'un code en base 38 (spécification Matter, § 5.1.3).
/// Contient le fabricant (vendor ID), le produit, le discriminateur et le code d'appairage.
class MatterQrParser extends QrParser {
  const MatterQrParser();

  @override
  String get id => 'matter';

  static const _alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-.';

  /// Base 38 → octets (blocs de 5 caractères = 3 octets, 4 = 2, 2 = 1).
  static List<int>? decodeBase38(String s) {
    final bytes = <int>[];
    var i = 0;
    while (i < s.length) {
      final left = s.length - i;
      final size = left >= 5 ? 5 : left;
      final nBytes = switch (size) { 5 => 3, 4 => 2, 2 => 1, _ => -1 };
      if (nBytes < 0) return null;
      var value = 0;
      for (var k = size - 1; k >= 0; k--) {
        final c = _alphabet.indexOf(s[i + k]);
        if (c < 0) return null;
        value = value * 38 + c;
      }
      for (var b = 0; b < nBytes; b++) {
        bytes.add(value & 0xff);
        value >>= 8;
      }
      if (value != 0) return null;
      i += size;
    }
    return bytes;
  }

  @override
  QrRecognition? parse(String raw) {
    if (!raw.toUpperCase().startsWith('MT:')) return null;
    final body = raw.substring(3).trim();
    // Plusieurs appareils dans un même code : séparés par « * » ; on lit le premier.
    final first = body.split('*').first;
    final bytes = decodeBase38(first);
    if (bytes == null || bytes.length < 11) return null;
    var bit = 0;
    int read(int n) {
      var v = 0;
      for (var k = 0; k < n; k++) {
        final b = (bytes[(bit + k) >> 3] >> ((bit + k) & 7)) & 1;
        v |= b << k;
      }
      bit += n;
      return v;
    }

    final version = read(3);
    final vendorId = read(16);
    final productId = read(16);
    final flow = read(2);
    final rendezvous = read(8);
    final discriminator = read(12);
    final passcode = read(27);
    if (version != 0 || passcode == 0) return null;
    final brand = BrandCatalog.byMatterVendor(vendorId);
    final hex = vendorId.toRadixString(16).toUpperCase().padLeft(4, '0');
    return QrRecognition(
      raw: raw,
      redactedPayload: 'MT:****',
      type: QrCodeType.standard,
      parser: id,
      brand: brand,
      manufacturerName: brand == null ? (vendorId >= 0xFFF1 && vendorId <= 0xFFF4 ? 'Matter (test)' : 'Matter 0x$hex') : null,
      productId: '0x${productId.toRadixString(16).toUpperCase().padLeft(4, '0')}',
      protocol: 'matter',
      secrets: {'passcode': passcode.toString().padLeft(8, '0')},
      details: {
        'vendor_id': '0x$hex',
        'discriminator': '$discriminator',
        'transport': [if (rendezvous & 1 != 0) 'SoftAP', if (rendezvous & 2 != 0) 'BLE', if (rendezvous & 4 != 0) 'IP'].join(' + '),
        'flow': '$flow',
      },
    );
  }
}

// ---------------------------------------------------------------------------- HomeKit
/// HomeKit : `X-HM://` + 9 caractères en base 36 (catégorie, drapeaux, code) + identifiant.
class HomeKitQrParser extends QrParser {
  const HomeKitQrParser();

  @override
  String get id => 'homekit';

  static const _categories = {
    2: 'bridge', 3: 'fan', 5: 'light', 6: 'lock', 7: 'plug', 8: 'switch', 9: 'thermostat',
    10: 'sensor', 11: 'alarm', 12: 'door', 14: 'cover', 17: 'camera', 18: 'doorbell',
    19: 'air_purifier', 21: 'ac', 22: 'humidifier', 28: 'sprinkler', 32: 'tv',
  };

  @override
  QrRecognition? parse(String raw) {
    final m = RegExp(r'^X-HM://([0-9A-Z]{9})([0-9A-Z]{4})?$', caseSensitive: false).firstMatch(raw);
    if (m == null) return null;
    final value = int.tryParse(m[1]!.toUpperCase(), radix: 36);
    if (value == null) return null;
    final code = value & 0x7FFFFFF;
    final category = (value >> 31) & 0xFF;
    final flags = (value >> 27) & 0xF;
    return QrRecognition(
      raw: raw,
      redactedPayload: 'X-HM://****',
      type: QrCodeType.standard,
      parser: id,
      manufacturerName: 'Apple HomeKit',
      deviceType: _categories[category],
      protocol: (flags & 4) != 0 ? 'ble' : 'homekit',
      secrets: {'setup_code': code.toString().padLeft(8, '0')},
      details: {if (m[2] != null) 'setup_id': m[2]!.toUpperCase(), 'category': '$category'},
    );
  }
}

// ---------------------------------------------------------------------------- Wi-Fi
/// Point d'accès Wi-Fi d'un appareil : `WIFI:T:WPA;S:<nom>;P:<mot de passe>;;`.
/// Le nom du réseau trahit souvent la marque (shellyplus1-…, SmartLife-…, ITEAD-…).
class WifiQrParser extends QrParser {
  const WifiQrParser();

  @override
  String get id => 'wifi';

  @override
  QrRecognition? parse(String raw) {
    if (!raw.toUpperCase().startsWith('WIFI:')) return null;
    final fields = <String, String>{};
    for (final m in RegExp(r'([A-Z]):((?:\\.|[^;])*);', caseSensitive: false).allMatches(raw.substring(5))) {
      fields[m[1]!.toUpperCase()] = m[2]!.replaceAllMapped(RegExp(r'\\(.)'), (x) => x[1]!);
    }
    final ssid = fields['S'];
    if (ssid == null || ssid.isEmpty) return null;
    final brand = BrandCatalog.bySsid(ssid);
    final mac = RegExp(r'([0-9A-Fa-f]{6,12})$').firstMatch(ssid)?[1];
    return QrRecognition(
      raw: raw,
      redactedPayload: redactSecrets(raw),
      type: QrCodeType.standard,
      parser: id,
      brand: brand,
      serial: brand == null ? null : _clean(mac),
      protocol: 'wifi',
      secrets: {if ((fields['P'] ?? '').isNotEmpty) 'wifi_password': fields['P']!},
      details: {'ssid': ssid, if (fields['T'] != null) 'security': fields['T']!},
    );
  }
}

// ---------------------------------------------------------------------------- Zigbee
/// Code d'installation Zigbee 3.0 : `Z:<adresse IEEE 16 hex>$I:<code>` (+ champs optionnels).
class ZigbeeQrParser extends QrParser {
  const ZigbeeQrParser();

  @override
  String get id => 'zigbee';

  @override
  QrRecognition? parse(String raw) {
    final m = RegExp(r'^Z:([0-9A-Fa-f]{16})(\$.*)?$').firstMatch(raw);
    if (m == null) return null;
    final rest = m[2] ?? '';
    final install = RegExp(r'\$I:([0-9A-Fa-f]+)').firstMatch(rest)?[1];
    final model = RegExp(r'\$M:([^$]+)').firstMatch(rest)?[1];
    return QrRecognition(
      raw: raw,
      redactedPayload: 'Z:${m[1]!.toUpperCase()}${install != null ? r'$I:****' : ''}',
      type: QrCodeType.standard,
      parser: id,
      serial: m[1]!.toUpperCase(),
      model: _clean(model),
      protocol: 'zigbee',
      secrets: {'install_code': ?install},
    );
  }
}

// ---------------------------------------------------------------------------- Dahua
/// Étiquette Dahua / Imou : `{SN:…,DT:…,SC:…}` (lecture partagée avec le boîtier vidéo).
class DahuaQrParser extends QrParser {
  const DahuaQrParser();

  @override
  String get id => 'dahua';

  @override
  QrRecognition? parse(String raw) {
    final qr = DeviceQr.parse(raw);
    if (qr == null) return null;
    return QrRecognition(
      raw: raw,
      redactedPayload: redactSecrets(raw),
      type: QrCodeType.proprietary,
      parser: id,
      brand: BrandCatalog.byId('dahua'),
      model: qr.model,
      serial: qr.serial,
      deviceType: 'camera',
      protocol: 'onvif',
      secrets: {'safety_code': ?qr.safetyCode},
    );
  }
}

// ---------------------------------------------------------------------------- Tuya
/// Lien Tuya / Smart Life : `https://…tuya…/…?p=<produit>&uuid=<appareil>` ou `tuyasmart://`.
class TuyaQrParser extends QrParser {
  const TuyaQrParser();

  @override
  String get id => 'tuya';

  @override
  QrRecognition? parse(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme) return null;
    final host = uri.host.toLowerCase();
    final isTuya = uri.scheme.startsWith('tuya') || uri.scheme.startsWith('smartlife') ||
        host.contains('tuya') || host.contains('smartlife') || host.contains('smart-life');
    if (!isTuya) return null;
    final q = {for (final e in uri.queryParameters.entries) e.key.toLowerCase(): e.value};
    return QrRecognition(
      raw: raw,
      redactedPayload: redactSecrets(raw),
      type: QrCodeType.proprietary,
      parser: id,
      brand: BrandCatalog.byId('tuya'),
      productId: _clean(q['p'] ?? q['pid'] ?? q['productid']),
      serial: _clean(q['uuid'] ?? q['devid'] ?? q['deviceid'] ?? q['sn']),
      protocol: 'wifi',
      details: {if (q['v'] != null) 'version': q['v']!},
    );
  }
}

// ---------------------------------------------------------------------------- Lien web
/// Lien d'un fabricant connu (nom d'hôte) avec, si présents, numéro de série / produit.
class UrlQrParser extends QrParser {
  const UrlQrParser();

  @override
  String get id => 'url';

  @override
  QrRecognition? parse(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) return null;
    final q = {for (final e in uri.queryParameters.entries) e.key.toLowerCase(): e.value};
    final brand = BrandCatalog.byHost(uri.host);
    return QrRecognition(
      raw: raw,
      redactedPayload: redactSecrets(raw),
      type: brand == null ? QrCodeType.url : QrCodeType.proprietary,
      parser: id,
      brand: brand,
      model: _clean(q['model'] ?? q['m']),
      productId: _clean(q['pid'] ?? q['productid'] ?? q['product']),
      serial: _clean(q['sn'] ?? q['serial'] ?? q['deviceid'] ?? q['did'] ?? q['mac'] ?? q['uuid'] ?? q['id']),
      details: {'host': uri.host},
    );
  }
}

// ---------------------------------------------------------------------------- JSON
/// Étiquette au format JSON : {"brand":…, "model":…, "sn":…}.
class JsonQrParser extends QrParser {
  const JsonQrParser();

  @override
  String get id => 'json';

  @override
  QrRecognition? parse(String raw) {
    if (!raw.startsWith('{')) return null;
    Object? data;
    try {
      data = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (data is! Map) return null;
    final f = {for (final e in data.entries) e.key.toString().toLowerCase(): e.value?.toString()};
    final maker = f['brand'] ?? f['manufacturer'] ?? f['vendor'] ?? f['mfr'];
    final serial = f['sn'] ?? f['serial'] ?? f['serialnumber'] ?? f['mac'] ?? f['deviceid'] ?? f['did'];
    final model = f['model'] ?? f['dt'] ?? f['type'];
    if (maker == null && serial == null && model == null) return null;
    return _fields(raw, id, maker: maker, model: model, serial: serial, productId: f['pid'] ?? f['productid'],
        secretKeys: f.keys.where(_isSecretKey).toList(), values: f);
  }
}

// ---------------------------------------------------------------------------- Champs
/// Étiquette « clé:valeur » (SN:…, MAC:…, PID:…, Model:…) sans format propriétaire connu.
class FieldsQrParser extends QrParser {
  const FieldsQrParser();

  @override
  String get id => 'fields';

  @override
  QrRecognition? parse(String raw) {
    var text = raw;
    if (text.startsWith('{') && text.endsWith('}')) text = text.substring(1, text.length - 1);
    final f = <String, String>{};
    for (final part in text.split(RegExp(r'[,;\n\r|]+'))) {
      final i = part.indexOf(RegExp(r'[:=]'));
      if (i <= 0) continue;
      f[part.substring(0, i).trim().toLowerCase()] = part.substring(i + 1).trim();
    }
    final serial = f['sn'] ?? f['s/n'] ?? f['serial'] ?? f['mac'] ?? f['id'] ?? f['did'];
    final model = f['model'] ?? f['m'] ?? f['pn'];
    final maker = f['brand'] ?? f['manufacturer'] ?? f['vendor'];
    if (serial == null && model == null) return null;
    return _fields(raw, id, maker: maker, model: model, serial: serial, productId: f['pid'],
        secretKeys: f.keys.where(_isSecretKey).toList(), values: f);
  }
}

bool _isSecretKey(String k) => const {'p', 'sc', 'pwd', 'pass', 'password', 'passwd', 'key', 'secret', 'token', 'code'}.contains(k);

QrRecognition _fields(String raw, String parser,
    {String? maker, String? model, String? serial, String? productId, required List<String> secretKeys, required Map<String, String?> values}) {
  final brand = maker == null ? BrandCatalog.byText(model ?? '') : BrandCatalog.byText(maker);
  return QrRecognition(
    raw: raw,
    redactedPayload: redactSecrets(raw),
    type: brand == null && maker == null ? QrCodeType.serial : QrCodeType.proprietary,
    parser: parser,
    brand: brand,
    manufacturerName: brand == null ? _clean(maker) : null,
    model: _clean(model),
    productId: _clean(productId),
    serial: _clean(serial),
    secrets: {for (final k in secretKeys) if ((values[k] ?? '').isNotEmpty) k: values[k]!},
  );
}

// ---------------------------------------------------------------------------- Numéro seul
/// Numéro de série seul : lettres et chiffres, au moins un chiffre.
class SerialQrParser extends QrParser {
  const SerialQrParser();

  @override
  String get id => 'serial';

  @override
  QrRecognition? parse(String raw) {
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9\-_.:]{4,39}$').hasMatch(raw) || !RegExp(r'\d').hasMatch(raw)) return null;
    return QrRecognition(
      raw: raw,
      redactedPayload: raw,
      type: QrCodeType.serial,
      parser: id,
      brand: BrandCatalog.bySerialPrefix(raw),
      serial: raw.toUpperCase(),
    );
  }
}
