import '../models/models.dart';
import 'icons.dart';

/// Niveau d'un indicateur du tableau d'accueil.
enum SummaryLevel { none, ok, warning, alert }

/// Tableau récapitulatif de l'accueil, calculé uniquement à partir des appareils
/// réellement connectés : un indicateur sans capteur en ligne reste vide (null),
/// jamais une valeur inventée.
class HomeOverview {
  // Maison connectée
  final int total;
  final int online;
  final int offline;

  // Sécurité
  final int securityDevices;
  final int openings; // portes / fenêtres ouvertes
  final int unlocked; // serrures déverrouillées
  final int motionNow; // détecteurs qui voient un mouvement
  final int hazards; // fumée ou fuite d'eau détectée

  // Climat
  final double? indoorTemperature;
  final double? setpoint;

  /// Modes des appareils de chauffage / climatisation en marche (cool, heat…).
  final Set<String> hvacModes;

  // Humidité
  final double? humidity;

  /// Humidité moyenne par pièce (clé null : appareils sans pièce).
  final Map<String?, double> humidityByRoom;

  const HomeOverview({
    required this.total,
    required this.online,
    required this.offline,
    required this.securityDevices,
    required this.openings,
    required this.unlocked,
    required this.motionNow,
    required this.hazards,
    required this.indoorTemperature,
    required this.setpoint,
    required this.hvacModes,
    required this.humidity,
    required this.humidityByRoom,
  });

  factory HomeOverview.of(Iterable<Device> devices) {
    final list = devices.toList();
    final live = list.where((d) => d.isOnline).toList();

    var security = 0, openings = 0, unlocked = 0, motion = 0, hazards = 0;
    final temps = <double>[];
    final setpoints = <double>[];
    final modes = <String>{};
    final hums = <double>[];
    final humByRoom = <String?, List<double>>{};

    for (final d in list) {
      final kind = deviceKind(d);
      final isSecurity = kind == DeviceKind.lock ||
          kind == DeviceKind.door ||
          kind == DeviceKind.motion ||
          _hazardKeys.any((k) => d.capability(k) != null);
      if (isSecurity) security++;
    }

    for (final d in live) {
      final s = d.state;
      if (s['contact'] == false) openings++;
      if (s['lock'] == false) unlocked++;
      if (s['motion'] == true && deviceKind(d) == DeviceKind.motion) motion++;
      if (_hazardKeys.any((k) => s[k] == true)) hazards++;

      final t = s['current_temperature'] ?? (deviceKind(d) == DeviceKind.sensor || deviceKind(d) == DeviceKind.climate || deviceKind(d) == DeviceKind.airConditioner ? s['temperature'] : null);
      if (t is num) temps.add(t.toDouble());
      final mode = s['hvac_mode'];
      final active = mode is String && mode != 'off';
      final sp = s['target_temperature'];
      if (sp is num && (active || mode == null)) setpoints.add(sp.toDouble());
      if (active) modes.add(mode);

      final h = s['humidity'];
      if (h is num) {
        hums.add(h.toDouble());
        humByRoom.putIfAbsent(d.roomId, () => []).add(h.toDouble());
      }
    }

    double? avg(List<double> v) => v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
    return HomeOverview(
      total: list.length,
      online: live.length,
      offline: list.where((d) => d.availability == Availability.unavailable).length,
      securityDevices: security,
      openings: openings,
      unlocked: unlocked,
      motionNow: motion,
      hazards: hazards,
      indoorTemperature: avg(temps),
      setpoint: avg(setpoints),
      hvacModes: modes,
      humidity: avg(hums),
      humidityByRoom: {for (final e in humByRoom.entries) e.key: avg(e.value)!},
    );
  }

  /// Capacités de détection de danger (fumée, fuite d'eau).
  static const _hazardKeys = ['smoke', 'water_leak', 'leak', 'moisture', 'gas'];

  SummaryLevel get homeLevel => total == 0 ? SummaryLevel.none : (offline > 0 ? SummaryLevel.warning : SummaryLevel.ok);

  SummaryLevel get securityLevel {
    if (hazards > 0) return SummaryLevel.alert;
    if (securityDevices == 0) return SummaryLevel.none;
    if (openings > 0 || unlocked > 0) return SummaryLevel.warning;
    return SummaryLevel.ok;
  }

  /// Chauffage, climatisation ou arrêt, d'après les appareils en marche.
  String get climateState => switch (hvacModes) {
        final m when m.isEmpty => 'off',
        final m when m.length > 1 => 'mixed',
        final m => m.first,
      };
}
