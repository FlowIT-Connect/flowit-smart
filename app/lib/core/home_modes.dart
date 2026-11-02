import 'package:flutter/material.dart';

/// Modes du logement : saison (été / hiver) et vacances. Appliqués par la
/// passerelle (conditions et déclencheurs « mode », simulation de présence).
@immutable
class HomeModes {
  final String season; // none | summer | winter
  final bool vacation;
  final DateTime? vacationFrom;
  final DateTime? vacationTo;
  final bool presenceSimulation;
  final List<String> simulationDevices;

  const HomeModes({
    this.season = 'none',
    this.vacation = false,
    this.vacationFrom,
    this.vacationTo,
    this.presenceSimulation = false,
    this.simulationDevices = const [],
  });

  static const none = HomeModes();

  factory HomeModes.fromJson(Map<String, dynamic> j) => HomeModes(
        season: (j['season'] as String?) ?? 'none',
        vacation: (j['vacation'] as bool?) ?? false,
        vacationFrom: DateTime.tryParse(j['vacation_from'] as String? ?? '')?.toLocal(),
        vacationTo: DateTime.tryParse(j['vacation_to'] as String? ?? '')?.toLocal(),
        presenceSimulation: (j['presence_simulation'] as bool?) ?? false,
        simulationDevices: [for (final d in (j['simulation_devices'] as List?) ?? const []) '$d'],
      );

  Map<String, dynamic> toJson() => {
        'season': season,
        'vacation': vacation,
        'vacation_from': vacationFrom?.toUtc().toIso8601String(),
        'vacation_to': vacationTo?.toUtc().toIso8601String(),
        'presence_simulation': presenceSimulation,
        'simulation_devices': simulationDevices,
      };

  /// Vacances en cours (activées et entre les dates, si elles sont fixées).
  bool vacationActive([DateTime? at]) {
    if (!vacation) return false;
    final t = at ?? DateTime.now();
    return (vacationFrom == null || !t.isBefore(vacationFrom!)) && (vacationTo == null || t.isBefore(vacationTo!));
  }

  /// Vacances programmées mais pas encore commencées.
  bool vacationScheduled([DateTime? at]) => vacation && vacationFrom != null && (at ?? DateTime.now()).isBefore(vacationFrom!);

  HomeModes copyWith({
    String? season,
    bool? vacation,
    DateTime? vacationFrom,
    DateTime? vacationTo,
    bool clearDates = false,
    bool? presenceSimulation,
    List<String>? simulationDevices,
  }) =>
      HomeModes(
        season: season ?? this.season,
        vacation: vacation ?? this.vacation,
        vacationFrom: clearDates ? null : (vacationFrom ?? this.vacationFrom),
        vacationTo: clearDates ? null : (vacationTo ?? this.vacationTo),
        presenceSimulation: presenceSimulation ?? this.presenceSimulation,
        simulationDevices: simulationDevices ?? this.simulationDevices,
      );
}

const modeIcons = {
  'summer': Icons.wb_sunny_rounded,
  'winter': Icons.ac_unit_rounded,
  'vacation': Icons.flight_takeoff_rounded,
};
