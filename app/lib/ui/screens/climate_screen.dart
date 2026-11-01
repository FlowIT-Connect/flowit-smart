import 'package:flutter/material.dart';

import '../../core/climate.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/device_controls.dart';

String _two(int v) => v.toString().padLeft(2, '0');
String _fmtTemp(double? t) => t == null ? '—' : '${t == t.roundToDouble() ? t.toStringAsFixed(0) : t.toStringAsFixed(1)} °C';

/// Durées proposées pour une ambiance choisie à la main.
Future<(bool, DateTime?)?> _askDuration(BuildContext context, String preset) {
  final now = DateTime.now();
  final tomorrow7 = DateTime(now.year, now.month, now.day + 1, 7);
  return showModalBottomSheet<(bool, DateTime?)>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: Icon(presetIcon(preset)), title: Text(optionLabel(ctx, preset), style: Theme.of(ctx).textTheme.titleMedium)),
        ListTile(leading: const Icon(Icons.all_inclusive_rounded), title: Text(ctx.tr('climate.until.forever')), onTap: () => Navigator.pop(ctx, (true, null))),
        ListTile(leading: const Icon(Icons.timer_outlined), title: Text(ctx.tr('climate.until.2h')), onTap: () => Navigator.pop(ctx, (true, now.add(const Duration(hours: 2))))),
        ListTile(leading: const Icon(Icons.wb_twilight_rounded), title: Text(ctx.tr('climate.until.morning')), onTap: () => Navigator.pop(ctx, (true, tomorrow7))),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

/// Boutons d'ambiance (Programme, Confort, Éco, Nuit, Absence) pour la maison ou une pièce.
class ClimatePresetButtons extends StatelessWidget {
  const ClimatePresetButtons({super.key, required this.current, this.roomId, this.compact = false});

  /// Ambiance imposée en ce moment (null = programme).
  final String? current;
  final String? roomId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final f = context.flow;
    Future<void> pick(String? preset) async {
      DateTime? until;
      if (preset != null) {
        final choice = await _askDuration(context, preset);
        if (choice == null) return;
        until = choice.$2;
      }
      if (!context.mounted) return;
      await state.setClimatePreset(roomId, preset,
          until: until, success: context.tr(preset == null ? 'climate.backToSchedule' : 'climate.presetOn', {'preset': preset == null ? '' : optionLabel(context, preset)}));
    }

    Widget button(String? preset) {
      final active = current == preset;
      final label = preset == null ? context.tr('option.schedule') : optionLabel(context, preset);
      return Expanded(
        child: Semantics(
          button: true,
          selected: active,
          label: label,
          child: InkWell(
            key: ValueKey('climate-${roomId ?? 'home'}-${preset ?? 'schedule'}'),
            borderRadius: BorderRadius.circular(16),
            onTap: active ? null : () => pick(preset),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: compact ? 6 : 10),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: compact ? 38 : 46,
                  height: compact ? 38 : 46,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: active ? f.orange : f.ink.withValues(alpha: .06)),
                  child: Icon(presetIcon(preset ?? 'schedule'), size: compact ? 20 : 22, color: active ? Colors.white : f.inkSoft),
                ),
                const SizedBox(height: 4),
                ExcludeSemantics(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: active ? f.ink : f.inkSoft)),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return Row(children: [button(null), for (final p in climateQuickPresets) button(p)]);
  }
}

String _sourceLabel(BuildContext context, String source) => context.tr('climate.source.$source');

/// Écran Chauffage et clim : ambiance de la maison, pièces, températures des ambiances.
class ClimateScreen extends StatefulWidget {
  const ClimateScreen({super.key});

  @override
  State<ClimateScreen> createState() => _ClimateScreenState();
}

class _ClimateScreenState extends State<ClimateScreen> {
  Map<String, PresetTemps>? _draft;

  @override
  void initState() {
    super.initState();
    AppScope.read(context).reloadClimate();
  }

  Future<void> _addZone(AppState state) async {
    final taken = state.climate.zones.map((z) => z.roomId).toSet();
    final free = state.rooms.where((r) => !taken.contains(r.id)).toList();
    final room = await showModalBottomSheet<Room>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text(ctx.tr('climate.addRoom'), style: Theme.of(ctx).textTheme.titleMedium)),
          if (free.isEmpty) ListTile(title: Text(ctx.tr('climate.noFreeRoom'))),
          for (final r in free) ListTile(leading: const Icon(Icons.meeting_room_rounded), title: Text(r.name), onTap: () => Navigator.pop(ctx, r)),
        ]),
      ),
    );
    if (room == null || !mounted) return;
    final devices = [
      for (final d in state.devices.values)
        if (d.roomId == room.id && (d.capability('target_temperature')?.writable ?? false)) d.id,
    ];
    final ok = await state.saveClimateZone(ClimateZone(roomId: room.id, devices: devices));
    if (!ok || !mounted) return;
    final zone = state.climate.zoneFor(room.id);
    if (zone != null) await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClimateZoneScreen(roomId: zone.roomId)));
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = state.climate;
    final manage = state.canManage;
    final home = c.settings.activeHomePreset();
    final f = context.flow;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('climate.title'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            SectionHeader(context.tr('climate.wholeHome')),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      home == null
                          ? context.tr(state.homeModes.vacationActive() ? 'climate.status.vacation' : 'climate.status.schedule')
                          : c.settings.homePresetUntil == null
                              ? context.tr('climate.status.preset', {'preset': optionLabel(context, home)})
                              : context.tr('climate.status.until', {
                                  'preset': optionLabel(context, home),
                                  'date': '${_two(c.settings.homePresetUntil!.day)}/${_two(c.settings.homePresetUntil!.month)} ${_two(c.settings.homePresetUntil!.hour)}:${_two(c.settings.homePresetUntil!.minute)}',
                                }),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClimatePresetButtons(current: home),
                ]),
              ),
            ),
            if (!c.settings.enabled) Padding(padding: const EdgeInsets.only(top: 8), child: Text(context.tr('climate.disabled'), style: TextStyle(color: f.danger))),
            SectionHeader(context.tr('climate.rooms')),
            if (c.zones.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(context.tr('climate.noRooms'))),
            for (final z in c.zones) _ZoneCard(zone: z),
            if (manage) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: () => _addZone(state), icon: const Icon(Icons.add_rounded), label: Text(context.tr('climate.addRoom'))),
              SectionHeader(context.tr('climate.presets')),
              Text(context.tr('climate.presets.help'), style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              ..._presetEditor(context, state),
              const SizedBox(height: 12),
              SwitchListTile(
                title: Text(context.tr('climate.enabled')),
                subtitle: Text(context.tr('climate.enabled.help')),
                value: c.settings.enabled,
                onChanged: (v) => state.saveClimateSettings(c.settings.copyWith(enabled: v)),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  List<Widget> _presetEditor(BuildContext context, AppState state) {
    final saved = state.climate.settings.presets;
    final draft = _draft ?? saved;
    Widget stepper(String preset, bool heat) {
      final t = draft[preset] ?? defaultPresetTemps[preset]!;
      final v = heat ? t.heat : t.cool;
      void set(double? nv) => setState(() {
            final next = Map<String, PresetTemps>.of(draft);
            next[preset] = heat ? PresetTemps(nv, t.cool) : PresetTemps(t.heat, nv);
            _draft = next;
          });
      return Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          style: IconButton.styleFrom(minimumSize: const Size(36, 36), fixedSize: const Size(36, 36), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          tooltip: context.tr('common.decrease'),
          icon: const Icon(Icons.remove_rounded, size: 18),
          onPressed: v == null || v <= 5 ? null : () => set(v - 0.5),
        ),
        SizedBox(width: 50, child: Text(_fmtTemp(v), textAlign: TextAlign.center, maxLines: 1)),
        IconButton(
          style: IconButton.styleFrom(minimumSize: const Size(36, 36), fixedSize: const Size(36, 36), padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          tooltip: context.tr('common.increase'),
          icon: const Icon(Icons.add_rounded, size: 18),
          onPressed: v != null && v >= 35 ? null : () => set((v ?? (heat ? 19 : 26)) + (v == null ? 0 : 0.5)),
        ),
      ]);
    }

    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const Expanded(child: SizedBox()),
                SizedBox(width: 122, child: Center(child: Icon(Icons.local_fire_department_rounded, color: context.flow.orange, semanticLabel: context.tr('option.heat')))),
                SizedBox(width: 122, child: Center(child: Icon(Icons.ac_unit_rounded, color: context.flow.blue, semanticLabel: context.tr('option.cool')))),
              ]),
            ),
            for (final p in climatePresets)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Row(children: [
                  Icon(presetIcon(p), size: 20, color: context.flow.inkSoft),
                  const SizedBox(width: 8),
                  Expanded(child: Text(optionLabel(context, p), overflow: TextOverflow.ellipsis)),
                  SizedBox(width: 122, child: stepper(p, true)),
                  SizedBox(width: 122, child: stepper(p, false)),
                ]),
              ),
          ]),
        ),
      ),
      if (_draft != null && _draft.toString() != saved.toString())
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FilledButton(
            onPressed: () async {
              final ok = await state.saveClimateSettings(state.climate.settings.copyWith(presets: _draft), success: context.tr('climate.presets.saved'));
              if (ok && mounted) setState(() => _draft = null);
            },
            child: Text(context.tr('common.save')),
          ),
        ),
    ];
  }
}

class _ZoneCard extends StatelessWidget {
  const _ZoneCard({required this.zone});

  final ClimateZone zone;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final room = state.roomById(zone.roomId);
    final (preset, source) = state.climatePresetFor(zone);
    final temps = state.climate.settings.temps(preset);
    double? measured;
    for (final id in zone.devices) {
      final v = state.devices[id]?.state['current_temperature'] ?? state.devices[id]?.state['temperature'];
      if (v is num) {
        measured = v.toDouble();
        break;
      }
    }
    final season = state.homeModes.season;
    final target = zone.activeTarget ?? (season == 'summer' ? temps.cool : temps.heat);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: TileIcon(presetIcon(preset), color: context.flow.orange),
        title: Text(room?.name ?? '—'),
        subtitle: Text([
          '${optionLabel(context, preset)} · ${_fmtTemp(target)}',
          [_sourceLabel(context, source), if (measured != null) context.tr('climate.measured', {'t': _fmtTemp(measured)})].join(' · '),
          if (!zone.enabled) context.tr('climate.zoneOff'),
        ].join('\n')),
        isThreeLine: true,
        trailing: const ForwardChevron(),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClimateZoneScreen(roomId: zone.roomId))),
      ),
    );
  }
}

/// Réglage d'une pièce : ambiance du moment, appareils pilotés, programme de la semaine.
class ClimateZoneScreen extends StatefulWidget {
  const ClimateZoneScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<ClimateZoneScreen> createState() => _ClimateZoneScreenState();
}

class _ClimateZoneScreenState extends State<ClimateZoneScreen> {
  ClimateZone? _draft;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final saved = state.climate.zoneFor(widget.roomId);
    if (saved == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: Text(context.tr('climate.noRooms'))));
    }
    final z = _draft ?? saved;
    final manage = state.canManage;
    final room = state.roomById(z.roomId);
    final dirty = _draft != null;
    final candidates = state.devices.values.where((d) => d.capability('target_temperature')?.writable ?? false).toList()
      ..sort((a, b) => (a.roomId == z.roomId ? 0 : 1).compareTo(b.roomId == z.roomId ? 0 : 1));
    final (preset, source) = state.climatePresetFor(saved);
    final entries = [...z.schedule]..sort((a, b) {
        final da = a.days.isEmpty ? 8 : a.days.reduce((x, y) => x < y ? x : y);
        final db = b.days.isEmpty ? 8 : b.days.reduce((x, y) => x < y ? x : y);
        return da != db ? da.compareTo(db) : a.minutes.compareTo(b.minutes);
      });

    void edit(ClimateZone next) => setState(() => _draft = next);

    return Scaffold(
      appBar: AppBar(
        title: Text(room?.name ?? context.tr('climate.title')),
        actions: [
          if (manage)
            IconButton(
              tooltip: context.tr('common.delete'),
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await state.deleteClimateZone(saved, success: context.tr('climate.zoneDeleted'));
                if (ok && context.mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            Text('${optionLabel(context, preset)} · ${_sourceLabel(context, source)}', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(child: Padding(padding: const EdgeInsets.all(8), child: ClimatePresetButtons(current: saved.activeOverride(), roomId: saved.roomId, compact: true))),
            if (manage) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('climate.zoneEnabled')),
                value: z.enabled,
                onChanged: (v) => edit(z.copyWith(enabled: v)),
              ),
              SectionHeader(context.tr('climate.devices')),
              if (candidates.isEmpty) Text(context.tr('climate.noDevices')),
              for (final d in candidates)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: z.devices.contains(d.id),
                  title: Text(d.name),
                  subtitle: Text(state.roomById(d.roomId)?.name ?? context.tr('room.none')),
                  onChanged: (v) => edit(z.copyWith(devices: v == true ? [...z.devices, d.id] : z.devices.where((x) => x != d.id).toList())),
                ),
              SectionHeader(context.tr('climate.schedule')),
              Text(context.tr('climate.schedule.help'), style: Theme.of(context).textTheme.bodySmall),
              for (final e in entries)
                _EntryRow(
                  entry: e,
                  onChanged: (next) => edit(z.copyWith(schedule: [for (final x in z.schedule) identical(x, e) ? next : x])),
                  onDelete: () => edit(z.copyWith(schedule: z.schedule.where((x) => !identical(x, e)).toList())),
                ),
              Wrap(spacing: 8, children: [
                TextButton.icon(
                  onPressed: z.schedule.length >= 48 ? null : () => edit(z.copyWith(schedule: [...z.schedule, const ScheduleEntry([1, 2, 3, 4, 5, 6, 7], '12:00', 'comfort')])),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(context.tr('climate.schedule.add')),
                ),
                TextButton.icon(
                  onPressed: () => edit(z.copyWith(schedule: defaultSchedule)),
                  icon: const Icon(Icons.auto_fix_high_rounded),
                  label: Text(context.tr('climate.schedule.template')),
                ),
              ]),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: dirty
                    ? () async {
                        final ok = await state.saveClimateZone(z, success: context.tr('climate.zoneSaved'));
                        if (ok && mounted) setState(() => _draft = null);
                      }
                    : null,
                child: Text(context.tr('common.save')),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.onChanged, required this.onDelete});

  final ScheduleEntry entry;
  final ValueChanged<ScheduleEntry> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final letters = context.tr('climate.days').split(',');
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.schedule_rounded, size: 18),
              label: Text(entry.at),
              onPressed: () async {
                final t = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: entry.minutes ~/ 60, minute: entry.minutes % 60),
                );
                if (t != null) onChanged(entry.copyWith(at: '${_two(t.hour)}:${_two(t.minute)}'));
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                value: entry.preset,
                underline: const SizedBox(),
                items: [for (final p in climatePresets) DropdownMenuItem(value: p, child: Text(optionLabel(context, p)))],
                onChanged: (p) => p == null ? null : onChanged(entry.copyWith(preset: p)),
              ),
            ),
            IconButton(tooltip: context.tr('common.delete'), icon: const Icon(Icons.close_rounded), onPressed: onDelete),
          ]),
          Wrap(spacing: 4, children: [
            for (var d = 1; d <= 7; d++)
              FilterChip(
                label: Text(letters.length == 7 ? letters[d - 1] : '$d'),
                visualDensity: VisualDensity.compact,
                showCheckmark: false,
                selected: entry.days.contains(d),
                onSelected: (on) {
                  final days = on ? ([...entry.days, d]..sort()) : entry.days.where((x) => x != d).toList();
                  if (days.isNotEmpty) onChanged(entry.copyWith(days: days));
                },
              ),
          ]),
        ]),
      ),
    );
  }
}

/// Carte de l'accueil : ambiance de la maison en un geste, accès aux réglages.
class ClimateHomeCard extends StatelessWidget {
  const ClimateHomeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final c = state.climate;
    if (c.zones.isEmpty && !state.canManage) return const SizedBox.shrink();
    final home = c.settings.activeHomePreset();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        child: Column(children: [
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: Icon(Icons.thermostat_rounded, color: context.flow.orange),
            title: Text(context.tr('climate.title')),
            subtitle: Text(c.zones.isEmpty
                ? context.tr('climate.noRooms')
                : home == null
                    ? context.tr(state.homeModes.vacationActive() ? 'climate.status.vacation' : 'climate.status.schedule')
                    : context.tr('climate.status.preset', {'preset': optionLabel(context, home)})),
            trailing: const ForwardChevron(),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ClimateScreen())),
          ),
          if (c.zones.isNotEmpty) ClimatePresetButtons(current: home, compact: true),
        ]),
      ),
    );
  }
}
