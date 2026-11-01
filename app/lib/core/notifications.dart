import 'package:flutter/material.dart';

/// Catégories du centre de notifications, dans l'ordre des filtres.
const notificationCategories = ['security', 'alarm', 'devices', 'climate', 'automation'];

/// Priorités, de la plus faible à la plus forte.
const notificationPriorities = ['low', 'normal', 'high', 'critical'];

/// Un type de notification : catégorie, priorité et icône (mêmes valeurs que
/// `notification_meta` côté serveur).
class NotificationKind {
  final String type;
  final String category;
  final String priority;
  final IconData icon;

  const NotificationKind(this.type, this.category, this.priority, this.icon);

  String get labelKey => 'notif.type.$type';

  static const all = <NotificationKind>[
    NotificationKind('motion', 'security', 'high', Icons.directions_run_rounded),
    NotificationKind('door_open', 'security', 'high', Icons.door_front_door_rounded),
    NotificationKind('door_closed', 'security', 'low', Icons.door_front_door_outlined),
    NotificationKind('window_open', 'security', 'normal', Icons.window_rounded),
    NotificationKind('water_leak', 'alarm', 'critical', Icons.water_drop_rounded),
    NotificationKind('smoke', 'alarm', 'critical', Icons.local_fire_department_rounded),
    NotificationKind('camera_offline', 'devices', 'high', Icons.videocam_off_rounded),
    NotificationKind('device_offline', 'devices', 'normal', Icons.wifi_off_rounded),
    NotificationKind('temperature_abnormal', 'climate', 'high', Icons.device_thermostat_rounded),
    NotificationKind('automation_run', 'automation', 'low', Icons.auto_awesome_rounded),
    NotificationKind('high_wind', 'climate', 'high', Icons.air_rounded),
    NotificationKind('shutters_auto_closed', 'automation', 'normal', Icons.blinds_closed_rounded),
  ];

  static NotificationKind of(String type) =>
      all.firstWhere((k) => k.type == type, orElse: () => const NotificationKind('other', 'devices', 'normal', Icons.notifications_rounded));
}

IconData categoryIcon(String category) => switch (category) {
      'security' => Icons.shield_rounded,
      'alarm' => Icons.warning_amber_rounded,
      'devices' => Icons.devices_other_rounded,
      'climate' => Icons.thermostat_rounded,
      'automation' => Icons.auto_awesome_rounded,
      _ => Icons.notifications_rounded,
    };

Color priorityColor(String priority) => switch (priority) {
      'critical' => const Color(0xFFEF4444),
      'high' => const Color(0xFFF59E0B),
      'normal' => const Color(0xFF60A5FA),
      _ => const Color(0xFF94A3B8),
    };

/// Notification reçue par l'utilisateur connecté.
class AppNotification {
  final int id;
  final String homeId;
  final String type;
  final String category;
  final String priority;
  final String? deviceId;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime? readAt;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.homeId,
    required this.type,
    required this.category,
    required this.priority,
    this.deviceId,
    required this.title,
    this.body = '',
    this.data = const {},
    this.readAt,
    required this.createdAt,
  });

  bool get isRead => readAt != null;
  NotificationKind get kind => NotificationKind.of(type);
  int get priorityRank => notificationPriorities.indexOf(priority).clamp(0, 3);

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: (j['id'] as num).toInt(),
        homeId: j['home_id'] as String,
        type: j['type'] as String,
        category: j['category'] as String? ?? 'devices',
        priority: j['priority'] as String? ?? 'normal',
        deviceId: j['device_id'] as String?,
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        data: Map<String, dynamic>.from((j['data'] as Map?) ?? const {}),
        readAt: DateTime.tryParse(j['read_at'] as String? ?? '')?.toLocal(),
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal() ?? DateTime.now(),
      );

  AppNotification markedRead([DateTime? at]) => AppNotification(
        id: id,
        homeId: homeId,
        type: type,
        category: category,
        priority: priority,
        deviceId: deviceId,
        title: title,
        body: body,
        data: data,
        readAt: at ?? DateTime.now(),
        createdAt: createdAt,
      );
}

/// Réglages de l'utilisateur (profiles.preferences -> notifications).
@immutable
class NotificationSettings {
  /// Types désactivés.
  final Set<String> off;
  final double tempMax;
  final double tempMin;

  const NotificationSettings({this.off = const {}, this.tempMax = 35, this.tempMin = 5});

  static const defaults = NotificationSettings();

  bool enabled(String type) => !off.contains(type);

  factory NotificationSettings.fromJson(Object? j) {
    if (j is! Map) return defaults;
    final off = j['off'];
    double n(Object? v, double min, double max, double def) => v is num ? v.toDouble().clamp(min, max) : def;
    return NotificationSettings(
      off: off is List ? {for (final t in off) if (t is String && NotificationKind.all.any((k) => k.type == t)) t} : const {},
      tempMax: n(j['temp_max'], 20, 60, 35),
      tempMin: n(j['temp_min'], -20, 18, 5),
    );
  }

  Map<String, dynamic> toJson() => {
        'off': (off.toList()..sort()),
        'temp_max': tempMax.roundToDouble(),
        'temp_min': tempMin.roundToDouble(),
      };

  NotificationSettings toggle(String type, bool on) =>
      NotificationSettings(off: on ? ({...off}..remove(type)) : {...off, type}, tempMax: tempMax, tempMin: tempMin);

  NotificationSettings copyWith({double? tempMax, double? tempMin}) =>
      NotificationSettings(off: off, tempMax: tempMax ?? this.tempMax, tempMin: tempMin ?? this.tempMin);
}
