import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../core/theme.dart';
import '../../../data/backend.dart';
import '../../../models/models.dart';
import '../../../state/app_state.dart';
import '../../widgets/common.dart';
import 'security_screen.dart' show capabilityIcon, capabilityLabel;

/// Fiche technique et diagnostic d'un équipement vidéo (gestionnaires du logement).
class VideoSourceScreen extends StatefulWidget {
  const VideoSourceScreen({super.key, required this.sourceId, this.initial});
  final String sourceId;
  final VideoSource? initial;

  @override
  State<VideoSourceScreen> createState() => _VideoSourceScreenState();
}

class _VideoSourceScreenState extends State<VideoSourceScreen> {
  VideoSource? _source;
  Timer? _poll;
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _source = widget.initial;
    _load();
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_source?.testing ?? true) _load();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final state = AppScope.read(context);
    final home = state.home;
    if (home == null) return;
    try {
      final list = await state.backend.listVideoSources(home.id);
      final s = list.where((x) => x.id == widget.sourceId).firstOrNull;
      if (!mounted) return;
      setState(() {
        _source = s ?? _source;
        _gone = s == null;
      });
    } on BackendException catch (_) {
      // Réseau momentané : on garde l'affichage, prochain essai dans 3 s.
    }
  }

  Future<void> _retest() async {
    final state = AppScope.read(context);
    if (await state.run(() => state.backend.requestVideoSourceTest(widget.sourceId), success: state.tr('vsrc.testRequested'))) await _load();
  }

  Future<void> _credentials() async {
    final state = AppScope.read(context);
    final user = TextEditingController(text: 'admin');
    final pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('vsrc.credentials')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: user, decoration: InputDecoration(labelText: ctx.tr('add.username'))),
          TextField(controller: pass, obscureText: true, decoration: InputDecoration(labelText: ctx.tr('add.password'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.tr('common.save'))),
        ],
      ),
    );
    if (ok == true && await state.run(() => state.backend.setVideoSourceCredentials(widget.sourceId, user.text, pass.text), success: state.tr('vsrc.testRequested'))) {
      await _load();
    }
    user.dispose();
    pass.dispose();
  }

  Future<void> _delete() async {
    final state = AppScope.read(context);
    final s = _source;
    final sure = await confirmDialog(context,
        title: state.tr('vsrc.delete'), message: state.tr('vsrc.deleteConfirm', {'name': s?.name ?? ''}), destructive: true, confirmLabel: state.tr('vsrc.delete'));
    if (!sure || !mounted) return;
    if (await state.run(() => state.backend.deleteVideoSource(widget.sourceId))) {
      await state.refreshHome(silent: true);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _source;
    final f = context.flow;
    final theme = Theme.of(context);
    if (s == null || _gone) {
      return Scaffold(appBar: AppBar(), body: _gone ? EmptyState(icon: Icons.videocam_off_rounded, title: context.tr('vsrc.gone')) : const Center(child: CircularProgressIndicator()));
    }
    final statusColor = switch (s.status) {
      VideoSourceStatus.online => f.success,
      VideoSourceStatus.pending || VideoSourceStatus.connecting => f.inkFaint,
      VideoSourceStatus.authError => f.warning,
      _ => f.danger,
    };
    final identity = [s.manufacturer, s.model, if (s.firmware != null) 'firmware ${s.firmware}'].whereType<String>().join(' · ');
    final relays = (s.detected['relay_outputs'] as num?)?.toInt() ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(s.name)),
      body: ContentWidth(
        maxWidth: 720,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
          GlassPanel(
            radius: 22,
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.circle, size: 12, color: statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(context.tr(s.testing ? 'security.waitingBox' : 'vsrc.status.${s.status.name}'),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (s.testing) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
              if (s.lastError != null && s.status != VideoSourceStatus.online)
                Padding(padding: const EdgeInsets.only(top: 6), child: Text(s.lastError!, style: TextStyle(color: f.danger))),
              const SizedBox(height: 10),
              _kv(context, context.tr('vsrc.identity'), identity.isEmpty ? '—' : identity),
              _kv(context, context.tr('vsrc.protocol'), s.driver.toUpperCase()),
              _kv(context, context.tr('vsrc.address'), s.address),
              if (s.location != null) _kv(context, context.tr('add.location'), s.location!),
            ]),
          ),
          SectionHeader(context.tr('vsrc.available')),
          if (s.capabilities.enabled.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(context.tr('vsrc.noneYet'), style: theme.textTheme.bodySmall))
          else
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in s.capabilities.enabled) InfoChip(icon: capabilityIcon(c), label: capabilityLabel(context, c)),
            ]),
          if (relays > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(context.tr('vsrc.relayLater', {'count': relays}), style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft)),
            ),
          SectionHeader(context.tr('vsrc.diagnostic')),
          GlassPanel(
            radius: 22,
            child: Column(children: [
              if (s.steps.isEmpty) ListTile(title: Text(context.tr('vsrc.noDiagnostic'))),
              for (final st in s.steps)
                ListTile(
                  dense: true,
                  leading: Icon(st.ok ? Icons.check_circle_rounded : Icons.cancel_rounded, color: st.ok ? f.success : f.danger),
                  title: Text(context.tryTr('diag.${st.step}') ?? st.step),
                  subtitle: st.detail == null ? null : Text(st.detail!),
                ),
            ]),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: [
            FilledButton.tonalIcon(onPressed: s.testing ? null : _retest, icon: const Icon(Icons.refresh_rounded), label: Text(context.tr('vsrc.retest'))),
            OutlinedButton.icon(onPressed: _credentials, icon: const Icon(Icons.key_rounded), label: Text(context.tr('vsrc.credentials'))),
            TextButton.icon(
              onPressed: _delete,
              icon: Icon(Icons.delete_outline_rounded, color: f.danger),
              label: Text(context.tr('vsrc.delete'), style: TextStyle(color: f.danger)),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.flow.inkSoft))),
          Expanded(child: Text(v, style: Theme.of(context).textTheme.bodyMedium)),
        ]),
      );
}
