import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import 'device_controls.dart';

/// Action modifiable : appareil + capacité + valeur (+ délai pour les scènes).
class EditableAction {
  String? deviceId;
  String? capabilityKey;
  dynamic value;
  int delayMs;

  EditableAction({this.deviceId, this.capabilityKey, this.value, this.delayMs = 0});

  bool get isComplete => deviceId != null && capabilityKey != null && value != null;
}

/// Appareils proposables dans une action : commandables et non sensibles.
List<Device> actionableDevices(AppState state) =>
    state.devices.values.where((d) => !d.isSensitive && d.controls.isNotEmpty).toList()..sort((a, b) => a.name.compareTo(b.name));

dynamic defaultValueFor(Capability c) => switch (c.type) {
      CapabilityType.boolean => true,
      CapabilityType.number => c.key == 'cover_position' ? c.max : (c.min + c.max) ~/ 2,
      CapabilityType.enumeration => c.options.isEmpty ? null : c.options.first,
      CapabilityType.color => '#FFC46B',
      _ => null,
    };

class ActionEditorCard extends StatelessWidget {
  const ActionEditorCard({
    super.key,
    required this.action,
    required this.onChanged,
    required this.onRemove,
    this.onMoveUp,
    this.onMoveDown,
    this.showDelay = false,
    this.index,
  });

  final EditableAction action;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final bool showDelay;
  final int? index;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final devices = actionableDevices(state);
    final device = state.devices[action.deviceId];
    final caps = device?.controls ?? const <Capability>[];
    final cap = device?.capability(action.capabilityKey ?? '');

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (index != null) Text('${index! + 1}.', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            if (onMoveUp != null) IconButton(tooltip: context.tr('common.moveUp'), onPressed: onMoveUp, icon: const Icon(Icons.arrow_upward)),
            if (onMoveDown != null) IconButton(tooltip: context.tr('common.moveDown'), onPressed: onMoveDown, icon: const Icon(Icons.arrow_downward)),
            IconButton(tooltip: context.tr('common.delete'), onPressed: onRemove, icon: const Icon(Icons.delete_outline)),
          ]),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: DropdownButtonFormField<String>(
              initialValue: device == null ? null : action.deviceId,
              isExpanded: true,
              decoration: InputDecoration(labelText: context.tr('action.device')),
              items: [for (final d in devices) DropdownMenuItem(value: d.id, child: Text(d.name, overflow: TextOverflow.ellipsis))],
              onChanged: (id) {
                action.deviceId = id;
                final first = state.devices[id]?.controls.firstOrNull;
                action.capabilityKey = first?.key;
                action.value = first == null ? null : defaultValueFor(first);
                onChanged();
              },
            ),
          ),
          if (device != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: DropdownButtonFormField<String>(
                key: ValueKey('cap-${action.deviceId}'),
                initialValue: cap?.key,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.tr('action.capability')),
                items: [for (final c in caps) DropdownMenuItem(value: c.key, child: Text(capabilityLabel(context, c.key)))],
                onChanged: (k) {
                  action.capabilityKey = k;
                  final c = device.capability(k ?? '');
                  action.value = c == null ? null : defaultValueFor(c);
                  onChanged();
                },
              ),
            ),
          ],
          if (cap != null) ...[
            const SizedBox(height: 8),
            ValueEditor(cap: cap, value: action.value, onChanged: (v) {
              action.value = v;
              onChanged();
            }),
          ],
          if (showDelay) ...[
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.timer_outlined, size: 20),
              const SizedBox(width: 8),
              Text(context.tr('action.delay')),
              const Spacer(),
              DropdownButton<int>(
                value: const [0, 1000, 2000, 5000, 10000, 30000, 60000, 300000].contains(action.delayMs) ? action.delayMs : 0,
                items: [
                  for (final ms in const [0, 1000, 2000, 5000, 10000, 30000, 60000, 300000])
                    DropdownMenuItem(value: ms, child: Text(ms == 0 ? context.tr('action.noDelay') : (ms < 60000 ? '${ms ~/ 1000} s' : '${ms ~/ 60000} min'))),
                ],
                onChanged: (v) {
                  action.delayMs = v ?? 0;
                  onChanged();
                },
              ),
              const SizedBox(width: 8),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// Choix d'une valeur cible selon le type de capacité.
class ValueEditor extends StatelessWidget {
  const ValueEditor({super.key, required this.cap, required this.value, required this.onChanged});

  final Capability cap;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  Widget build(BuildContext context) {
    switch (cap.type) {
      case CapabilityType.boolean:
        return SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, label: Text(formatValue(context, cap, cap.key, true))),
            ButtonSegment(value: false, label: Text(formatValue(context, cap, cap.key, false))),
          ],
          selected: {value == true},
          onSelectionChanged: (s) => onChanged(s.first),
        );
      case CapabilityType.number:
        final v = ((value as num?) ?? cap.min).toDouble().clamp(cap.min.toDouble(), cap.max.toDouble());
        final divisions = ((cap.max - cap.min) / cap.step).round();
        return Row(children: [
          Expanded(
            child: Slider(
              value: v,
              min: cap.min.toDouble(),
              max: cap.max.toDouble(),
              divisions: divisions > 0 && divisions <= 1000 ? divisions : null,
              onChanged: (x) {
                final steps = ((x - cap.min) / cap.step).round();
                final r = cap.min + steps * cap.step;
                onChanged(cap.step is int && cap.min is int ? r.round() : double.parse(r.toStringAsFixed(2)));
              },
            ),
          ),
          SizedBox(width: 72, child: Text(formatValue(context, cap, cap.key, value ?? v), textAlign: TextAlign.end)),
          const SizedBox(width: 8),
        ]);
      case CapabilityType.enumeration:
        return Wrap(spacing: 8, children: [
          for (final o in cap.options) ChoiceChip(label: Text(optionLabel(context, o)), selected: value == o, onSelected: (_) => onChanged(o)),
        ]);
      case CapabilityType.color:
        const palette = ['#FFFFFF', '#FFC46B', '#FF6B6B', '#E91E63', '#9C27B0', '#3F51B5', '#03A9F4', '#00BFA5', '#8BC34A', '#FFEB3B'];
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final hex in palette)
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onChanged(hex),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: parseHexColor(hex),
                  shape: BoxShape.circle,
                  border: Border.all(
                    width: value == hex ? 3 : 1,
                    color: value == hex ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
        ]);
      case CapabilityType.string:
      case CapabilityType.sensor:
        return const SizedBox.shrink();
    }
  }
}

/// Résumé lisible d'une action ("Plafonnier : Luminosité → 20 %").
String describeAction(BuildContext context, AppState state, String deviceId, String capKey, dynamic value) {
  final d = state.devices[deviceId];
  final cap = d?.capability(capKey);
  return '${d?.name ?? context.tr('device.gone')} : ${capabilityLabel(context, capKey)} → ${formatValue(context, cap, capKey, value)}';
}
