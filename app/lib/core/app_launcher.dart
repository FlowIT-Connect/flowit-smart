import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ouverture d'une autre application du téléphone (app Android seulement).
class AppLauncher {
  const AppLauncher();

  static const _channel = MethodChannel('solea/apps');

  /// Applications Tuya capables de coupler un appareil, par ordre de préférence.
  static const tuyaApps = ['com.tuya.smartlife', 'com.tuya.smart'];

  bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Ouvre Smart Life (ou Tuya Smart). Renvoie le paquet ouvert, « store » si seule la fiche
  /// Play Store a pu s'ouvrir, ou null.
  Future<String?> openTuyaApp() async {
    if (!available) return null;
    try {
      return await _channel.invokeMethod<String>('open', {'packages': tuyaApps});
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
