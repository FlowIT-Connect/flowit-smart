import 'package:flutter/material.dart';

/// Chauffage et climatisation par pièce : ambiances, programme de la semaine, dérogations.
/// La passerelle applique ; l'app règle et affiche (même logique que bridge/src/climate.js).

const climatePresets = ['comfort', 'eco', 'sleep', 'away', 'frost'];

/// Ambiances proposées en boutons (Hors-gel reste dans les réglages et le programme).
const climateQuickPresets = ['comfort', 'eco', 'sleep', 'away'];

IconData presetIcon(String preset) => switch (preset) {
      'comfort' => Icons.weekend_rounded,
      'eco' => Icons.eco_rounded,
      'sleep' => Icons.bedtime_rounded,
      'away' => Icons.flight_takeoff_rounded,
      'frost' => Icons.severe_cold_rounded,
      _ => Icons.schedule_rounded,
    };

/// Températures d'une ambiance : chauffage et climatisation (null = pas de clim).
@immutable
class PresetTemps {
  final double? heat;
  final double? cool;
  const PresetTemps(this.heat, this.cool);

  factory PresetTemps.fromJson(Object? j) {
    final m = j is Map ? j : const {};
    double? n(Object? v) => v is num ? v.toDouble() : null;
    return PresetTemps(n(m['heat']), n(m['cool']));
  }

  Map<String, dynamic> toJson() => {'heat': heat, 'cool': cool};

  PresetTemps copyWith({double? heat, double? cool}) => PresetTemps(heat ?? this.heat, cool ?? this.cool);

  @override
  bool operator ==(Object other) => other is PresetTemps && other.heat == heat && other.cool == cool;
  @override
  int get hashCode => Object.hash(heat, cool);
}

const defaultPresetTemps = {
  'comfort': PresetTemps(21, 24),
  'eco': PresetTemps(19, 27),
  'sleep': PresetTemps(18, 26),
  'away': PresetTemps(16, 29),
  'frost': PresetTemps(7, null),
};

@immutable
class ClimateSettings {
  final bool enabled;
  final Map<String, PresetTemps> presets;
  final String? homePreset;
  final DateTime? homePresetUntil;

  const ClimateSettings({this.enabled = true, this.presets = defaultPresetTemps, this.homePreset, this.homePresetUntil});

  static const initial = ClimateSettings();

  factory ClimateSettings.fromJson(Map<String, dynamic> j) {
    final raw = j['presets'] is Map ? j['presets'] as Map : const {};
    return ClimateSettings(
      enabled: (j['enabled'] as bool?) ?? true,
      presets: {for (final p in climatePresets) p: raw.containsKey(p) ? PresetTemps.fromJson(raw[p]) : defaultPresetTemps[p]!},
      homePreset: j['home_preset'] as String?,
      homePresetUntil: DateTime.tryParse(j['home_preset_until'] as String? ?? '')?.toLocal(),
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'presets': {for (final e in presets.entries) e.key: e.value.toJson()},
      };

  PresetTemps temps(String preset) => presets[preset] ?? defaultPresetTemps[preset]!;

  /// Ambiance imposée à toute la maison, si elle est toujours valable.
  String? activeHomePreset([DateTime? at]) =>
      homePreset != null && (homePresetUntil == null || homePresetUntil!.isAfter(at ?? DateTime.now())) ? homePreset : null;

  ClimateSettings copyWith({bool? enabled, Map<String, PresetTemps>? presets}) =>
      ClimateSettings(enabled: enabled ?? this.enabled, presets: presets ?? this.presets, homePreset: homePreset, homePresetUntil: homePresetUntil);
}

/// Plage du programme : à partir de [at] les jours [days] (1 = lundi), ambiance [preset].
@immutable
class ScheduleEntry {
  final List<int> days;
  final String at; // HH:MM
  final String preset;
  const ScheduleEntry(this.days, this.at, this.preset);

  factory ScheduleEntry.fromJson(Object? j) {
    final m = j is Map ? j : const {};
    return ScheduleEntry([for (final d in (m['days'] as List?) ?? const []) if (d is num) d.toInt()], '${m['at'] ?? '00:00'}', '${m['preset'] ?? 'comfort'}');
  }

  Map<String, dynamic> toJson() => {'days': days, 'at': at, 'preset': preset};

  int get minutes => int.parse(at.substring(0, 2)) * 60 + int.parse(at.substring(3, 5));

  ScheduleEntry copyWith({List<int>? days, String? at, String? preset}) => ScheduleEntry(days ?? this.days, at ?? this.at, preset ?? this.preset);
}

/// Programme proposé par défaut : semaine (lever, journée, retour, nuit) et week-end.
const defaultSchedule = [
  ScheduleEntry([1, 2, 3, 4, 5], '06:30', 'comfort'),
  ScheduleEntry([1, 2, 3, 4, 5], '08:30', 'eco'),
  ScheduleEntry([1, 2, 3, 4, 5], '17:30', 'comfort'),
  ScheduleEntry([6, 7], '08:00', 'comfort'),
  ScheduleEntry([1, 2, 3, 4, 5, 6, 7], '22:30', 'sleep'),
];

@immutable
class ClimateZone {
  final String? id;
  final String roomId;
  final bool enabled;
  final List<String> devices;
  final List<ScheduleEntry> schedule;
  final String? override;
  final DateTime? overrideUntil;
  final String? activePreset;
  final double? activeTarget;
  final String? activeSource;

  const ClimateZone({
    this.id,
    required this.roomId,
    this.enabled = true,
    this.devices = const [],
    this.schedule = defaultSchedule,
    this.override,
    this.overrideUntil,
    this.activePreset,
    this.activeTarget,
    this.activeSource,
  });

  factory ClimateZone.fromJson(Map<String, dynamic> j) => ClimateZone(
        id: j['id'] as String?,
        roomId: j['room_id'] as String,
        enabled: (j['enabled'] as bool?) ?? true,
        devices: [for (final d in (j['devices'] as List?) ?? const []) '$d'],
        schedule: [for (final e in (j['schedule'] as List?) ?? const []) ScheduleEntry.fromJson(e)],
        override: j['preset_override'] as String?,
        overrideUntil: DateTime.tryParse(j['override_until'] as String? ?? '')?.toLocal(),
        activePreset: j['active_preset'] as String?,
        activeTarget: (j['active_target'] as num?)?.toDouble(),
        activeSource: j['active_source'] as String?,
      );

  /// Champs réglés depuis l'app (l'état actif est écrit par la passerelle).
  Map<String, dynamic> toJson() => {
        'room_id': roomId,
        'enabled': enabled,
        'devices': devices,
        'schedule': [for (final e in schedule) e.toJson()],
      };

  String? activeOverride([DateTime? at]) => override != null && (overrideUntil == null || overrideUntil!.isAfter(at ?? DateTime.now())) ? override : null;

  ClimateZone copyWith({bool? enabled, List<String>? devices, List<ScheduleEntry>? schedule}) => ClimateZone(
        id: id,
        roomId: roomId,
        enabled: enabled ?? this.enabled,
        devices: devices ?? this.devices,
        schedule: schedule ?? this.schedule,
        override: override,
        overrideUntil: overrideUntil,
        activePreset: activePreset,
        activeTarget: activeTarget,
        activeSource: activeSource,
      );
}

@immutable
class ClimateData {
  final ClimateSettings settings;
  final List<ClimateZone> zones;
  const ClimateData(this.settings, this.zones);
  static const empty = ClimateData(ClimateSettings.initial, []);

  ClimateZone? zoneFor(String roomId) => zones.where((z) => z.roomId == roomId).firstOrNull;
}

/// Ambiance du programme à [at] : dernière plage commencée, en remontant jusqu'à 7 jours.
String? scheduledPreset(List<ScheduleEntry> schedule, DateTime at) {
  final entries = schedule.where((e) => climatePresets.contains(e.preset)).toList();
  if (entries.isEmpty) return null;
  final now = at.hour * 60 + at.minute;
  for (var back = 0; back < 8; back++) {
    final day = (at.weekday - 1 - back + 70) % 7 + 1;
    final limit = back == 0 ? now : 24 * 60;
    final today = entries.where((e) => e.days.contains(day) && e.minutes <= limit).toList()..sort((a, b) => a.minutes.compareTo(b.minutes));
    if (today.isNotEmpty) return today.last.preset;
  }
  return null;
}

/// Ambiance d'une pièce et sa raison : room, home, vacation, schedule, default.
(String, String) effectivePreset(ClimateZone zone, ClimateSettings settings, {required bool vacation, DateTime? at}) {
  final t = at ?? DateTime.now();
  final room = zone.activeOverride(t);
  if (room != null) return (room, 'room');
  final home = settings.activeHomePreset(t);
  if (home != null) return (home, 'home');
  if (vacation) return ('away', 'vacation');
  final s = scheduledPreset(zone.schedule, t);
  if (s != null) return (s, 'schedule');
  return ('comfort', 'default');
}
