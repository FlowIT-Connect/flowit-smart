import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Position du téléphone (latitude, longitude).
typedef LatLon = (double, double);

/// Position du téléphone pour l'Absence automatique (optionnelle, à la demande du membre).
///
/// Seule la distance au logement est gardée côté serveur, jamais la position.
abstract class LocationService {
  /// Demande l'autorisation ; false si refusée ou service de localisation coupé.
  Future<bool> requestPermission();

  /// Position actuelle (null si indisponible).
  Future<LatLon?> current();

  /// Positions pendant que l'app tourne, à chaque déplacement d'au moins 150 m.
  Stream<LatLon> watch();
}

/// Pas de localisation : tests, ou plateforme sans GPS.
class NoLocation implements LocationService {
  const NoLocation();
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<LatLon?> current() async => null;
  @override
  Stream<LatLon> watch() => const Stream.empty();
}

/// Localisation du téléphone (précision réduite : à quelques centaines de mètres près, c'est assez).
class DeviceLocation implements LocationService {
  const DeviceLocation();

  static const _settings = LocationSettings(accuracy: LocationAccuracy.low, distanceFilter: 150);

  @override
  Future<bool> requestPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      return p == LocationPermission.always || p == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<LatLon?> current() async {
    try {
      final p = await Geolocator.getCurrentPosition(locationSettings: _settings).timeout(const Duration(seconds: 20));
      return (p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<LatLon> watch() => Geolocator.getPositionStream(locationSettings: _settings).map((p) => (p.latitude, p.longitude)).handleError((_) {});
}
