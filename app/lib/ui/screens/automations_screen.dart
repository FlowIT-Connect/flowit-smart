import 'package:flutter/material.dart';

import '../../core/home_modes.dart';
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
      'weather' => (Icons.air_rounded, f.blue),
      'sun' => (Icons.wb_twilight_rounded, f.warning),
      'mode' => (Icons.flight_takeoff_rounded, f.success),
      _ => (Icons.schedule_rounded, f.blue),
    };
    final follow = a.followUp;
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
                Row(children: [
                  Flexible(child: Text(a.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                  if (a.priority == 'security') ...[
                    const SizedBox(width: 6),
                    Tooltip(message: context.tr('automation.security'), child: Icon(Icons.shield_rounded, size: 16, color: f.danger)),
                  ],
                ]),
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
            for (final c in a.exceptions) line(Icons.block_rounded, f.danger, context.tr('automation.unlessLine', {'what': describeCondition(context, state, c)})),
            for (final act in a.actions) line(Icons.arrow_forward_rounded, f.brand, describeAutomationAction(context, state, act)),
            if (follow != null)
              line(Icons.timer_outlined, f.violet, context.tr('automation.followLine', {
                'minutes': '${follow['after_minutes'] ?? 0}',
                'what': [for (final act in (follow['actions'] as List? ?? const [])) describeAutomationAction(context, state, Map<String, dynamic>.from(act as Map))].join(', '),
              })),
            if (a.lastRunAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(context.tr('automation.lastRun', {'when': relativeTime(context, a.lastRunAt)}), style: theme.textTheme.labelSmall?.copyWith(color: f.inkSoft)),
              ),
          ]),
        ),
        OverflowBar(alignment: MainAxisAlignment.end, children: [
          TextButton.icon(
            key: ValueKey('automation-history-${a.id}'),
            style: TextButton.styleFrom(foregroundColor: f.inkSoft),
            onPressed: () => showAutomationHistory(context, a),
            icon: const Icon(Icons.history_rounded),
            label: Text(context.tr('automation.history')),
          ),
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
    case 'weather':
      return context.tr('automation.trigger.weather', {
        'metric': context.tr('weatherMetric.${t['metric']}'),
        'op': context.tr('op.${t['op'] ?? 'gt'}'),
        'value': '${t['value']} ${weatherUnit('${t['metric']}')}',
      }) +
          ((t['for_minutes'] as num? ?? 0) > 0 ? context.tr('automation.trigger.forMinutes', {'minutes': '${t['for_minutes']}'}) : '');
    case 'mode':
      return context.tr(t['event'] == 'end' ? 'automation.trigger.modeEnd' : 'automation.trigger.modeStart', {'mode': context.tr('modes.${t['mode']}')});
    case 'sun':
      final offset = (t['offset_minutes'] as num?)?.toInt() ?? 0;
      return context.tr('automation.trigger.sun.${t['event'] == 'sunrise' ? 'sunrise' : 'sunset'}') +
          (offset == 0 ? '' : context.tr(offset < 0 ? 'automation.trigger.before' : 'automation.trigger.after', {'minutes': '${offset.abs()}'}));
    default:
      return context.tr('automation.trigger.manual');
  }
}

String weatherUnit(String metric) => switch (metric) {
      'precipitation' => 'mm',
      'temperature' => '°C',
      _ => 'km/h',
    };

String describeCondition(BuildContext context, AppState state, Map<String, dynamic> c) {
  if (c['type'] == 'time_range') return context.tr('automation.condition.between', {'from': c['from'], 'to': c['to']});
  if (c['type'] == 'weather') {
    return context.tr('automation.condition.weather', {
      'metric': context.tr('weatherMetric.${c['metric']}'),
      'op': context.tr('op.${c['op'] ?? 'gt'}'),
      'value': '${c['value']} ${weatherUnit('${c['metric']}')}',
    });
  }
  if (c['type'] == 'mode') return context.tr('automation.condition.mode', {'mode': context.tr('modes.${c['mode']}')});
  if (c['type'] == 'sun') return context.tr(c['is'] == 'day' ? 'automation.condition.day' : 'automation.condition.night');
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

/// Condition météo (vent, rafales, pluie, température extérieure).
class _WeatherRule {
  String metric;
  String op;
  num? value;
  _WeatherRule({this.metric = 'wind_speed', this.op = 'gt', this.value = 80});

  Map<String, dynamic> toJson() => {'type': 'weather', 'metric': metric, 'op': op, 'value': value};
}

/// Condition « mode actif » (été, hiver, vacances).
class _ModeRule {
  String mode;
  _ModeRule({this.mode = 'vacation'});
}

const homeModeKeys = ['summer', 'winter', 'vacation'];

/// Condition « il fait nuit / jour ».
class _SunRule {
  bool night;
  _SunRule({this.night = true});
}

const weatherMetrics = ['wind_speed', 'wind_gust', 'precipitation', 'temperature'];

Object _ruleFromJson(Map<String, dynamic> c) => switch (c['type']) {
      'time_range' => _TimeRange('${c['from']}', '${c['to']}'),
      'weather' => _WeatherRule(metric: '${c['metric'] ?? 'wind_speed'}', op: '${c['op'] ?? 'gt'}', value: c['value'] as num?),
      'sun' => _SunRule(night: c['is'] != 'day'),
      'mode' => _ModeRule(mode: '${c['mode'] ?? 'vacation'}'),
      _ => _StateRule.fromJson(c),
    };

Map<String, dynamic> _ruleToJson(Object r) => switch (r) {
      _TimeRange t => {'type': 'time_range', 'from': t.from, 'to': t.to},
      _WeatherRule w => w.toJson(),
      _SunRule s => {'type': 'sun', 'is': s.night ? 'night' : 'day'},
      _ModeRule m => {'type': 'mode', 'mode': m.mode},
      _ => (r as _StateRule).toJson(),
    };

bool _ruleComplete(Object r) => switch (r) {
      _StateRule s => s.isComplete,
      _WeatherRule w => w.value != null,
      _ => true,
    };

EditableAction _editable(Map<String, dynamic> a) =>
    EditableAction(deviceId: a['device_id'] as String?, capabilityKey: a['capability_key'] as String?, value: a['value']);

class AutomationEditor extends StatefulWidget {
  const AutomationEditor({super.key, this.automation, this.template, this.triggerDeviceId});

  final Automation? automation;

  /// Nouvelle automatisation pré-remplie depuis un modèle (ex. 'presence' depuis la fiche
  /// d'un détecteur), avec l'appareil déclencheur déjà choisi.
  final String? template;
  final String? triggerDeviceId;

  @override
  State<AutomationEditor> createState() => _AutomationEditorState();
}

class _AutomationEditorState extends State<AutomationEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.automation?.name);
  late String _type = (widget.automation?.trigger['type'] as String?) ?? 'time';
  late String _at = (widget.automation?.trigger['at'] as String?) ?? '07:00';
  late final Set<int> _days = {...((widget.automation?.trigger['days'] as List?) ?? _weekdays).cast<num>().map((e) => e.toInt())};
  late _StateRule _triggerRule =
      widget.automation?.trigger['type'] == 'device_state' ? _StateRule.fromJson(widget.automation!.trigger) : _StateRule();
  late _WeatherRule _weather = widget.automation?.trigger['type'] == 'weather'
      ? _ruleFromJson({...widget.automation!.trigger, 'type': 'weather'}) as _WeatherRule
      : _WeatherRule();
  late int _weatherFor = (widget.automation?.trigger['for_minutes'] as num?)?.toInt() ?? 2;
  late String _sunEvent = (widget.automation?.trigger['event'] as String?) ?? 'sunset';
  late int _sunOffset = (widget.automation?.trigger['offset_minutes'] as num?)?.toInt() ?? 0;
  late String _mode = (widget.automation?.trigger['mode'] as String?) ?? 'vacation';
  late String _modeEvent = (widget.automation?.trigger['event'] as String?) == 'end' ? 'end' : 'start';
  late List<Object> _conditions = [for (final c in widget.automation?.conditions ?? const <Map<String, dynamic>>[]) _ruleFromJson(c)];
  late List<Object> _exceptions = [for (final c in widget.automation?.exceptions ?? const <Map<String, dynamic>>[]) _ruleFromJson(c)];
  late List<Object> _actions = [
    for (final a in widget.automation?.actions ?? const <Map<String, dynamic>>[])
      if (a['scene_id'] != null) a['scene_id'] as String else _editable(a),
  ];
  late bool _follow = widget.automation?.followUp != null;
  late int _followAfter = (widget.automation?.followUp?['after_minutes'] as num?)?.toInt() ?? 5;
  late bool _followRestart = widget.automation?.followUp?['restart_on_trigger'] as bool? ?? true;
  late List<EditableAction> _followActions = [
    for (final a in (widget.automation?.followUp?['actions'] as List?) ?? const []) _editable(Map<String, dynamic>.from(a as Map)),
  ];
  late List<Object> _followConditions = [
    for (final c in (widget.automation?.followUp?['conditions'] as List?) ?? const []) _ruleFromJson(Map<String, dynamic>.from(c as Map)),
  ];
  late bool _security = widget.automation?.priority == 'security';
  bool _saving = false;

  Map<String, dynamic> _trigger() => switch (_type) {
        'time' => {'type': 'time', 'at': _at, 'days': (_days.toList()..sort())},
        'device_state' => _triggerRule.toJson(),
        'weather' => {..._weather.toJson(), 'for_minutes': _weatherFor},
        'sun' => {'type': 'sun', 'event': _sunEvent, 'offset_minutes': _sunOffset},
        'mode' => {'type': 'mode', 'mode': _mode, 'event': _modeEvent},
        _ => {'type': 'manual'},
      };

  @override
  void initState() {
    super.initState();
    final t = widget.template;
    if (widget.automation == null && t != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyTemplate(t);
        if (widget.triggerDeviceId != null) setState(() => _triggerRule.deviceId = widget.triggerDeviceId);
      });
    }
  }

  /// Modèles prêts à l'emploi du cahier des charges ; il reste à choisir les appareils.
  void _applyTemplate(String t) {
    setState(() {
      switch (t) {
        case 'wind':
          _name.text = context.tr('automation.template.wind');
          _type = 'weather';
          _weather = _WeatherRule(metric: 'wind_speed', op: 'gt', value: 80);
          _weatherFor = 2;
          _conditions = [];
          _exceptions = [];
          _actions = [EditableAction(capabilityKey: 'cover_position', value: 0)];
          _follow = true;
          _followAfter = 30;
          _followRestart = false;
          _followActions = [EditableAction(capabilityKey: 'cover_position', value: 100)];
          _followConditions = [_WeatherRule(metric: 'wind_speed', op: 'lt', value: 50)];
          _security = true;
        case 'shutters':
          _name.text = context.tr('automation.template.shutters');
          _type = 'device_state';
          _triggerRule = _StateRule(capabilityKey: 'cover_position', op: 'eq', value: 0);
          _conditions = [_TimeRange('12:00', '19:00')];
          _exceptions = [];
          _actions = [EditableAction(capabilityKey: 'switch', value: true)];
          _follow = false;
          _security = false;
        case 'presence':
          _name.text = context.tr('automation.template.presence');
          _type = 'device_state';
          _triggerRule = _StateRule(capabilityKey: 'motion', op: 'eq', value: true);
          _conditions = [_SunRule(night: true)];
          _exceptions = [];
          _actions = [EditableAction(capabilityKey: 'switch', value: true)];
          _follow = true;
          _followAfter = 5;
          _followRestart = true;
          _followActions = [EditableAction(capabilityKey: 'switch', value: false)];
          _followConditions = [];
          _security = false;
      }
    });
  }

  Future<void> _save() async {
    final state = AppScope.read(context);
    String? problem;
    if (_name.text.trim().isEmpty) problem = 'validation.nameRequired';
    if (_type == 'time' && _days.isEmpty) problem = 'validation.daysRequired';
    if (_type == 'device_state' && !_triggerRule.isComplete) problem = 'validation.triggerIncomplete';
    if (_type == 'weather' && _weather.value == null) problem = 'validation.triggerIncomplete';
    if ([..._conditions, ..._exceptions, if (_follow) ..._followConditions].any((c) => !_ruleComplete(c))) problem = 'validation.conditionsIncomplete';
    if (_actions.isEmpty || _actions.any((a) => a is EditableAction && !a.isComplete)) problem = 'validation.actionsIncomplete';
    if (_follow && (_followActions.isEmpty || _followActions.any((a) => !a.isComplete))) problem = 'validation.actionsIncomplete';
    if (problem != null) {
      state.notify(context.tr(problem), error: true);
      return;
    }
    setState(() => _saving = true);
    final isNew = widget.automation == null;
    Map<String, dynamic> act(EditableAction a) => {'device_id': a.deviceId, 'capability_key': a.capabilityKey, 'value': a.value};
    final a = Automation(
      id: widget.automation?.id ?? newUuid(),
      homeId: state.home!.id,
      name: _name.text.trim(),
      enabled: widget.automation?.enabled ?? true,
      trigger: _trigger(),
      conditions: [for (final c in _conditions) _ruleToJson(c)],
      exceptions: [for (final c in _exceptions) _ruleToJson(c)],
      actions: [
        for (final x in _actions)
          if (x is String) {'scene_id': x} else act(x as EditableAction),
      ],
      followUp: _follow
          ? {
              'after_minutes': _followAfter,
              'restart_on_trigger': _followRestart,
              'actions': [for (final x in _followActions) act(x)],
              'conditions': [for (final c in _followConditions) _ruleToJson(c)],
            }
          : null,
      priority: _security ? 'security' : 'normal',
      lastRunAt: widget.automation?.lastRunAt,
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

  /// Liste de conditions modifiable (SI, SAUF SI, conditions du PUIS).
  List<Widget> _ruleSection(String id, String titleKey, String emptyKey, List<Object> list, {String? hintKey}) => [
        SectionHeader(
          context.tr(titleKey),
          trailing: PopupMenuButton<String>(
            key: ValueKey('add-$id'),
            icon: const Icon(Icons.add),
            tooltip: context.tr('automation.addCondition'),
            onSelected: (v) => setState(() => list.add(switch (v) {
                  'time' => _TimeRange('22:00', '06:00'),
                  'weather' => _WeatherRule(),
                  'sun' => _SunRule(),
                  'mode' => _ModeRule(),
                  _ => _StateRule(),
                })),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'state', child: Text(context.tr('automation.condition.deviceState'))),
              PopupMenuItem(value: 'time', child: Text(context.tr('automation.condition.timeRange'))),
              PopupMenuItem(value: 'weather', child: Text(context.tr('automation.condition.weatherMenu'))),
              PopupMenuItem(value: 'sun', child: Text(context.tr('automation.condition.sunMenu'))),
              PopupMenuItem(value: 'mode', child: Text(context.tr('automation.condition.modeMenu'))),
            ],
          ),
        ),
        if (hintKey != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(context.tr(hintKey), style: Theme.of(context).textTheme.bodySmall)),
        if (list.isEmpty) Text(context.tr(emptyKey)),
        for (var i = 0; i < list.length; i++)
          Card(
            key: ObjectKey(list[i]),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(children: [
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: IconButton(tooltip: context.tr('common.delete'), onPressed: () => setState(() => list.removeAt(i)), icon: const Icon(Icons.delete_outline)),
                ),
                switch (list[i]) {
                  _TimeRange r => _timeRangeEditor(r),
                  _WeatherRule w => _weatherEditor(w),
                  _SunRule r => SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(value: true, icon: const Icon(Icons.nightlight_round), label: Text(context.tr('automation.night'))),
                        ButtonSegment(value: false, icon: const Icon(Icons.wb_sunny_outlined), label: Text(context.tr('automation.day'))),
                      ],
                      selected: {r.night},
                      onSelectionChanged: (v) => setState(() => r.night = v.first),
                    ),
                  _ModeRule m => _modeChoice(m.mode, (v) => setState(() => m.mode = v)),
                  _ => _StateRuleEditor(rule: list[i] as _StateRule, onChanged: () => setState(() {})),
                },
              ]),
            ),
          ),
      ];

  Widget _weatherEditor(_WeatherRule w, {Key? valueKey}) => Row(children: [
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<String>(
            initialValue: w.metric,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.tr('automation.metric')),
            items: [for (final m in weatherMetrics) DropdownMenuItem(value: m, child: Text(context.tr('weatherMetric.$m')))],
            onChanged: (v) => setState(() => w.metric = v ?? 'wind_speed'),
          ),
        ),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: w.op,
          items: [for (final op in const ['gt', 'lt']) DropdownMenuItem(value: op, child: Text(context.tr('op.$op')))],
          onChanged: (v) => setState(() => w.op = v ?? 'gt'),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextFormField(
            key: valueKey,
            initialValue: w.value?.toString(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: InputDecoration(labelText: context.tr('action.value'), suffixText: weatherUnit(w.metric)),
            onChanged: (v) => setState(() => w.value = num.tryParse(v.replaceAll(',', '.'))),
          ),
        ),
      ]);

  Widget _modeChoice(String mode, ValueChanged<String> onChanged) => SegmentedButton<String>(
        segments: [
          for (final m in homeModeKeys) ButtonSegment(value: m, icon: Icon(modeIcons[m], size: 18), label: Text(context.tr('modes.$m'))),
        ],
        selected: {mode},
        onSelectionChanged: (v) => onChanged(v.first),
      );

  Widget _minutesField(String labelKey, int value, ValueChanged<int> onChanged, {Key? key, bool signed = false}) => TextFormField(
        key: key,
        initialValue: '$value',
        keyboardType: TextInputType.numberWithOptions(signed: signed),
        decoration: InputDecoration(labelText: context.tr(labelKey), suffixText: 'min'),
        onChanged: (v) {
          final n = int.tryParse(v.trim());
          if (n != null) onChanged(n);
        },
      );

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
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
            if (widget.automation == null) ...[
              Text(context.tr('automation.templates'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (t, icon) in const [('wind', Icons.air_rounded), ('shutters', Icons.blinds_closed_rounded), ('presence', Icons.directions_walk_rounded)])
                  ActionChip(
                    key: ValueKey('template-$t'),
                    avatar: Icon(icon, size: 18),
                    label: Text(context.tr('automation.template.$t')),
                    onPressed: () => _applyTemplate(t),
                  ),
              ]),
              const SizedBox(height: 16),
            ],
            TextField(controller: _name, decoration: InputDecoration(labelText: context.tr('common.name'))),
            SectionHeader(context.tr('automation.when')),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (t, icon) in const [
                ('time', Icons.schedule),
                ('device_state', Icons.sensors),
                ('weather', Icons.air_rounded),
                ('sun', Icons.wb_twilight_rounded),
                ('mode', Icons.flight_takeoff_rounded),
                ('manual', Icons.touch_app_outlined),
              ])
                ChoiceChip(
                  key: ValueKey('trigger-$t'),
                  avatar: Icon(icon, size: 18),
                  label: Text(context.tr(t == 'device_state' ? 'automation.type.state' : 'automation.type.$t')),
                  selected: _type == t,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _type = t),
                ),
            ]),
            const SizedBox(height: 12),
            if (_type == 'time') ...[
              ListTile(
                leading: const Icon(Icons.access_time),
                title: Text(context.tr('automation.at')),
                trailing: Text(_at, style: theme.textTheme.titleLarge),
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
                child: Text(context.tr('automation.timezone', {'tz': state.home?.timezone ?? ''}), style: theme.textTheme.bodySmall),
              ),
            ],
            if (_type == 'device_state') _StateRuleEditor(key: ObjectKey(_triggerRule), rule: _triggerRule, onChanged: () => setState(() {})),
            if (_type == 'weather') ...[
              _weatherEditor(_weather, valueKey: ObjectKey(_weather)),
              const SizedBox(height: 12),
              _minutesField('automation.confirmDelay', _weatherFor, (v) => _weatherFor = v.clamp(0, 120), key: ValueKey('weather-for-$_weatherFor-${identityHashCode(_weather)}')),
              const SizedBox(height: 8),
              Text(
                context.tr(state.home?.hasLocation ?? false ? 'automation.weatherHelp' : 'automation.weatherNoLocation', {'place': state.home?.locationName ?? state.weatherPlace.label}),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_type == 'sun') ...[
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'sunrise', icon: const Icon(Icons.wb_sunny_outlined), label: Text(context.tr('automation.sunrise'))),
                  ButtonSegment(value: 'sunset', icon: const Icon(Icons.nights_stay_outlined), label: Text(context.tr('automation.sunset'))),
                ],
                selected: {_sunEvent},
                onSelectionChanged: (v) => setState(() => _sunEvent = v.first),
              ),
              const SizedBox(height: 12),
              _minutesField('automation.sunOffset', _sunOffset, (v) => _sunOffset = v.clamp(-240, 240), signed: true),
            ],
            if (_type == 'mode') ...[
              _modeChoice(_mode, (v) => setState(() => _mode = v)),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'start', label: Text(context.tr('automation.modeStart'))),
                  ButtonSegment(value: 'end', label: Text(context.tr('automation.modeEnd'))),
                ],
                selected: {_modeEvent},
                onSelectionChanged: (v) => setState(() => _modeEvent = v.first),
              ),
            ],
            if (_type == 'manual') Text(context.tr('automation.manualHelp')),

            ..._ruleSection('condition', 'automation.conditions', 'automation.noConditions', _conditions),
            ..._ruleSection('exception', 'automation.unless', 'automation.noExceptions', _exceptions, hintKey: 'automation.unlessHelp'),

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

            // ------------------------------------------------------------ PUIS
            SectionHeader(context.tr('automation.followUp')),
            SwitchListTile(
              key: const ValueKey('follow-switch'),
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr('automation.followEnable')),
              subtitle: Text(context.tr('automation.followHelp')),
              value: _follow,
              onChanged: (v) => setState(() {
                _follow = v;
                if (v && _followActions.isEmpty) _followActions.add(EditableAction());
              }),
            ),
            if (_follow) ...[
              _minutesField('automation.followAfter', _followAfter, (v) => _followAfter = v.clamp(0, 1440), key: ValueKey('follow-after-$_followAfter-${_followActions.length}')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('automation.followRestart')),
                value: _followRestart,
                onChanged: (v) => setState(() => _followRestart = v),
              ),
              for (var i = 0; i < _followActions.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ActionEditorCard(
                    key: ObjectKey(_followActions[i]),
                    action: _followActions[i],
                    onChanged: () => setState(() {}),
                    onRemove: () => setState(() => _followActions.removeAt(i)),
                  ),
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(() => _followActions.add(EditableAction())),
                  icon: const Icon(Icons.add),
                  label: Text(context.tr('automation.action.device')),
                ),
              ),
              ..._ruleSection('follow-condition', 'automation.followConditions', 'automation.noFollowConditions', _followConditions),
            ],

            const SizedBox(height: 8),
            SwitchListTile(
              key: const ValueKey('security-switch'),
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.shield_outlined),
              title: Text(context.tr('automation.security')),
              subtitle: Text(context.tr('automation.securityHelp')),
              value: _security,
              onChanged: (v) => setState(() => _security = v),
            ),
            const SizedBox(height: 16),
            Text(context.tr('automation.localHelp'), style: theme.textTheme.bodySmall),
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
  const _StateRuleEditor({super.key, required this.rule, required this.onChanged});

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
          final keep = state.devices[id]?.capability(rule.capabilityKey ?? '') != null;
          if (!keep) {
            rule.capabilityKey = state.devices[id]?.capabilities.firstOrNull?.key;
            rule.value = null;
          }
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

/// Historique d'exécution d'une automatisation (écrit par la passerelle).
Future<void> showAutomationHistory(BuildContext context, Automation a) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AutomationHistory(automation: a),
    );

class _AutomationHistory extends StatelessWidget {
  const _AutomationHistory({required this.automation});

  final Automation automation;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final theme = Theme.of(context);
    final f = context.flow;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
        child: FutureBuilder<List<AutomationRun>>(
          future: state.automationRuns(automationId: automation.id),
          builder: (context, snap) {
            final runs = snap.data;
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(context.tr('automation.historyOf', {'name': automation.name}), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ),
              if (runs == null)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (runs.isEmpty)
                Padding(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), child: Text(context.tr('automation.historyEmpty')))
              else
                Flexible(
                  child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
                    for (final r in runs)
                      ListTile(
                        leading: Icon(
                          switch (r.status) {
                            'success' => Icons.check_circle_rounded,
                            'partial' => Icons.error_outline_rounded,
                            'skipped' => Icons.block_rounded,
                            _ => Icons.cancel_rounded,
                          },
                          color: switch (r.status) {
                            'success' => f.success,
                            'skipped' => f.inkSoft,
                            _ => f.danger,
                          },
                        ),
                        title: Text('${context.tr('automation.run.${r.status}')}${r.phase == 'follow_up' ? ' · ${context.tr('automation.followUp')}' : ''}'),
                        subtitle: Text([
                          relativeTime(context, r.createdAt),
                          if (r.details['total'] is num) context.tr('automation.runActions', {'ok': '${r.details['actions'] ?? 0}', 'total': '${r.details['total']}'}),
                          if (r.details['weather'] is Map && (r.details['weather'] as Map)['wind_speed'] is num)
                            context.tr('notif.body.wind', {'wind': '${((r.details['weather'] as Map)['wind_speed'] as num).round()}'}),
                          if (r.status == 'skipped' && r.reason.isNotEmpty) r.reason,
                        ].join(' · ')),
                      ),
                  ]),
                ),
            ]);
          },
        ),
      ),
    );
  }
}
