import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/backend.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../widgets/action_editor.dart';
import '../widgets/common.dart';
import '../widgets/device_controls.dart';

/// Automatisations : déclencheur (manuel, heure, état d'un appareil), conditions
/// (état, plage horaire), actions (commande ou scène). Exécutées localement par la
/// passerelle FlowIT Bridge quand c'est possible (§5.9).
class AutomationsScreen extends StatelessWidget {
  const AutomationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final list = state.automations;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: state.canManage
          ? FloatingActionButton.extended(
              heroTag: 'automation-add',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AutomationEditor())),
              icon: const Icon(Icons.add_rounded),
              label: Text(context.tr('automation.add')),
            )
          : null,
      body: list.isEmpty
          ? ListView(children: [
              EmptyState(icon: Icons.schedule_rounded, title: context.tr('automation.emptyTitle'), message: context.tr('automation.emptyHelp')),
            ])
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _AutomationCard(automation: list[i]),
            ),
    );
  }
}

class _AutomationCard extends StatelessWidget {
  const _AutomationCard({required this.automation});

  final Automation automation;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final a = automation;
    final f = context.flow;
    final theme = Theme.of(context);
    final type = a.trigger['type'];
    final (icon, color) = switch (type) {
      'manual' => (Icons.touch_app_rounded, f.brand),
      'device_state' => (Icons.sensors_rounded, f.violet),
      _ => (Icons.schedule_rounded, f.blue),
    };
    Widget line(IconData i, Color c, String text) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(i, size: 16, color: c)),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: f.inkSoft))),
          ]),
        );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 12, 4),
          child: Row(children: [
            IconBubble(icon: icon, color: color, size: 46, filled: a.enabled, glow: a.enabled),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(describeTrigger(context, state, a.trigger), style: theme.textTheme.bodyMedium?.copyWith(color: f.inkSoft)),
              ]),
            ),
            Switch(
              value: a.enabled,
              onChanged: state.canManage
                  ? (v) => state.run(() async {
                        await state.backend.saveAutomation(a.copyWith(enabled: v));
                        await state.refreshHome(silent: true);
                      })
                  : null,
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final c in a.conditions) line(Icons.filter_alt_rounded, f.warning, describeCondition(context, state, c)),
            for (final act in a.actions) line(Icons.arrow_forward_rounded, f.brand, describeAutomationAction(context, state, act)),
            if (a.lastRunAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(context.tr('automation.lastRun', {'when': relativeTime(context, a.lastRunAt)}), style: theme.textTheme.labelSmall?.copyWith(color: f.inkFaint)),
              ),
          ]),
        ),
        OverflowBar(alignment: MainAxisAlignment.end, children: [
          if (a.trigger['type'] == 'manual')
            TextButton.icon(
              onPressed: a.enabled ? () => runAutomationNow(context, a) : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(context.tr('scene.run')),
            ),
          if (state.canManage)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: f.inkSoft),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AutomationEditor(automation: a))),
              icon: const Icon(Icons.edit_rounded),
              label: Text(context.tr('common.edit')),
            ),
        ]),
      ]),
    );
  }
}

/// Déclenchement manuel : chaque action passe par le circuit de commande normal.
Future<void> runAutomationNow(BuildContext context, Automation a) async {
  final state = AppScope.read(context);
  for (final act in a.actions) {
    if (act['scene_id'] != null) {
      final s = state.sceneById(act['scene_id'] as String);
      if (s != null) await state.executeScene(s);
    } else {
      final d = state.devices[act['device_id']];
      if (d != null) await state.sendCommand(d, act['capability_key'] as String, act['value']);
    }
  }
}

const _weekdays = [1, 2, 3, 4, 5, 6, 7]; // ISO : 1 = lundi

String describeTrigger(BuildContext context, AppState state, Map<String, dynamic> t) {
  switch (t['type']) {
    case 'time':
      final days = ((t['days'] as List?) ?? const []).cast<num>().map((d) => d.toInt()).toList();
      final daysText = days.isEmpty || days.length == 7 ? context.tr('automation.everyDay') : days.map((d) => context.tr('day.short.$d')).join(', ');
      return context.tr('automation.trigger.timeAt', {'at': t['at'], 'days': daysText});
    case 'device_state':
      final d = state.devices[t['device_id']];
      final cap = d?.capability('${t['capability_key']}');
      return context.tr('automation.trigger.stateWhen', {
        'device': d?.name ?? '—',
        'cap': capabilityLabel(context, '${t['capability_key']}'),
        'op': context.tr('op.${t['op'] ?? 'eq'}'),
        'value': formatValue(context, cap, '${t['capability_key']}', t['value']),
      });
    default:
      return context.tr('automation.trigger.manual');
  }
}

String describeCondition(BuildContext context, AppState state, Map<String, dynamic> c) {
  if (c['type'] == 'time_range') return context.tr('automation.condition.between', {'from': c['from'], 'to': c['to']});
  final d = state.devices[c['device_id']];
  final cap = d?.capability('${c['capability_key']}');
  return context.tr('automation.condition.state', {
    'device': d?.name ?? '—',
    'cap': capabilityLabel(context, '${c['capability_key']}'),
    'op': context.tr('op.${c['op'] ?? 'eq'}'),
    'value': formatValue(context, cap, '${c['capability_key']}', c['value']),
  });
}

String describeAutomationAction(BuildContext context, AppState state, Map<String, dynamic> a) {
  if (a['scene_id'] != null) {
    return context.tr('automation.action.scene', {'name': state.sceneById(a['scene_id'] as String)?.name ?? '—'});
  }
  return describeAction(context, state, '${a['device_id']}', '${a['capability_key']}', a['value']);
}

/// Condition sur l'état d'un appareil (déclencheur ou condition).
class _StateRule {
  String? deviceId;
  String? capabilityKey;
  String op;
  dynamic value;

  _StateRule({this.deviceId, this.capabilityKey, this.op = 'eq', this.value});

  factory _StateRule.fromJson(Map<String, dynamic> j) =>
      _StateRule(deviceId: j['device_id'] as String?, capabilityKey: j['capability_key'] as String?, op: (j['op'] as String?) ?? 'eq', value: j['value']);

  Map<String, dynamic> toJson() => {'type': 'device_state', 'device_id': deviceId, 'capability_key': capabilityKey, 'op': op, 'value': value};

  bool get isComplete => deviceId != null && capabilityKey != null && value != null;
}

class _TimeRange {
  String from;
  String to;
  _TimeRange(this.from, this.to);
}

class AutomationEditor extends StatefulWidget {
  const AutomationEditor({super.key, this.automation});

  final Automation? automation;

  @override
  State<AutomationEditor> createState() => _AutomationEditorState();
}

class _AutomationEditorState extends State<AutomationEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.automation?.name);
  late String _type = (widget.automation?.trigger['type'] as String?) ?? 'time';
  late String _at = (widget.automation?.trigger['at'] as String?) ?? '07:00';
  late final Set<int> _days = {...((widget.automation?.trigger['days'] as List?) ?? _weekdays).cast<num>().map((e) => e.toInt())};
  late final _StateRule _triggerRule =
      widget.automation?.trigger['type'] == 'device_state' ? _StateRule.fromJson(widget.automation!.trigger) : _StateRule();
  late final List<Object> _conditions = [
    for (final c in widget.automation?.conditions ?? const <Map<String, dynamic>>[])
      if (c['type'] == 'time_range') _TimeRange('${c['from']}', '${c['to']}') else _StateRule.fromJson(c),
  ];
  late final List<Object> _actions = [
    for (final a in widget.automation?.actions ?? const <Map<String, dynamic>>[])
      if (a['scene_id'] != null) a['scene_id'] as String else EditableAction(deviceId: a['device_id'] as String?, capabilityKey: a['capability_key'] as String?, value: a['value']),
  ];
  bool _saving = false;

  Map<String, dynamic> _trigger() => switch (_type) {
        'time' => {'type': 'time', 'at': _at, 'days': (_days.toList()..sort())},
        'device_state' => _triggerRule.toJson(),
        _ => {'type': 'manual'},
      };

  Future<void> _save() async {
    final state = AppScope.read(context);
    String? problem;
    if (_name.text.trim().isEmpty) problem = 'validation.nameRequired';
    if (_type == 'time' && _days.isEmpty) problem = 'validation.daysRequired';
    if (_type == 'device_state' && !_triggerRule.isComplete) problem = 'validation.triggerIncomplete';
    if (_conditions.any((c) => c is _StateRule && !c.isComplete)) problem = 'validation.conditionsIncomplete';
    if (_actions.isEmpty || _actions.any((a) => a is EditableAction && !a.isComplete)) problem = 'validation.actionsIncomplete';
    if (problem != null) {
      state.notify(context.tr(problem), error: true);
      return;
    }
    setState(() => _saving = true);
    final isNew = widget.automation == null;
    final a = Automation(
      id: widget.automation?.id ?? newUuid(),
      homeId: state.home!.id,
      name: _name.text.trim(),
      enabled: widget.automation?.enabled ?? true,
      trigger: _trigger(),
      conditions: [
        for (final c in _conditions)
          if (c is _TimeRange) {'type': 'time_range', 'from': c.from, 'to': c.to} else (c as _StateRule).toJson(),
      ],
      actions: [
        for (final act in _actions)
          if (act is String) {'scene_id': act} else {'device_id': (act as EditableAction).deviceId, 'capability_key': act.capabilityKey, 'value': act.value},
      ],
    );
    final ok = await state.run(() => state.backend.saveAutomation(a, isNew: isNew), success: context.tr('common.saved'));
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      await state.refreshHome(silent: true);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _delete() async {
    final state = AppScope.read(context);
    final ok = await confirmDialog(context,
        title: context.tr('automation.deleteTitle', {'name': widget.automation!.name}), message: context.tr('common.irreversible'), destructive: true, confirmLabel: context.tr('common.delete'));
    if (!ok || !mounted) return;
    if (await state.run(() => state.backend.deleteAutomation(widget.automation!.id))) {
      await state.refreshHome(silent: true);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<String?> _pickTime(String current) async {
    final parts = current.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.tryParse(parts.first) ?? 7, minute: int.tryParse(parts.last) ?? 0),
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null) return null;
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(widget.automation == null ? 'automation.add' : 'automation.edit')),
        actions: [
          if (widget.automation != null) IconButton(tooltip: context.tr('common.delete'), onPressed: _delete, icon: const Icon(Icons.delete_outline)),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilledButton(onPressed: _saving ? null : _save, child: Text(context.tr('common.save'))),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            TextField(controller: _name, decoration: InputDecoration(labelText: context.tr('common.name'))),
            SectionHeader(context.tr('automation.when')),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'time', icon: const Icon(Icons.schedule), label: Text(context.tr('automation.type.time'))),
                ButtonSegment(value: 'device_state', icon: const Icon(Icons.sensors), label: Text(context.tr('automation.type.state'))),
                ButtonSegment(value: 'manual', icon: const Icon(Icons.touch_app_outlined), label: Text(context.tr('automation.type.manual'))),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 12),
            if (_type == 'time') ...[
              ListTile(
                leading: const Icon(Icons.access_time),
                title: Text(context.tr('automation.at')),
                trailing: Text(_at, style: Theme.of(context).textTheme.titleLarge),
                onTap: () async {
                  final t = await _pickTime(_at);
                  if (t != null) setState(() => _at = t);
                },
              ),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final d in _weekdays)
                  FilterChip(
                    label: Text(context.tr('day.short.$d')),
                    selected: _days.contains(d),
                    onSelected: (v) => setState(() => v ? _days.add(d) : _days.remove(d)),
                  ),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(context.tr('automation.timezone', {'tz': state.home?.timezone ?? ''}), style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
            if (_type == 'device_state') _StateRuleEditor(rule: _triggerRule, onChanged: () => setState(() {})),
            if (_type == 'manual') Text(context.tr('automation.manualHelp')),
            SectionHeader(
              context.tr('automation.conditions'),
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.add),
                tooltip: context.tr('automation.addCondition'),
                onSelected: (v) => setState(() => _conditions.add(v == 'time' ? _TimeRange('22:00', '06:00') : _StateRule())),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'time', child: Text(context.tr('automation.condition.timeRange'))),
                  PopupMenuItem(value: 'state', child: Text(context.tr('automation.condition.deviceState'))),
                ],
              ),
            ),
            if (_conditions.isEmpty) Text(context.tr('automation.noConditions')),
            for (var i = 0; i < _conditions.length; i++)
              Card(
                key: ObjectKey(_conditions[i]),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(children: [
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: IconButton(tooltip: context.tr('common.delete'), onPressed: () => setState(() => _conditions.removeAt(i)), icon: const Icon(Icons.delete_outline)),
                    ),
                    if (_conditions[i] is _TimeRange)
                      _timeRangeEditor(_conditions[i] as _TimeRange)
                    else
                      _StateRuleEditor(rule: _conditions[i] as _StateRule, onChanged: () => setState(() {})),
                  ]),
                ),
              ),
            SectionHeader(
              context.tr('automation.then'),
              trailing: PopupMenuButton<String>(
                icon: const Icon(Icons.add),
                tooltip: context.tr('scene.addAction'),
                onSelected: (v) => setState(() => _actions.add(v == 'device' ? EditableAction() : (state.scenes.firstOrNull?.id ?? ''))),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'device', child: Text(context.tr('automation.action.device'))),
                  if (state.scenes.isNotEmpty) PopupMenuItem(value: 'scene', child: Text(context.tr('automation.action.runScene'))),
                ],
              ),
            ),
            if (_actions.isEmpty) Text(context.tr('scene.noActions')),
            for (var i = 0; i < _actions.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _actions[i] is EditableAction
                    ? ActionEditorCard(
                        key: ObjectKey(_actions[i]),
                        action: _actions[i] as EditableAction,
                        onChanged: () => setState(() {}),
                        onRemove: () => setState(() => _actions.removeAt(i)),
                      )
                    : Card(
                        child: ListTile(
                          leading: const Icon(Icons.auto_awesome_outlined),
                          title: DropdownButton<String>(
                            isExpanded: true,
                            value: state.sceneById(_actions[i] as String) == null ? null : _actions[i] as String,
                            items: [for (final s in state.scenes) DropdownMenuItem(value: s.id, child: Text(s.name))],
                            onChanged: (v) => setState(() => _actions[i] = v ?? ''),
                          ),
                          trailing: IconButton(tooltip: context.tr('common.delete'), onPressed: () => setState(() => _actions.removeAt(i)), icon: const Icon(Icons.delete_outline)),
                        ),
                      ),
              ),
            const SizedBox(height: 16),
            Text(context.tr('automation.localHelp'), style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }

  Widget _timeRangeEditor(_TimeRange r) => Row(children: [
        const Icon(Icons.nightlight_outlined),
        const SizedBox(width: 12),
        Text(context.tr('automation.between')),
        TextButton(
          onPressed: () async {
            final t = await _pickTime(r.from);
            if (t != null) setState(() => r.from = t);
          },
          child: Text(r.from),
        ),
        Text(context.tr('automation.and')),
        TextButton(
          onPressed: () async {
            final t = await _pickTime(r.to);
            if (t != null) setState(() => r.to = t);
          },
          child: Text(r.to),
        ),
      ]);
}

class _StateRuleEditor extends StatelessWidget {
  const _StateRuleEditor({required this.rule, required this.onChanged});

  final _StateRule rule;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final devices = state.devices.values.where((d) => d.capabilities.isNotEmpty).toList()..sort((a, b) => a.name.compareTo(b.name));
    final device = state.devices[rule.deviceId];
    final cap = device?.capability(rule.capabilityKey ?? '');
    final numeric = cap != null && (cap.type == CapabilityType.number || (cap.type == CapabilityType.sensor && rule.value is! bool && cap.metadata['kind'] != 'binary'));
    final binary = cap != null && (cap.type == CapabilityType.boolean || cap.metadata['kind'] == 'binary');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DropdownButtonFormField<String>(
        initialValue: device == null ? null : rule.deviceId,
        isExpanded: true,
        decoration: InputDecoration(labelText: context.tr('action.device')),
        items: [for (final d in devices) DropdownMenuItem(value: d.id, child: Text(d.name, overflow: TextOverflow.ellipsis))],
        onChanged: (id) {
          rule.deviceId = id;
          rule.capabilityKey = state.devices[id]?.capabilities.firstOrNull?.key;
          rule.value = null;
          onChanged();
        },
      ),
      if (device != null) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('rule-cap-${rule.deviceId}'),
          initialValue: cap?.key,
          isExpanded: true,
          decoration: InputDecoration(labelText: context.tr('action.capability')),
          items: [for (final c in device.capabilities) DropdownMenuItem(value: c.key, child: Text(capabilityLabel(context, c.key)))],
          onChanged: (k) {
            rule.capabilityKey = k;
            rule.value = null;
            onChanged();
          },
        ),
      ],
      if (cap != null) ...[
        const SizedBox(height: 12),
        if (numeric)
          Row(children: [
            DropdownButton<String>(
              value: rule.op,
              items: [for (final op in const ['eq', 'ne', 'gt', 'lt']) DropdownMenuItem(value: op, child: Text(context.tr('op.$op')))],
              onChanged: (v) {
                rule.op = v ?? 'eq';
                onChanged();
              },
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                initialValue: rule.value?.toString(),
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(labelText: context.tr('action.value'), suffixText: cap.unit),
                onChanged: (v) {
                  rule.value = num.tryParse(v.replaceAll(',', '.'));
                  onChanged();
                },
              ),
            ),
          ])
        else if (binary)
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(formatValue(context, cap, cap.key, true))),
              ButtonSegment(value: false, label: Text(formatValue(context, cap, cap.key, false))),
            ],
            emptySelectionAllowed: true,
            selected: rule.value is bool ? {rule.value as bool} : const {},
            onSelectionChanged: (s) {
              rule.op = 'eq';
              rule.value = s.firstOrNull;
              onChanged();
            },
          )
        else
          ValueEditor(cap: cap, value: rule.value, onChanged: (v) {
            rule.op = 'eq';
            rule.value = v;
            onChanged();
          }),
      ],
    ]);
  }
}
