import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import 'common.dart';

/// Télécommande infrarouge (Broadlink RM4 Pro…) : touches apprises et apprentissage.

final _modeTemp = RegExp(r'^(cool|heat|dry|fan_only|auto|heat_cool)_(\d{2}(?:[.,]5)?)$');

/// Nom lisible d'une touche apprise (« volume_up » → « Volume + », « cool_22 » → « Froid 22° »).
String irKeyLabel(BuildContext context, String key) {
  final m = _modeTemp.firstMatch(key);
  if (m != null) return context.tr('ir.modeTemp', {'mode': context.tr('ir.mode.${m[1]}'), 't': m[2]});
  return context.tryTr('ir.key.$key') ?? (key.isEmpty ? key : key[0].toUpperCase() + key.substring(1).replaceAll('_', ' '));
}

IconData irKeyIcon(String key) => switch (key) {
  'power' || 'on' || 'off' => Icons.power_settings_new_rounded,
  'volume_up' => Icons.volume_up_rounded,
  'volume_down' => Icons.volume_down_rounded,
  'mute' => Icons.volume_off_rounded,
  'channel_up' => Icons.keyboard_arrow_up_rounded,
  'channel_down' => Icons.keyboard_arrow_down_rounded,
  'source' || 'input' => Icons.input_rounded,
  'up' => Icons.arrow_upward_rounded,
  'down' => Icons.arrow_downward_rounded,
  'left' => Icons.arrow_back_rounded,
  'right' => Icons.arrow_forward_rounded,
  'ok' => Icons.radio_button_checked_rounded,
  'back' => Icons.undo_rounded,
  'home' || 'menu' => Icons.home_rounded,
  'play' || 'pause' => Icons.play_arrow_rounded,
  'swing' => Icons.swap_vert_rounded,
  'speed' || 'fan' => Icons.air_rounded,
  _ when key.startsWith('cool') => Icons.ac_unit_rounded,
  _ when key.startsWith('heat') => Icons.local_fire_department_rounded,
  _ => Icons.radio_button_unchecked_rounded,
};

/// Touches d'une télécommande : un bouton par touche apprise, toujours disponible (même
/// pour répéter la dernière, comme sur la vraie télécommande).
class IrRemotePanel extends StatelessWidget {
  const IrRemotePanel({super.key, required this.device, required this.cap, required this.enabled, required this.indicator, required this.send});

  final Device device;
  final Capability cap;
  final bool enabled;
  final Widget? indicator;
  final void Function(dynamic) send;

  @override
  Widget build(BuildContext context) {
    final keys = cap.options;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const TileIcon(Icons.settings_remote_rounded),
              const SizedBox(width: 14),
              Expanded(
                child: Text(context.tr('cap.ir_command'), style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              ),
              ?indicator,
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final k in keys)
                k == 'power'
                    ? FilledButton.icon(onPressed: enabled ? () => send(k) : null, icon: Icon(irKeyIcon(k)), label: Text(irKeyLabel(context, k)))
                    : OutlinedButton.icon(onPressed: enabled ? () => send(k) : null, icon: Icon(irKeyIcon(k), size: 18), label: Text(irKeyLabel(context, k))),
            ],
          ),
          const SizedBox(height: 10),
          Text(context.tr('ir.noFeedback'), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.flow.inkSoft)),
        ],
      ),
    );
  }
}

/// Carte « Apprendre une touche » de la fiche du Broadlink.
class IrLearnCard extends StatelessWidget {
  const IrLearnCard({super.key, required this.device, required this.cap, required this.enabled});

  final Device device;
  final Capability cap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final learned = learnedCommands(cap);
    final summary = learned.isEmpty
        ? context.tr('ir.nothingLearned')
        : learned.entries.map((e) => '${irDeviceLabel(context, e.key)} : ${e.value.length}').join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const TileIcon(Icons.school_rounded),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('ir.learnTitle'), style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(summary, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.flow.inkSoft)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: enabled
                ? () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => IrLearnSheet(device: device, cap: cap),
                  )
                : null,
            icon: const Icon(Icons.settings_remote_rounded),
            label: Text(context.tr('ir.learnButton')),
          ),
        ],
      ),
    );
  }
}

/// Touches déjà apprises, par appareil (métadonnées de la capacité ir_learn).
Map<String, List<String>> learnedCommands(Capability cap) {
  final raw = cap.metadata['learned'];
  if (raw is! Map) return {};
  return {
    for (final e in raw.entries)
      if (e.value is List) e.key.toString(): [for (final c in e.value as List) c.toString()],
  };
}

String irDeviceLabel(BuildContext context, String sub) => context.tryTr('ir.device.$sub') ?? sub;

/// Profils proposés : télé (touches courantes) et clim (convention off / cool_22…).
const irProfiles = ['tv', 'clim', 'decodeur', 'ventilateur'];

List<(String, List<String>)> irSuggestions(String device) {
  final temps = [for (var t = 16; t <= 30; t++) t];
  return switch (device) {
    'clim' => [
      ('ir.group.basic', ['off', 'dry', 'fan_only', 'auto']),
      ('ir.group.cool', [for (final t in temps) 'cool_$t']),
      ('ir.group.heat', [for (final t in temps) 'heat_$t']),
      ('ir.group.other', ['swing', 'speed']),
    ],
    'ventilateur' => [
      ('ir.group.basic', ['power', 'speed', 'swing']),
    ],
    _ => [
      ('ir.group.basic', ['power', 'volume_up', 'volume_down', 'mute', 'channel_up', 'channel_down', 'source']),
      ('ir.group.nav', ['up', 'down', 'left', 'right', 'ok', 'back', 'home', 'menu']),
    ],
  };
}

/// Apprentissage guidé : choisir l'appareil et la touche, puis appuyer sur la vraie
/// télécommande pointée vers le Broadlink. La touche suivante est proposée aussitôt.
class IrLearnSheet extends StatefulWidget {
  const IrLearnSheet({super.key, required this.device, required this.cap});

  final Device device;
  final Capability cap;

  @override
  State<IrLearnSheet> createState() => _IrLearnSheetState();
}

class _IrLearnSheetState extends State<IrLearnSheet> {
  late final Map<String, Set<String>> _learned = {for (final e in learnedCommands(widget.cap).entries) e.key: e.value.toSet()};
  final _deviceCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  String _device = 'tv';
  String? _key;
  bool _busy = false;
  String? _message;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _key = _nextKey();
  }

  @override
  void dispose() {
    _deviceCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  String? _nextKey() {
    final done = _learned[_device] ?? const {};
    for (final (_, keys) in irSuggestions(_device)) {
      for (final k in keys) {
        if (!done.contains(k)) return k;
      }
    }
    return null;
  }

  String _cleanName(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');

  Future<void> _run(String key, {bool delete = false}) async {
    final state = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = false;
      _message = delete ? context.tr('ir.deleting') : context.tr('ir.pressNow', {'key': irKeyLabel(context, key)});
    });
    final r = await state.sendCommandAndWait(widget.device, 'ir_learn', {'device': _device, 'command': key, if (delete) 'action': 'delete'});
    if (!mounted) return;
    final ok = r?.status == CommandStatus.confirmed;
    setState(() {
      _busy = false;
      _error = !ok;
      if (ok) {
        final set = _learned.putIfAbsent(_device, () => {});
        delete ? set.remove(key) : set.add(key);
        _message = context.tr(delete ? 'ir.deleted' : 'ir.learned', {'key': irKeyLabel(context, key)});
        if (!delete) _key = _nextKey();
      } else {
        _message = r?.error ?? context.tr('ir.failed');
      }
    });
  }

  Future<void> _confirmDelete(String key) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(c.tr('ir.deleteTitle', {'key': irKeyLabel(c, key)})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(c.tr('ir.delete'))),
        ],
      ),
    );
    if (yes == true) await _run(key, delete: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = _learned[_device] ?? const <String>{};
    final devices = {...irProfiles, ..._learned.keys}.toList();
    final suggested = irSuggestions(_device).expand((g) => g.$2).toSet();
    final extra = done.where((k) => !suggested.contains(k)).toList()..sort();

    Widget keyChip(String k) => FilterChip(
      avatar: done.contains(k) ? const Icon(Icons.check_rounded, size: 16) : null,
      label: Text(irKeyLabel(context, k)),
      selected: _key == k,
      onSelected: _busy ? null : (_) => setState(() => _key = k),
      tooltip: done.contains(k) ? context.tr('ir.longPressDelete') : null,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        maxChildSize: .95,
        builder: (context, scroll) => Column(
          children: [
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                children: [
                  Text(context.tr('ir.learnTitle'), style: theme.textTheme.titleLarge),
                  const SizedBox(height: 6),
                  Text(context.tr('ir.learnHelp'), style: theme.textTheme.bodyMedium?.copyWith(color: context.flow.inkSoft)),
                  const SizedBox(height: 16),
                  Text(context.tr('ir.whichDevice'), style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final d in devices)
                        ChoiceChip(
                          label: Text(irDeviceLabel(context, d)),
                          selected: _device == d,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() {
                                  _device = d;
                                  _key = _nextKey();
                                  _message = null;
                                }),
                        ),
                      SizedBox(
                        width: 170,
                        child: TextField(
                          controller: _deviceCtrl,
                          enabled: !_busy,
                          decoration: InputDecoration(isDense: true, hintText: context.tr('ir.otherDevice')),
                          onSubmitted: (v) {
                            final name = _cleanName(v);
                            if (name.isEmpty) return;
                            setState(() {
                              _device = name;
                              _learned.putIfAbsent(name, () => {});
                              _key = _nextKey();
                              _deviceCtrl.clear();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_device == 'clim') ...[
                    const SizedBox(height: 10),
                    Text(context.tr('ir.climHelp'), style: theme.textTheme.bodySmall?.copyWith(color: context.flow.inkSoft)),
                  ],
                  for (final (title, keys) in irSuggestions(_device)) ...[
                    const SizedBox(height: 14),
                    Text(context.tr(title), style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final k in keys) GestureDetector(onLongPress: done.contains(k) && !_busy ? () => _confirmDelete(k) : null, child: keyChip(k)),
                      ],
                    ),
                  ],
                  if (extra.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(context.tr('ir.group.learned'), style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [for (final k in extra) GestureDetector(onLongPress: _busy ? null : () => _confirmDelete(k), child: keyChip(k))],
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: _keyCtrl,
                    enabled: !_busy,
                    decoration: InputDecoration(labelText: context.tr('ir.otherKey'), prefixIcon: const Icon(Icons.edit_rounded)),
                    onSubmitted: (v) {
                      final name = _cleanName(v);
                      if (name.isNotEmpty) setState(() => _key = name);
                    },
                    onChanged: (v) {
                      final name = _cleanName(v);
                      if (name.isNotEmpty) setState(() => _key = name);
                    },
                  ),
                ],
              ),
            ),
            // Toujours visible : l'état de l'apprentissage et le bouton.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_message != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: (_error ? theme.colorScheme.error : context.flow.brand).withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          if (_busy)
                            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                          else
                            Icon(
                              _error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
                              color: _error ? theme.colorScheme.error : context.flow.brand,
                            ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(_message!)),
                        ],
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: _busy || _key == null ? null : () => _run(_key!),
                    icon: const Icon(Icons.sensors_rounded),
                    label: Text(_key == null ? context.tr('ir.allLearned') : context.tr('ir.learnKey', {'key': irKeyLabel(context, _key!)})),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
