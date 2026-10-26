import 'package:flutter/material.dart';

import '../models/models.dart';

/// Icônes de pièces proposées (clé stockée dans rooms.icon).
const roomIcons = <String, IconData>{
  'sofa': Icons.weekend_outlined,
  'bed': Icons.bed_outlined,
  'kitchen': Icons.kitchen_outlined,
  'dining': Icons.dining_outlined,
  'bath': Icons.bathtub_outlined,
  'office': Icons.desk_outlined,
  'child': Icons.child_care_outlined,
  'door': Icons.door_front_door_outlined,
  'garage': Icons.garage_outlined,
  'garden': Icons.yard_outlined,
  'stairs': Icons.stairs_outlined,
  'other': Icons.meeting_room_outlined,
};

IconData roomIcon(String? key) => roomIcons[key] ?? Icons.meeting_room_outlined;

/// Icônes de scènes (clé stockée dans scenes.icon).
const sceneIcons = <String, IconData>{
  'movie': Icons.movie_outlined,
  'night': Icons.bedtime_outlined,
  'sun': Icons.wb_sunny_outlined,
  'logout': Icons.logout,
  'home': Icons.home_outlined,
  'party': Icons.celebration_outlined,
  'meal': Icons.restaurant_outlined,
  'auto': Icons.auto_awesome_outlined,
};

IconData sceneIcon(String? key) => sceneIcons[key] ?? Icons.auto_awesome_outlined;

IconData deviceIcon(Device d) {
  bool has(String k) => d.capability(k) != null;
  if (d.isSensitive || has('lock')) return Icons.lock_outline;
  if (has('cover_position')) return Icons.blinds_outlined;
  if (has('target_temperature')) return Icons.thermostat_outlined;
  if (has('color') || has('brightness') || has('color_temp')) return Icons.lightbulb_outline;
  if (has('switch')) return Icons.power_settings_new;
  if (has('contact')) return Icons.sensor_door_outlined;
  if (has('motion')) return Icons.directions_run;
  if (has('temperature') || has('humidity')) return Icons.device_thermostat;
  return Icons.devices_other_outlined;
}

IconData capabilityIcon(String key) => switch (key) {
      'switch' => Icons.power_settings_new,
      'brightness' => Icons.brightness_6_outlined,
      'color_temp' => Icons.wb_incandescent_outlined,
      'color' => Icons.palette_outlined,
      'cover_position' => Icons.blinds_outlined,
      'target_temperature' => Icons.thermostat_outlined,
      'hvac_mode' => Icons.mode_fan_off_outlined,
      'lock' => Icons.lock_outline,
      'temperature' || 'current_temperature' => Icons.device_thermostat,
      'humidity' => Icons.water_drop_outlined,
      'battery' => Icons.battery_std_outlined,
      'power' => Icons.bolt_outlined,
      'energy' => Icons.electric_meter_outlined,
      'contact' => Icons.sensor_door_outlined,
      'motion' => Icons.directions_run,
      'illuminance' => Icons.light_mode_outlined,
      _ => Icons.tune,
    };

IconData protocolIcon(String protocol) => switch (protocol) {
      'zigbee' => Icons.hub_outlined,
      'ble' => Icons.bluetooth,
      'wifi' => Icons.wifi,
      'tuya' => Icons.cloud_outlined,
      'mqtt' => Icons.lan_outlined,
      'matter' => Icons.join_inner,
      _ => Icons.device_unknown_outlined,
    };
