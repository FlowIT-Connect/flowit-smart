import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../core/theme.dart';
import '../../../data/backend.dart';
import '../../../models/models.dart';
import '../../../state/app_state.dart';
import '../../widgets/common.dart';

/// « Ajouter un équipement vidéo » : recherche sur le réseau local (ONVIF) ou saisie manuelle.
///
/// Les identifiants partent directement dans un coffre lisible par le boîtier seulement :
/// l'application ne peut plus les relire ensuite. Renvoie l'identifiant de l'équipement ajouté.
class AddVideoDeviceScreen extends StatefulWidget {
  const AddVideoDeviceScreen({super.key});

  @override
  State<AddVideoDeviceScreen> createState() => _AddVideoDeviceScreenState();
}

class _AddVideoDeviceScreenState extends State<AddVideoDeviceScreen> {
  final _form = GlobalKey<FormState>();
  final _draft = VideoSourceDraft();
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '80');
  final _rtsp = TextEditingController();
  final _snapshot = TextEditingController();
  final _user = TextEditingController(text: 'admin');
  final _pass = TextEditingController();
  final _location = TextEditingController();
  bool _showPass = false;
  bool _saving = false;

  VideoScan? _scan;
  bool _scanning = false;
  String? _scanError;

  @override
  void dispose() {
    for (final c in [_name, _host, _port, _rtsp, _snapshot, _user, _pass, _location]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _search() async {
    final state = AppScope.read(context);
    final home = state.home;
    if (home == null) return;
    setState(() {
      _scanning = true;
      _scanError = null;
      _scan = null;
    });
    try {
      final id = await state.backend.requestVideoScan(home.id);
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      VideoScan? scan;
      while (mounted && DateTime.now().isBefore(deadline)) {
        scan = await state.backend.getVideoScan(id);
        if (scan != null && scan.finished) break;
        await Future.delayed(const Duration(seconds: 1));
      }
      if (!mounted) return;
      setState(() {
        _scan = scan;
        if (scan == null || !scan.finished) _scanError = state.tr('add.scanNoBox');
        if (scan?.status == 'failed') _scanError = scan?.error ?? state.tr('add.scanFailed');
      });
    } on BackendException catch (e) {
      if (mounted) setState(() => _scanError = e.message);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _pick(ScanResult r) {
    setState(() {
      _draft.driver = 'onvif';
      _host.text = r.host;
      _port.text = '${r.port}';
      if (_name.text.trim().isEmpty) _name.text = r.name ?? r.hardware ?? r.host;
    });
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final state = AppScope.read(context);
    final home = state.home;
    if (home == null) return;
    _draft
      ..name = _name.text
      ..host = _host.text
      ..port = int.tryParse(_port.text.trim()) ?? 80
      ..rtspUrl = _rtsp.text
      ..snapshotUrl = _snapshot.text
      ..username = _user.text
      ..password = _pass.text
      ..location = _location.text;
    setState(() => _saving = true);
    try {
      final id = await state.backend.addVideoSource(home.id, _draft);
      state.notify(state.tr('add.added'));
      if (mounted) Navigator.of(context).pop(id);
    } on BackendException catch (e) {
      state.notify(e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? context.tr('add.required') : null;

  String? _rtspValidator(String? v) {
    if (_draft.driver != 'rtsp') return null;
    final t = v?.trim() ?? '';
    if (!RegExp(r'^rtsps?://').hasMatch(t)) return context.tr('add.rtspInvalid');
    if (RegExp(r'^rtsps?://[^/]*@').hasMatch(t)) return context.tr('add.noCredsInUrl');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final theme = Theme.of(context);
    final onvif = _draft.driver == 'onvif';
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('add.title'))),
      body: ContentWidth(
        maxWidth: 720,
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
            // ------------------------------------------------ Recherche
            GlassPanel(
              radius: 22,
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr('add.search'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(context.tr('add.searchHelp'), style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft, height: 1.35)),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: _scanning ? null : _search,
                  icon: _scanning
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.radar_rounded),
                  label: Text(context.tr(_scanning ? 'add.searching' : 'add.searchButton')),
                ),
                if (_scanError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_scanError!, style: TextStyle(color: f.danger))),
                if (_scan?.status == 'done' && _scan!.results.isEmpty)
                  Padding(padding: const EdgeInsets.only(top: 8), child: Text(context.tr('add.nothingFound'), style: theme.textTheme.bodySmall)),
                for (final r in _scan?.results ?? const <ScanResult>[])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.videocam_rounded),
                    title: Text(r.name ?? r.hardware ?? r.host),
                    subtitle: Text([r.hardware, '${r.host}:${r.port}'].whereType<String>().join(' · ')),
                    trailing: r.alreadyAdded ? Text(context.tr('add.alreadyAdded'), style: theme.textTheme.labelSmall) : const Icon(Icons.add_rounded),
                    onTap: r.alreadyAdded ? null : () => _pick(r),
                  ),
              ]),
            ),
            const SizedBox(height: 14),
            // ------------------------------------------------ Saisie
            GlassPanel(
              radius: 22,
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(context.tr('add.manual'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                TextFormField(controller: _name, decoration: InputDecoration(labelText: context.tr('add.name')), validator: _required, maxLength: 60),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'camera', icon: const Icon(Icons.videocam_rounded), label: Text(context.tr('add.camera'))),
                    ButtonSegment(value: 'intercom', icon: const Icon(Icons.doorbell_rounded), label: Text(context.tr('add.intercom'))),
                  ],
                  selected: {_draft.category},
                  onSelectionChanged: (v) => setState(() => _draft.category = v.first),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [ButtonSegment(value: 'onvif', label: Text('ONVIF')), ButtonSegment(value: 'rtsp', label: Text('RTSP'))],
                  selected: {_draft.driver},
                  onSelectionChanged: (v) => setState(() => _draft.driver = v.first),
                ),
                const SizedBox(height: 4),
                Text(context.tr(onvif ? 'add.onvifHelp' : 'add.rtspHelp'), style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft, height: 1.35)),
                const SizedBox(height: 8),
                if (onvif)
                  Row(children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _host,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(labelText: context.tr('add.ip'), hintText: '192.168.1.20'),
                        validator: (v) => !onvif ? null : _required(v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _port,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: context.tr('add.port')),
                        validator: (v) {
                          final p = int.tryParse(v?.trim() ?? '');
                          return p == null || p < 1 || p > 65535 ? context.tr('add.portInvalid') : null;
                        },
                      ),
                    ),
                  ])
                else ...[
                  TextFormField(
                    controller: _rtsp,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(labelText: context.tr('add.rtspUrl'), hintText: 'rtsp://192.168.1.20:554/stream1'),
                    validator: _rtspValidator,
                  ),
                  TextFormField(
                    controller: _snapshot,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(labelText: context.tr('add.snapshotUrl'), hintText: 'http://192.168.1.20/snapshot.jpg'),
                  ),
                ],
                TextFormField(controller: _user, autocorrect: false, decoration: InputDecoration(labelText: context.tr('add.username'))),
                TextFormField(
                  controller: _pass,
                  obscureText: !_showPass,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: context.tr('add.password'),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _showPass = !_showPass),
                      icon: Icon(_showPass ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                    ),
                  ),
                ),
                TextFormField(controller: _location, decoration: InputDecoration(labelText: context.tr('add.location'), hintText: context.tr('add.locationHint')), maxLength: 80),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.lock_rounded, size: 16, color: f.inkSoft),
                  const SizedBox(width: 6),
                  Expanded(child: Text(context.tr('add.secretsHelp'), style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft, height: 1.35))),
                ]),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded),
                  label: Text(context.tr('add.save')),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
