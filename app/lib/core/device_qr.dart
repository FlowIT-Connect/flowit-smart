/// Lecture du QR code collé sous une caméra.
///
/// Format Dahua (gammes Hero, Imou et caméras IP), relevé sur une vraie étiquette DH-H5A
/// (valeurs remplacées ici) :
///   `{SN:9K00AB1CDEF2345,DT:DH-H5A,SC:ABCD1234,NC:030}`
///   SN = numéro de série, DT = modèle, SC = code de sécurité (mot de passe d'origine),
///   NC = mode de configuration réseau (ignoré).
/// Les variantes sans accolades ou avec « ; » et retours à la ligne sont acceptées.
/// Tout autre QR est refusé : aucune marque n'est annoncée compatible sans vérification.
class DeviceQr {
  const DeviceQr({required this.manufacturer, required this.serial, this.model, this.safetyCode});

  final String manufacturer;
  final String serial;
  final String? model;
  final String? safetyCode;

  /// Pilote du boîtier vidéo correspondant.
  String get driver => 'dahua';

  static final _serial = RegExp(r'^[A-Za-z0-9-]{4,40}$');

  static DeviceQr? parse(String? raw) {
    if (raw == null) return null;
    var text = raw.trim();
    if (text.startsWith('{') && text.endsWith('}')) text = text.substring(1, text.length - 1);
    final fields = <String, String>{};
    for (final part in text.split(RegExp(r'[,;\n\r]+'))) {
      final i = part.indexOf(':');
      if (i <= 0) continue;
      fields[part.substring(0, i).trim().toUpperCase()] = part.substring(i + 1).trim();
    }
    final sn = fields['SN'];
    if (sn == null || !_serial.hasMatch(sn)) return null;
    // Sans DT ni SC, ce n'est pas une étiquette Dahua (un « SN: » isolé est trop vague).
    if (fields['DT'] == null && fields['SC'] == null) return null;
    String? opt(String? v) => (v == null || v.isEmpty) ? null : v;
    return DeviceQr(manufacturer: 'Dahua', serial: sn.toUpperCase(), model: opt(fields['DT']), safetyCode: opt(fields['SC']));
  }
}
