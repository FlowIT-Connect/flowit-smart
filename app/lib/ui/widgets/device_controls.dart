import 'package:flutter/material.dart';

import '../../core/icons.dart';
import '../../core/l10n.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../screens/device_detail.dart';
import 'common.dart';

String capabilityLabel(BuildContext context, String key) => context.tryTr('cap.$key') ?? key.replaceAll('_', ' ');

String optionLabel(BuildContext context, String option) => context.tryTr('option.$option') ?? option;

/// Valeur lisible d'une capacité (unité, booléens traduits).
String formatValue(BuildContext context, Capability? cap, String key, dynamic value) {
  if (value == null) return '—';
  if (value is bool) {
    final specific = context.tryTr('value.$key.${value ? 'true' : 'false'}');
    return specific ?? context.tr(value ? 'value.on' : 'value.off');
  }
  if (value is num) {
    final step = cap?.step ?? 1;
    final text = (step < 1 || value is double && value != value.roundToDouble()) ? value.toStringAsFixed(1) : value.round().toString();
    final unit = cap?.unit;
    return unit == null ? text : '$text $unit';
  }
  if (cap?.type == CapabilityType.enumeration) return optionLabel(context, value.toString());
  return value.toString();
}

Color? parseHexColor(dynamic v) {
  if (v is! String || !RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(v)) return null;
  return Color(int.parse(v.replaceFirst('#', ''), radix: 16) | 0xFF000000);
}

String toHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Indicateur d'état d'une commande : attente, confirmée, échec (§5.4).
class CommandIndicator extends StatelessWidget {
  const CommandIndicator(this.pending, {super.key, this.compact = false});

  final PendingCommand? pending;

  /// Icône seule (tuiles étroites), libellé en info-bulle.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = pending;
    if (p == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final label = context.tr('command.status.${p.status.name}');
    final Widget icon = p.isWaiting
        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        : Icon(p.status == CommandStatus.confirmed ? Icons.check_circle : Icons.error_outline,
            size: 18, color: p.status == CommandStatus.confirmed ? Colors.green.shade600 : scheme.error);
    if (compact) {
      return Semantics(liveRegion: true, label: label, child: Tooltip(message: label, child: icon));
    }
    return Semantics(
      liveRegion: true,
      label: label,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        icon,
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ]),
    );
  }
}

/// Tuile d'appareil (grilles Accueil / Pièces / Appareils).
class DeviceTile extends StatelessWidget {
  const DeviceTile(this.device, {super.key, this.showRoom = true});

  final Device device;
  final bool showRoom;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    final d = device;
    final sw = d.primarySwitch;
    final pending = sw == null ? null : state.pendingFor(d.id, 'switch');
    final on = (pending?.isWaiting ?? false) ? pending!.value == true : d.isOn == true;
    final active = d.isOnline && d.isOn == true; // couleur = état confirmé, pas la demande en cours
    final subtitle = _summary(context, d);
    final room = showRoom ? state.roomById(d.roomId)?.name : null;

    return Card(
      color: active ? scheme.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showDeviceDetail(context, d.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(deviceIcon(d), color: active ? scheme.onPrimaryContainer : (d.isOnline ? scheme.primary : scheme.outline)),
                const Spacer(),
                if (pending != null) CommandIndicator(pending, compact: true) else AvailabilityBadge(d.availability, compact: true),
              ]),
              const Spacer(),
              Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
              Text(
                [?room, subtitle].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              if (sw != null && sw.isControl)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Switch(
                    value: on,
                    onChanged: !d.isOnline || d.isSensitive || (pending?.isWaiting ?? false)
                        ? null
                        : (v) => state.sendCommand(d, 'switch', v),
                  ),
                )
              else
                const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  String _summary(BuildContext context, Device d) {
    if (d.availability == Availability.unavailable) return context.tr('availability.unavailable');
    if (d.isUnsupported) return context.tr('device.unsupportedShort');
    if (d.isSensitive) return context.tr('device.sensitiveShort');
    if (d.availability == Availability.unknown && d.state.isEmpty) return context.tr('availability.unknown');
    for (final key in ['switch', 'cover_position', 'target_temperature', 'temperature', 'contact', 'motion', 'power']) {
      final cap = d.capability(key);
      if (cap != null && d.state.containsKey(key)) {
        final v = formatValue(context, cap, key, d.state[key]);
        return key == 'switch' ? v : (key == 'temperature' || key == 'power' ? v : '${capabilityLabel(context, key)} $v');
      }
    }
    return '';
  }
}

/// Grille adaptative de tuiles.
class DeviceGrid extends StatelessWidget {
  const DeviceGrid(this.devices, {super.key, this.showRoom = true});

  final List<Device> devices;
  final bool showRoom;

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisExtent: 152,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          delegate: SliverChildBuilderDelegate((context, i) => DeviceTile(devices[i], showRoom: showRoom), childCount: devices.length),
        ),
      );
}

/// Contrôles d'un appareil, générés depuis ses capacités réelles (§5.3, §5.4).
class DeviceControlPanel extends StatelessWidget {
  const DeviceControlPanel(this.device, {super.key});

  final Device device;

  @override
  Widget build(BuildContext context) {
    final d = device;
    final children = <Widget>[];

    if (d.isSensitive) {
      children.add(_Notice(icon: Icons.shield_outlined, text: context.tr('device.sensitiveBlocked')));
    } else if (d.availability == Availability.unavailable && d.controls.isNotEmpty) {
      children.add(_Notice(icon: Icons.link_off, text: context.tr('device.offlineControls')));
    }
    if (d.isUnsupported) {
      children.add(_Notice(icon: Icons.info_outline, text: context.tr('device.unsupported')));
    }
    for (final cap in d.controls) {
      if (d.isSensitive) break;
      children.add(_CapabilityControl(device: d, cap: cap));
    }
    if (d.readings.isNotEmpty) {
      children.add(SectionHeader(context.tr('device.readings')));
      for (final cap in d.readings) {
        children.add(ListTile(
          leading: Icon(capabilityIcon(cap.key)),
          title: Text(capabilityLabel(context, cap.key)),
          trailing: Text(formatValue(context, cap, cap.key, d.state[cap.key]), style: Theme.of(context).textTheme.titleMedium),
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Icon(icon, color: scheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ]),
    );
  }
}

class _CapabilityControl extends StatefulWidget {
  const _CapabilityControl({required this.device, required this.cap});

  final Device device;
  final Capability cap;

  @override
  State<_CapabilityControl> createState() => _CapabilityControlState();
}

class _CapabilityControlState extends State<_CapabilityControl> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final d = widget.device;
    final cap = widget.cap;
    final pending = state.pendingFor(d.id, cap.key);
    final waiting = pending?.isWaiting ?? false;
    final current = waiting ? pending!.value : d.state[cap.key];
    final enabled = d.availability != Availability.unavailable && !waiting;
    void send(dynamic v) => state.sendCommand(d, cap.key, v);

    final title = Text(capabilityLabel(context, cap.key));
    final indicator = CommandIndicator(pending);

    switch (cap.type) {
      case CapabilityType.boolean:
        return SwitchListTile(
          secondary: Icon(capabilityIcon(cap.key)),
          title: title,
          subtitle: pending != null ? Align(alignment: AlignmentDirectional.centerStart, child: indicator) : null,
          value: current == true,
          onChanged: enabled ? send : null,
        );
      case CapabilityType.number:
        if (cap.key == 'target_temperature') {
          final v = (current as num?) ?? cap.min;
          return ListTile(
            leading: Icon(capabilityIcon(cap.key)),
            title: title,
            subtitle: pending != null ? Align(alignment: AlignmentDirectional.centerStart, child: indicator) : null,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton.filledTonal(
                tooltip: context.tr('common.decrease'),
                onPressed: enabled && v > cap.min ? () => send(_round(v - cap.step, cap)) : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 72,
                child: Text(formatValue(context, cap, cap.key, v), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton.filledTonal(
                tooltip: context.tr('common.increase'),
                onPressed: enabled && v < cap.max ? () => send(_round(v + cap.step, cap)) : null,
                icon: const Icon(Icons.add),
              ),
            ]),
          );
        }
        final v = (_drag ?? (current as num?)?.toDouble() ?? cap.min.toDouble()).clamp(cap.min.toDouble(), cap.max.toDouble());
        final divisions = ((cap.max - cap.min) / cap.step).round();
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ListTile(
              leading: Icon(capabilityIcon(cap.key)),
              title: title,
              subtitle: pending != null ? Align(alignment: AlignmentDirectional.centerStart, child: indicator) : null,
              trailing: Text(formatValue(context, cap, cap.key, _round(v, cap)), style: Theme.of(context).textTheme.titleMedium),
            ),
            if (cap.key == 'cover_position')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: enabled ? () => send(cap.max) : null,
                      icon: const Icon(Icons.keyboard_arrow_up),
                      label: Text(context.tr('cover.open')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: enabled ? () => send(cap.min) : null,
                      icon: const Icon(Icons.keyboard_arrow_down),
                      label: Text(context.tr('cover.close')),
                    ),
                  ),
                ]),
              ),
            Slider(
              value: v,
              min: cap.min.toDouble(),
              max: cap.max.toDouble(),
              divisions: divisions > 0 && divisions <= 1000 ? divisions : null,
              label: formatValue(context, cap, cap.key, _round(v, cap)),
              onChanged: enabled ? (x) => setState(() => _drag = x) : null,
              onChangeEnd: enabled
                  ? (x) {
                      setState(() => _drag = null);
                      send(_round(x, cap));
                    }
                  : null,
            ),
          ]),
        );
      case CapabilityType.enumeration:
        return ListTile(
          leading: Icon(capabilityIcon(cap.key)),
          title: title,
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final o in cap.options)
                ChoiceChip(
                  label: Text(optionLabel(context, o)),
                  selected: current == o,
                  onSelected: enabled && current != o ? (_) => send(o) : null,
                ),
              if (pending != null) indicator,
            ]),
          ),
        );
      case CapabilityType.color:
        final selected = parseHexColor(current);
        const palette = [
          Color(0xFFFFFFFF), Color(0xFFFFC46B), Color(0xFFFF6B6B), Color(0xFFE91E63), Color(0xFF9C27B0),
          Color(0xFF3F51B5), Color(0xFF03A9F4), Color(0xFF00BFA5), Color(0xFF8BC34A), Color(0xFFFFEB3B),
        ];
        return ListTile(
          leading: Icon(capabilityIcon(cap.key)),
          title: title,
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final c in palette)
                Semantics(
                  button: true,
                  selected: selected?.toARGB32() == c.toARGB32(),
                  label: toHex(c),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: enabled ? () => send(toHex(c)) : null,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected?.toARGB32() == c.toARGB32() ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant,
                          width: selected?.toARGB32() == c.toARGB32() ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
                ),
              if (pending != null) indicator,
            ]),
          ),
        );
      case CapabilityType.string:
      case CapabilityType.sensor:
        return ListTile(
          leading: Icon(capabilityIcon(cap.key)),
          title: title,
          trailing: Text(formatValue(context, cap, cap.key, current)),
        );
    }
  }

  num _round(num v, Capability cap) {
    final steps = ((v - cap.min) / cap.step).round();
    final r = cap.min + steps * cap.step;
    return cap.step is int && cap.min is int ? r.round() : double.parse(r.toStringAsFixed(2));
  }
}
