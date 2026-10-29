import 'package:flutter/services.dart';

import '../models/models.dart';
import 'icons.dart';

/// Nom de la photo de type d'un appareil (`assets/devices/<clé>.jpg|png|webp`).
String devicePhotoKey(Device d) => switch (deviceKind(d)) {
      DeviceKind.camera => 'camera',
      DeviceKind.airConditioner => 'air_conditioner',
      DeviceKind.climate => 'thermostat',
      DeviceKind.light => 'light',
      DeviceKind.plug => 'plug',
      DeviceKind.cover => 'blinds',
      DeviceKind.lock => 'lock',
      DeviceKind.door => 'door_sensor',
      DeviceKind.motion => 'motion_sensor',
      DeviceKind.sensor => 'sensor',
      DeviceKind.other => 'other',
    };

/// Photos de type livrées avec l'application : il suffit de déposer un fichier dans
/// assets/devices/ pour qu'il soit utilisé (aucune liste à tenir à jour dans le code).
class DevicePhotoCatalog {
  static Map<String, String> _byKey = const {};

  static Future<void> load([AssetBundle? bundle]) async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(bundle ?? rootBundle);
      final found = <String, String>{};
      for (final path in manifest.listAssets()) {
        final m = RegExp(r'^assets/devices/([a-z_]+)\.(jpg|jpeg|png|webp)$').firstMatch(path);
        if (m != null) found[m.group(1)!] = path;
      }
      _byKey = found;
    } catch (_) {
      _byKey = const {};
    }
  }

  /// Utilisé par les tests pour simuler des photos livrées.
  static void debugSet(Map<String, String> byKey) => _byKey = byKey;

  static String? assetFor(Device d) => _byKey[devicePhotoKey(d)];
}
