import 'package:flutter/material.dart';

import '../../core/icons.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/backend.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../widgets/action_editor.dart';
import '../widgets/common.dart';
import '../widgets/device_controls.dart';

/// Scènes : exécution, activation, édition, historique des exécutions (§5.9).
class ScenesScreen extends StatelessWidget {
  const ScenesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final scenes = state.scenes;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: state.canManage
          ? FloatingActionButton.extended(
              heroTag: 'scene-add',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SceneEditor())),
              icon: const Icon(Icons.add_rounded),
              label: Text(context.tr('scene.add')),
            )
          : null,
      body: scenes.isEmpty
          ? ListView(children: [
              EmptyState(icon: Icons.auto_awesome_rounded, title: context.tr('scene.emptyTitle'), message: context.tr('scene.emptyHelp')),
            ])
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
              children: [
                for (final s in scenes) Padding(padding: const EdgeInsets.only(bottom: 12), child: _SceneCard(scene: s)),
                if (state.sceneRuns.isNotEmpty) ...[
                  SectionHeader(context.tr('scene.history')),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(children: [for (final r in state.sceneRuns.take(15)) _RunTile(run: r)]),
                  ),
                ],
              ],
            ),
    );
  }
}

class _SceneCard extends StatelessWidget {
  const _SceneCard({required this.scene});

  final Scene scene;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = scene;
    final running = state.sceneRuns.any((r) => r.sceneId == s.id && r.finishedAt == null);
    final f = context.flow;
    final theme = Theme.of(context);
    final colors = sceneGradient(context, s.icon);
    final canRun = !running && s.enabled && s.actions.isNotEmpty;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(children: [
            Opacity(
              opacity: s.enabled ? 1 : .45,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(color: colors.last.withValues(alpha: .35), blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: Icon(sceneIcon(s.icon), color: Colors.white, size: 28),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  [
                    context.tr('scene.actionCount', {'n': s.actions.length}),
                    if (!s.enabled) context.tr('common.disabled'),
                    if (s.failurePolicy == FailurePolicy.stop) context.tr('scene.policy.stop'),
                  ].join(' · '),
                  style: theme.textTheme.bodyMedium?.copyWith(color: f.inkSoft),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colors.first,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onPressed: canRun ? () => state.executeScene(s) : null,
              icon: running
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(context.tr(running ? 'scene.running' : 'scene.run')),
            ),
          ]),
        ),
        if (state.canManage) ...[
          Divider(height: 1, color: f.line),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: OverflowBar(alignment: MainAxisAlignment.end, children: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: f.inkSoft),
                onPressed: () => state.run(() async {
                  await state.backend.saveScene(s.copyWith(enabled: !s.enabled));
                  await state.refreshHome(silent: true);
                }),
                icon: Icon(s.enabled ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded),
                label: Text(context.tr(s.enabled ? 'common.disable' : 'common.enable')),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: f.inkSoft),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SceneEditor(scene: s))),
                icon: const Icon(Icons.edit_rounded),
                label: Text(context.tr('common.edit')),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _RunTile extends StatelessWidget {
  const _RunTile({required this.run});

  final SceneRun run;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final f = context.flow;
    final scene = state.sceneById(run.sceneId);
    final ok = run.results.where((r) => r['status'] == 'confirmed').length;
    final (icon, color) = switch (run.status) {
      'success' => (Icons.check_circle_rounded, f.success),
      'partial' => (Icons.warning_rounded, f.warning),
      'failed' => (Icons.error_rounded, f.danger),
      _ => (Icons.hourglass_top_rounded, f.inkFaint),
    };
    return ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      leading: TileIcon(icon, color: color),
      title: Text(scene?.name ?? context.tr('scene.deleted')),
      subtitle: Text([
        '${MaterialLocalizations.of(context).formatShortDate(run.startedAt)} ${timeOfDay(context, run.startedAt)}',
        context.tr('run.${run.status}'),
        if (run.results.isNotEmpty) '$ok/${run.results.length}',
        if (run.automationId != null) context.tr('run.byAutomation'),
      ].join(' · ')),
      children: [
        for (final r in run.results)
          ListTile(
            dense: true,
            leading: Icon(r['status'] == 'confirmed' ? Icons.check_rounded : Icons.close_rounded, color: r['status'] == 'confirmed' ? f.success : f.danger),
            title: Text('${state.devices[r['device_id']]?.name ?? '—'} · ${capabilityLabel(context, '${r['capability_key']}')}'),
            subtitle: Text([context.tr('command.status.${r['status']}'), if (r['error'] != null) '${r['error']}'].join(' — ')),
          ),
      ],
    );
  }
}

/// Création / modification d'une scène.
class SceneEditor extends StatefulWidget {
  const SceneEditor({super.key, this.scene});

  final Scene? scene;

  @override
  State<SceneEditor> createState() => _SceneEditorState();
}

class _SceneEditorState extends State<SceneEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.scene?.name);
  late String _icon = widget.scene?.icon ?? 'auto';
  late FailurePolicy _policy = widget.scene?.failurePolicy ?? FailurePolicy.continueOnError;
  late final List<EditableAction> _actions = [
    for (final a in widget.scene?.actions ?? const <SceneAction>[])
      EditableAction(deviceId: a.deviceId, capabilityKey: a.capabilityKey, value: a.value, delayMs: a.delayMs),
  ];
  bool _saving = false;

  Future<void> _save() async {
    final state = AppScope.read(context);
    if (_name.text.trim().isEmpty) {
      state.notify(context.tr('validation.nameRequired'), error: true);
      return;
    }
    if (_actions.isEmpty || _actions.any((a) => !a.isComplete)) {
      state.notify(context.tr('validation.actionsIncomplete'), error: true);
      return;
    }
    setState(() => _saving = true);
    final isNew = widget.scene == null;
    final scene = Scene(
      id: widget.scene?.id ?? newUuid(),
      homeId: state.home!.id,
      name: _name.text.trim(),
      icon: _icon,
      enabled: widget.scene?.enabled ?? true,
      failurePolicy: _policy,
      actions: [
        for (final a in _actions) SceneAction(deviceId: a.deviceId!, capabilityKey: a.capabilityKey!, value: a.value, delayMs: a.delayMs),
      ],
    );
    final ok = await state.run(() => state.backend.saveScene(scene, isNew: isNew), success: context.tr('common.saved'));
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
        title: context.tr('scene.deleteTitle', {'name': widget.scene!.name}), message: context.tr('common.irreversible'), destructive: true, confirmLabel: context.tr('common.delete'));
    if (!ok || !mounted) return;
    if (await state.run(() => state.backend.deleteScene(widget.scene!.id))) {
      await state.refreshHome(silent: true);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(widget.scene == null ? 'scene.add' : 'scene.edit')),
        actions: [
          if (widget.scene != null) IconButton(tooltip: context.tr('common.delete'), onPressed: _delete, icon: const Icon(Icons.delete_outline)),
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
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in sceneIcons.entries)
                ChoiceChip(label: Icon(e.value, size: 20, semanticLabel: e.key), selected: _icon == e.key, onSelected: (_) => setState(() => _icon = e.key)),
            ]),
            const SizedBox(height: 16),
            Text(context.tr('scene.policy'), style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<FailurePolicy>(
              segments: [
                ButtonSegment(value: FailurePolicy.continueOnError, label: Text(context.tr('scene.policy.continue'))),
                ButtonSegment(value: FailurePolicy.stop, label: Text(context.tr('scene.policy.stop'))),
              ],
              selected: {_policy},
              onSelectionChanged: (s) => setState(() => _policy = s.first),
            ),
            SectionHeader(context.tr('scene.actions')),
            if (_actions.isEmpty) Text(context.tr('scene.noActions')),
            for (var i = 0; i < _actions.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: ActionEditorCard(
                  key: ObjectKey(_actions[i]),
                  index: i,
                  action: _actions[i],
                  showDelay: true,
                  onChanged: () => setState(() {}),
                  onRemove: () => setState(() => _actions.removeAt(i)),
                  onMoveUp: i == 0 ? null : () => setState(() => _actions.insert(i - 1, _actions.removeAt(i))),
                  onMoveDown: i == _actions.length - 1 ? null : () => setState(() => _actions.insert(i + 1, _actions.removeAt(i))),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() => _actions.add(EditableAction())),
              icon: const Icon(Icons.add),
              label: Text(context.tr('scene.addAction')),
            ),
          ]),
        ),
      ),
    );
  }
}
