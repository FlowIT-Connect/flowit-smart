import 'package:flutter/material.dart';

import '../../core/glass.dart';
import '../../core/home_modes.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';

String _two(int v) => v.toString().padLeft(2, '0');
String _date(DateTime d) => '${_two(d.day)}/${_two(d.month)}';

/// Boutons Été / Hiver / Vacances de l'accueil (verre dépoli, comme le reste).
class HomeModesBar extends StatelessWidget {
  const HomeModesBar({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final m = state.homeModes;
    final canEdit = state.canManage;

    Future<void> season(String s) async {
      final next = m.season == s ? 'none' : s;
      await state.saveHomeModes(m.copyWith(season: next),
          success: context.tr(next == 'none' ? 'modes.seasonOff' : 'modes.on', {'mode': context.tr('modes.$next')}));
    }

    final vacationLabel = m.vacationActive()
        ? (m.vacationTo == null ? context.tr('modes.vacation') : context.tr('modes.vacationUntil', {'date': _date(m.vacationTo!)}))
        : m.vacationScheduled()
            ? context.tr('modes.vacationFrom', {'date': _date(m.vacationFrom!)})
            : context.tr('modes.vacation');

    return GlassPanel(
      radius: 24,
      padding: const EdgeInsets.all(6),
      child: Row(children: [
        Expanded(
          child: _ModeButton(
            key: const ValueKey('mode-summer'),
            icon: modeIcons['summer']!,
            label: context.tr('modes.summer'),
            color: const Color(0xFFF59E0B),
            active: m.season == 'summer',
            onTap: canEdit ? () => season('summer') : null,
          ),
        ),
        Expanded(
          child: _ModeButton(
            key: const ValueKey('mode-winter'),
            icon: modeIcons['winter']!,
            label: context.tr('modes.winter'),
            color: const Color(0xFF60A5FA),
            active: m.season == 'winter',
            onTap: canEdit ? () => season('winter') : null,
          ),
        ),
        Expanded(
          child: _ModeButton(
            key: const ValueKey('mode-vacation'),
            icon: modeIcons['vacation']!,
            label: vacationLabel,
            color: const Color(0xFF34D399),
            active: m.vacationActive(),
            pending: m.vacationScheduled(),
            onTap: () => showVacationSheet(context),
          ),
        ),
      ]),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({super.key, required this.icon, required this.label, required this.color, required this.active, this.pending = false, this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final bool active;
  final bool pending;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    return Semantics(
      button: true,
      selected: active,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: active ? color.withValues(alpha: .22) : Colors.transparent,
            border: Border.all(color: active || pending ? color.withValues(alpha: active ? .7 : .4) : Colors.transparent, width: 1.2),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 22, color: active || pending ? color : f.inkSoft),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: active ? FontWeight.w800 : FontWeight.w600, color: active ? f.ink : f.inkSoft),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Mode Vacances : dates, simulation de présence et lumières utilisées.
Future<void> showVacationSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _VacationSheet(),
    );

class _VacationSheet extends StatefulWidget {
  const _VacationSheet();

  @override
  State<_VacationSheet> createState() => _VacationSheetState();
}

class _VacationSheetState extends State<_VacationSheet> {
  late HomeModes _m = AppScope.read(context).homeModes;
  bool _saving = false;

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: _m.vacationFrom != null && _m.vacationTo != null ? DateTimeRange(start: _m.vacationFrom!, end: _m.vacationTo!) : null,
    );
    if (range == null) return;
    // Départ au début du premier jour, retour à la fin du dernier.
    setState(() => _m = _m.copyWith(
          vacationFrom: DateTime(range.start.year, range.start.month, range.start.day),
          vacationTo: DateTime(range.end.year, range.end.month, range.end.day).add(const Duration(days: 1)),
        ));
  }

  Future<void> _save() async {
    final state = AppScope.read(context);
    setState(() => _saving = true);
    final ok = await state.saveHomeModes(_m, success: context.tr(_m.vacation ? 'modes.vacationSaved' : 'modes.vacationOff'));
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final f = context.flow;
    final canEdit = state.canManage;
    final lights = state.visibleDevices.where((d) => d.capability('switch')?.writable ?? false).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Icon(modeIcons['vacation'], color: const Color(0xFF34D399)),
              const SizedBox(width: 10),
              Expanded(child: Text(context.tr('modes.vacation'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 6),
            Text(context.tr('modes.vacationHelp'), style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft, height: 1.4)),
            SwitchListTile(
              key: const ValueKey('vacation-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('modes.vacationEnable')),
              value: _m.vacation,
              onChanged: canEdit ? (v) => setState(() => _m = _m.copyWith(vacation: v)) : null,
            ),
            if (_m.vacation) ...[
              ListTile(
                key: const ValueKey('vacation-dates'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.date_range_rounded),
                title: Text(context.tr('modes.dates')),
                subtitle: Text(_m.vacationFrom == null || _m.vacationTo == null
                    ? context.tr('modes.noDates')
                    : context.tr('modes.dateRange', {'from': _date(_m.vacationFrom!), 'to': _date(_m.vacationTo!.subtract(const Duration(days: 1)))})),
                trailing: _m.vacationFrom == null
                    ? null
                    : IconButton(
                        tooltip: context.tr('common.delete'),
                        onPressed: canEdit ? () => setState(() => _m = _m.copyWith(clearDates: true)) : null,
                        icon: const Icon(Icons.close_rounded),
                      ),
                onTap: canEdit ? _pickDates : null,
              ),
              SwitchListTile(
                key: const ValueKey('simulation-switch'),
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('modes.simulation')),
                subtitle: Text(context.tr('modes.simulationHelp')),
                value: _m.presenceSimulation,
                onChanged: canEdit ? (v) => setState(() => _m = _m.copyWith(presenceSimulation: v)) : null,
              ),
              if (_m.presenceSimulation)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final Device d in lights)
                    FilterChip(
                      key: ValueKey('sim-${d.id}'),
                      label: Text(d.name),
                      selected: _m.simulationDevices.contains(d.id),
                      onSelected: canEdit
                          ? (v) => setState(() => _m = _m.copyWith(
                                simulationDevices: v ? [..._m.simulationDevices, d.id] : _m.simulationDevices.where((x) => x != d.id).toList(),
                              ))
                          : null,
                    ),
                ]),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.shield_outlined, size: 18, color: f.inkSoft),
                const SizedBox(width: 8),
                Expanded(child: Text(context.tr('modes.securityKeeps'), style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft, height: 1.4))),
              ]),
            ],
            const SizedBox(height: 16),
            if (canEdit)
              FilledButton(
                key: const ValueKey('vacation-save'),
                onPressed: _saving ? null : _save,
                child: Text(context.tr('common.save')),
              )
            else
              Text(context.tr('modes.managersOnly'), style: theme.textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}
