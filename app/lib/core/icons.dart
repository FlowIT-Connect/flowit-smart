import 'package:flutter/material.dart';

import '../models/models.dart';
import 'theme.dart';

/// Icônes de pièces proposées (clé stockée dans rooms.icon).
const roomIcons = <String, IconData>{
  'sofa': Icons.weekend_rounded,
  'bed': Icons.bed_rounded,
  'kitchen': Icons.kitchen_rounded,
  'dining': Icons.dining_rounded,
  'bath': Icons.bathtub_rounded,
  'office': Icons.desk_rounded,
  'child': Icons.child_care_rounded,
  'door': Icons.door_front_door_rounded,
  'garage': Icons.garage_rounded,
  'garden': Icons.yard_rounded,
  'stairs': Icons.stairs_rounded,
  'other': Icons.meeting_room_rounded,
};

IconData roomIcon(String? key) => roomIcons[key] ?? Icons.meeting_room_rounded;

/// Icônes de scènes (clé stockée dans scenes.icon).
const sceneIcons = <String, IconData>{
  'movie': Icons.movie_rounded,
  'night': Icons.bedtime_rounded,
  'sun': Icons.wb_sunny_rounded,
  'logout': Icons.logout_rounded,
  'home': Icons.home_rounded,
  'party': Icons.celebration_rounded,
  'meal': Icons.restaurant_rounded,
  'auto': Icons.auto_awesome_rounded,
};

IconData sceneIcon(String? key) => sceneIcons[key] ?? Icons.auto_awesome_rounded;

/// Dégradé d'une scène, choisi d'après son icône pour rester stable.
List<Color> sceneGradient(BuildContext context, String? key) {
  final f = context.flow;
  // Tons chauds et terreux, en accord avec l'identité Solea.
  return switch (key) {
    'movie' => [const Color(0xFF2B211B), const Color(0xFF6A4630)],
    'night' => [const Color(0xFF1E2232), const Color(0xFF46507A)],
    'sun' => [const Color(0xFFFFB53D), const Color(0xFFF07B1F)],
    'logout' => [const Color(0xFF3A332C), const Color(0xFF7A6B5A)],
    'home' => [const Color(0xFFC9772F), const Color(0xFFE9A35A)],
    'party' => [const Color(0xFFC94A6E), const Color(0xFFF08A5D)],
    'meal' => [const Color(0xFFD9652B), const Color(0xFFF2AE5E)],
    _ => [f.brandDeep, f.brand],
  };
}

enum DeviceKind { camera, light, plug, cover, airConditioner, climate, lock, door, motion, sensor, other }

/// Modes propres à un climatiseur (un thermostat de chauffage ne les a pas).
const _acModes = {'cool', 'dry', 'fan_only'};

DeviceKind deviceKind(Device d) {
  bool has(String k) => d.capability(k) != null;
  if (d.isCamera) return DeviceKind.camera;
  if (d.isSensitive || has('lock')) return DeviceKind.lock;
  if (has('cover_position') || has('cover_control')) return DeviceKind.cover;
  if (has('target_temperature')) {
    final modes = d.capability('hvac_mode')?.options ?? const [];
    return modes.any(_acModes.contains) ? DeviceKind.airConditioner : DeviceKind.climate;
  }
  if (has('color') || has('brightness') || has('color_temp')) return DeviceKind.light;
  if (has('switch')) return DeviceKind.plug;
  if (has('contact')) return DeviceKind.door;
  if (has('motion')) return DeviceKind.motion;
  if (has('temperature') || has('humidity')) return DeviceKind.sensor;
  return DeviceKind.other;
}

IconData deviceIcon(Device d) => switch (deviceKind(d)) {
      DeviceKind.camera => Icons.videocam_rounded,
      DeviceKind.airConditioner => Icons.ac_unit_rounded,
      DeviceKind.lock => Icons.lock_rounded,
      DeviceKind.cover => Icons.blinds_rounded,
      DeviceKind.climate => Icons.thermostat_rounded,
      DeviceKind.light => Icons.lightbulb_rounded,
      DeviceKind.plug => Icons.power_rounded,
      DeviceKind.door => Icons.sensor_door_rounded,
      DeviceKind.motion => Icons.directions_walk_rounded,
      DeviceKind.sensor => Icons.device_thermostat_rounded,
      DeviceKind.other => Icons.devices_other_rounded,
    };

/// Couleur d'accent d'un appareil : la couleur réelle d'une lampe colorée si elle
/// est connue, sinon la couleur de sa famille.
Color deviceAccent(BuildContext context, Device d) {
  final f = context.flow;
  final kind = deviceKind(d);
  if (kind == DeviceKind.light) {
    final c = d.state['color'];
    if (c is String && RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(c)) {
      final color = Color(int.parse(c.replaceFirst('#', ''), radix: 16) | 0xFF000000);
      // Une lampe blanche reste ambrée pour garder une icône lisible.
      if (color.computeLuminance() < .85) return color;
    }
    return f.amber;
  }
  return switch (kind) {
    DeviceKind.plug => f.brand,
    DeviceKind.cover => f.blue,
    DeviceKind.climate => f.orange,
    DeviceKind.airConditioner => f.blue,
    DeviceKind.camera => f.violet,
    DeviceKind.lock => f.violet,
    DeviceKind.door => f.cyan,
    DeviceKind.motion => f.pink,
    DeviceKind.sensor => f.cyan,
    _ => f.brand,
  };
}

IconData capabilityIcon(String key) => switch (key) {
      'switch' => Icons.power_settings_new_rounded,
      'brightness' => Icons.brightness_6_rounded,
      'color_temp' => Icons.wb_incandescent_rounded,
      'color' => Icons.palette_rounded,
      'cover_position' || 'cover_control' => Icons.blinds_rounded,
      'target_temperature' => Icons.thermostat_rounded,
      'hvac_mode' => Icons.mode_fan_off_rounded,
      'lock' => Icons.lock_rounded,
      'temperature' || 'current_temperature' => Icons.device_thermostat_rounded,
      'humidity' => Icons.water_drop_rounded,
      'battery' => Icons.battery_std_rounded,
      'power' => Icons.bolt_rounded,
      'energy' => Icons.electric_meter_rounded,
      'contact' => Icons.sensor_door_rounded,
      'motion' => Icons.directions_walk_rounded,
      'illuminance' => Icons.light_mode_rounded,
      _ => Icons.tune_rounded,
    };

IconData protocolIcon(String protocol) => switch (protocol) {
      'zigbee' => Icons.hub_rounded,
      'ble' => Icons.bluetooth_rounded,
      'wifi' => Icons.wifi_rounded,
      'tuya' => Icons.cloud_rounded,
      'mqtt' => Icons.lan_rounded,
      'matter' => Icons.join_inner_rounded,
      _ => Icons.device_unknown_rounded,
    };
