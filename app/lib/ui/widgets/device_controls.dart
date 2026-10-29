import 'package:flutter/material.dart';

import '../../core/icons.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../screens/device_detail.dart';
import 'camera_view.dart';
import 'common.dart';
import 'device_visual.dart';

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
            size: 18, color: p.status == CommandStatus.confirmed ? context.flow.success : scheme.error);
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
///
/// Allumé, l'appareil « s'illumine » : carte claire, pastille pleine à sa couleur
/// et halo. Éteint ou hors ligne, il reste discret.
class DeviceTile extends StatelessWidget {
  const DeviceTile(this.device, {super.key, this.showRoom = true});

  final Device device;
  final bool showRoom;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final f = context.flow;
    final theme = Theme.of(context);
    final d = device;
    final sw = d.primarySwitch;
    final pending = sw == null ? null : state.pendingFor(d.id, 'switch');
    final on = (pending?.isWaiting ?? false) ? pending!.value == true : d.isOn == true;
    final active = d.isOnline && d.isOn == true; // couleur = état confirmé, pas la demande en cours
    final subtitle = _summary(context, d);
    final room = showRoom ? state.roomById(d.roomId)?.name : null;
    final reading = sw == null ? _headline(context, d) : null;
    final ink = active ? f.tileOnInk : f.ink;
    final inkSoft = active ? f.tileOnInkSoft : f.inkSoft;

    return Card(
      color: active ? f.tileOn : f.tileOff,
      elevation: active ? 6 : 0,
      shadowColor: active ? f.brand.withValues(alpha: .18) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: active ? f.brand.withValues(alpha: .28) : f.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showDeviceDetail(context, d.id),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 10, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Opacity(
                  opacity: d.isOnline ? 1 : .55,
                  child: DeviceVisual(d, size: 42, photoSize: 52, active: active),
                ),
                const Spacer(),
                if (pending != null)
                  Padding(padding: const EdgeInsetsDirectional.only(end: 4), child: CommandIndicator(pending, compact: true))
                else if (!d.isOnline || sw == null || !sw.isControl)
                  Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: AvailabilityBadge(d.availability, compact: true)),
                if (sw != null && sw.isControl)
                  Transform.scale(
                    scale: .82,
                    alignment: AlignmentDirectional.centerEnd,
                    child: Switch(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      value: on,
                      onChanged: !d.isOnline || d.isSensitive || (pending?.isWaiting ?? false)
                          ? null
                          : (v) => state.sendCommand(d, 'switch', v),
                    ),
                  ),
              ]),
              const Spacer(),
              if (reading != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(reading, style: theme.textTheme.headlineSmall?.copyWith(color: ink, height: 1.1, fontWeight: FontWeight.w300)),
                ),
              Text(d.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(color: ink, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                [?room, if (reading == null || subtitle != reading) subtitle].where((e) => e.isNotEmpty).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: d.availability == Availability.unavailable ? f.danger : inkSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Mesure mise en avant sur la tuile d'un capteur ou d'un thermostat.
  String? _headline(BuildContext context, Device d) {
    if (!d.isOnline) return null;
    for (final key in ['temperature', 'current_temperature', 'target_temperature', 'cover_position', 'humidity', 'power']) {
      final cap = d.capability(key);
      if (cap != null && d.state[key] is num) return formatValue(context, cap, key, d.state[key]);
    }
    return null;
  }

  String _summary(BuildContext context, Device d) {
    if (d.availability == Availability.unavailable) return context.tr('availability.unavailable');
    if (d.isUnsupported) return context.tr('device.unsupportedShort');
    if (d.isSensitive) return context.tr('device.sensitiveShort');
    if (d.availability == Availability.unknown && d.state.isEmpty) return context.tr('availability.unknown');
    if (d.isCamera) return context.tr('camera.tapToView');
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
            maxCrossAxisExtent: 210,
            mainAxisExtent: 164,
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
      children.add(_Notice(icon: Icons.shield_rounded, text: context.tr('device.sensitiveBlocked')));
    } else if (d.availability == Availability.unavailable && d.controls.isNotEmpty) {
      children.add(_Notice(icon: Icons.link_off_rounded, text: context.tr('device.offlineControls')));
    }
    if (d.isUnsupported) {
      children.add(_Notice(icon: Icons.info_outline_rounded, text: context.tr('device.unsupported')));
    }
    if (d.isCamera) {
      if (d.availability == Availability.unavailable) {
        children.add(_Notice(icon: Icons.videocam_off_rounded, text: context.tr('camera.offline')));
      } else {
        children.add(CameraLiveView(key: ValueKey('camera-${d.id}'), device: d));
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(22, 2, 22, 8),
          child: Text(context.tr('camera.privacy'), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.flow.inkSoft)),
        ));
      }
    }
    for (final cap in d.controls) {
      if (d.isSensitive) break;
      children.add(_ControlCard(child: _CapabilityControl(device: d, cap: cap)));
    }
    if (d.readings.isNotEmpty) {
      children.add(SectionHeader(context.tr('device.readings')));
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LayoutBuilder(builder: (context, box) {
          final cols = box.maxWidth > 420 ? 3 : 2;
          final w = (box.maxWidth - 10 * (cols - 1)) / cols;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final cap in d.readings) SizedBox(width: w, child: _ReadingCard(device: d, cap: cap)),
          ]);
        }),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// Carte d'un contrôle dans la fiche d'appareil.
class _ControlCard extends StatelessWidget {
  const _ControlCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: child),
        ),
      );
}

/// Mesure d'un capteur (température, humidité, batterie…).
class _ReadingCard extends StatelessWidget {
  const _ReadingCard({required this.device, required this.cap});

  final Device device;
  final Capability cap;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(capabilityIcon(cap.key), size: 20, color: f.brand),
          const SizedBox(height: 10),
          Text(formatValue(context, cap, cap.key, device.state[cap.key]), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w300), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(capabilityLabel(context, cap.key), style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: f.warning.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        Icon(icon, color: f.warning),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: TextStyle(color: f.ink, height: 1.4, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

IconData _modeIcon(String o) => switch (o) {
      'off' => Icons.power_settings_new_rounded,
      'heat' => Icons.local_fire_department_rounded,
      'cool' => Icons.ac_unit_rounded,
      'auto' || 'heat_cool' => Icons.autorenew_rounded,
      'dry' => Icons.water_drop_rounded,
      'fan_only' => Icons.air_rounded,
      _ => Icons.tune_rounded,
    };

/// Bouton rond − / + (plein = action principale, orange).
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, this.onPressed, this.filled = false});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      iconSize: 26,
      style: IconButton.styleFrom(
        fixedSize: const Size(58, 58),
        backgroundColor: filled ? f.brand : f.chip,
        foregroundColor: filled ? f.onBrand : f.ink,
        disabledBackgroundColor: f.chip.withValues(alpha: .5),
        disabledForegroundColor: f.inkFaint,
        shadowColor: f.brand.withValues(alpha: .4),
        elevation: filled && onPressed != null ? 6 : 0,
      ),
      icon: Icon(icon),
    );
  }
}

/// Mode (chaud, froid…) : cercle avec icône et libellé dessous.
class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.icon, required this.label, required this.selected, this.onPressed});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: 68,
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? f.brand : Colors.transparent,
                border: Border.all(color: selected ? f.brand : f.line, width: 1.4),
                boxShadow: selected ? [BoxShadow(color: f.brand.withValues(alpha: .35), blurRadius: 14, offset: const Offset(0, 6))] : null,
              ),
              child: Icon(icon, color: selected ? f.onBrand : f.inkSoft, size: 26),
            ),
            const SizedBox(height: 6),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: selected ? f.ink : f.inkSoft)),
          ]),
        ),
      ),
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
          secondary: TileIcon(capabilityIcon(cap.key)),
          title: title,
          subtitle: pending != null ? Align(alignment: AlignmentDirectional.centerStart, child: indicator) : null,
          value: current == true,
          onChanged: enabled ? send : null,
        );
      case CapabilityType.number:
        if (cap.key == 'target_temperature') {
          // Grand chiffre fin et boutons ronds − / +, façon thermostat.
          final v = (current as num?) ?? cap.min;
          final f = context.flow;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                TileIcon(capabilityIcon(cap.key), color: f.orange),
                const SizedBox(width: 14),
                Expanded(child: DefaultTextStyle.merge(style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600), child: title)),
                if (pending != null) indicator,
              ]),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: Text(
                    formatValue(context, cap, cap.key, v),
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w300, color: f.ink),
                  ),
                ),
                _RoundButton(
                  tooltip: context.tr('common.decrease'),
                  icon: Icons.remove_rounded,
                  onPressed: enabled && v > cap.min ? () => send(_round(v - cap.step, cap)) : null,
                ),
                const SizedBox(width: 14),
                _RoundButton(
                  tooltip: context.tr('common.increase'),
                  icon: Icons.add_rounded,
                  filled: true,
                  onPressed: enabled && v < cap.max ? () => send(_round(v + cap.step, cap)) : null,
                ),
              ]),
            ]),
          );
        }
        final v = (_drag ?? (current as num?)?.toDouble() ?? cap.min.toDouble()).clamp(cap.min.toDouble(), cap.max.toDouble());
        final divisions = ((cap.max - cap.min) / cap.step).round();
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ListTile(
              leading: TileIcon(capabilityIcon(cap.key)),
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
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                      label: Text(context.tr('cover.open')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: enabled ? () => send(cap.min) : null,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      label: Text(context.tr('cover.close')),
                    ),
                  ),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: cap.key == 'cover_position' ? context.flow.blue : (cap.key.contains('temp') ? context.flow.orange : deviceAccent(context, d)),
                ),
                child: Slider(
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
              ),
            ),
          ]),
        );
      case CapabilityType.enumeration:
        if (cap.key == 'hvac_mode') {
          // Modes en gros boutons ronds, le mode actif rempli d'orange.
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                TileIcon(capabilityIcon(cap.key)),
                const SizedBox(width: 14),
                Expanded(child: DefaultTextStyle.merge(style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600), child: title)),
                if (pending != null) indicator,
              ]),
              const SizedBox(height: 14),
              Wrap(spacing: 14, runSpacing: 12, children: [
                for (final o in cap.options)
                  _ModeButton(
                    icon: _modeIcon(o),
                    label: optionLabel(context, o),
                    selected: current == o,
                    onPressed: enabled && current != o ? () => send(o) : null,
                  ),
              ]),
            ]),
          );
        }
        return ListTile(
          leading: TileIcon(capabilityIcon(cap.key)),
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
          leading: TileIcon(capabilityIcon(cap.key)),
          title: title,
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final c in palette)
                Semantics(
                  button: true,
                  selected: selected?.toARGB32() == c.toARGB32(),
                  label: toHex(c),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: enabled ? () => send(toHex(c)) : null,
                    child: Container(
                      width: 38,
                      height: 38,
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
          leading: TileIcon(capabilityIcon(cap.key)),
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
