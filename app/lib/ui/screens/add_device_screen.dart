import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ble_lock.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/plan_card.dart';

enum _Kind { lock, tuya }

enum _Phase { idle, scanning, installing, registering, waiting, done, failed }

/// Ajout d'un appareil depuis Solea (propriétaire ou administrateur).
///
/// Serrure TTLock : installée en Bluetooth par ce téléphone, puis enregistrée sur le compte
/// TTLock par la passerelle. Appareil Tuya : couplé dans Smart Life (Tuya ne permet pas le
/// couplage hors de ses applications), puis repéré tout de suite par la passerelle.
/// Dans les deux cas, la passerelle lui donne le nom et la pièce choisis ici.
class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  final _name = TextEditingController();
  String? _roomId;
  _Kind? _kind;
  _Phase _phase = _Phase.idle;
  String? _message;
  String? _deviceId;
  final _found = <String, NewLock>{};
  StreamSubscription<NewLock>? _scan;

  /// Change à chaque nouvel essai : un résultat arrivé après « Annuler » est ignoré.
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    AppScope.read(context).refreshPlan(); // compteur à jour avant de choisir
  }

  @override
  void dispose() {
    _scan?.cancel();
    _name.dispose();
    super.dispose();
  }

  String? get _nameOrNull => _name.text.trim().isEmpty ? null : _name.text.trim();

  bool get _busy => const {_Phase.scanning, _Phase.installing, _Phase.registering, _Phase.waiting}.contains(_phase);

  void _set(_Phase phase, {String? message}) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _message = message;
    });
  }

  void _restart() {
    _attempt++;
    _scan?.cancel();
    _scan = null;
    _found.clear();
    _deviceId = null;
    _set(_Phase.idle);
  }

  // ---------------------------------------------------------------- Serrure TTLock
  void _startScan(AppState state) {
    _found.clear();
    _set(_Phase.scanning);
    _scan = state.ble.scanNewLocks().listen(
      (lock) {
        if (mounted) setState(() => _found[lock.mac] = lock);
      },
      onError: (Object e) {
        _scan?.cancel();
        _set(_Phase.failed, message: e is BleLockException ? state.tr('access.ble.error.${e.code}') : '$e');
      },
    );
  }

  Future<void> _installLock(AppState state, NewLock lock) async {
    await _scan?.cancel();
    _scan = null;
    _set(_Phase.installing);
    String lockData;
    try {
      lockData = await state.ble.initLock(lock);
    } on BleLockException catch (e) {
      _set(_Phase.failed, message: state.tr('access.ble.error.${e.code}'));
      return;
    }
    _set(_Phase.registering);
    final id = await state.requestPairing(kind: 'ttlock_lock', name: _nameOrNull ?? lock.name, roomId: _roomId, lockData: lockData);
    final result = id == null ? null : await state.waitPairing(id, timeout: const Duration(minutes: 2));
    if (result?.status == 'done') {
      _deviceId = result!.deviceId;
      _set(_Phase.done);
      return;
    }
    if (id != null && result?.status != 'failed') {
      // La passerelle n'a pas répondu : la demande reste valable, on ne touche pas à la serrure.
      _set(_Phase.failed, message: state.tr('pair.bridgeSlow'));
      return;
    }
    // Refusée : la serrure revient en mode installation pour pouvoir réessayer.
    var reset = false;
    try {
      await state.ble.resetLock(lockData);
      reset = true;
    } on BleLockException {
      // Message ci-dessous suffisant : réinitialiser la serrure à la main.
    }
    _set(_Phase.failed, message: [if (result?.error != null) result!.error!, if (reset) state.tr('pair.lock.resetDone')].join('\n'));
  }

  // ---------------------------------------------------------------- Smart Life (Tuya)
  Future<void> _startTuya(AppState state) async {
    final attempt = _attempt;
    final id = await state.requestPairing(kind: 'scan', name: _nameOrNull, roomId: _roomId);
    if (id == null) return;
    _set(_Phase.waiting);
    if (state.launcher.available) {
      unawaited(state.launcher.openTuyaApp().then((app) {
        if (app == null) state.notify(state.tr('pair.tuya.noApp'), error: true);
      }));
    }
    final result = await state.waitPairing(id, timeout: const Duration(minutes: 6));
    if (!mounted || attempt != _attempt) return; // annulé entre-temps
    if (result?.status == 'done') {
      _deviceId = result!.deviceId;
      _set(_Phase.done);
    } else {
      _set(_Phase.failed, message: result?.status == 'failed' ? result!.error : state.tr('pair.bridgeSlow'));
    }
  }

  // ---------------------------------------------------------------- Affichage
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('pair.add'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            if (_kind == null) ..._choice(context) else ..._flow(context, state),
          ]),
        ),
      ),
    );
  }

  List<Widget> _choice(BuildContext context) {
    final f = context.flow;
    final plan = AppScope.of(context).plan;
    if (plan?.managed ?? false) {
      // Logement équipé par l'installateur : le résident n'ajoute rien lui-même.
      return [
        const PlanCard(),
        const SizedBox(height: 8),
        _Banner(icon: Icons.support_agent_rounded, color: f.brand, title: context.tr('pair.managed.title'), message: context.tr('pair.managed.help')),
      ];
    }
    // Logement à sa limite : rien à installer (une serrure initialisée resterait orpheline).
    final full = plan?.isFull ?? false;
    Widget option(_Kind kind, IconData icon, Color color, String title, String subtitle) => Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: TileIcon(icon, color: color),
            title: Text(context.tr(title)),
            subtitle: Text(context.tr(subtitle)),
            trailing: const ForwardChevron(),
            enabled: !full,
            onTap: () => setState(() => _kind = kind),
          ),
        );
    return [
      const PlanCard(),
      SectionHeader(context.tr('pair.choose')),
      option(_Kind.tuya, Icons.devices_other_rounded, f.brand, 'pair.tuya.title', 'pair.tuya.subtitle'),
      const SizedBox(height: 8),
      option(_Kind.lock, Icons.lock_outline_rounded, f.violet, 'pair.lock.title', 'pair.lock.subtitle'),
    ];
  }

  List<Widget> _flow(BuildContext context, AppState state) {
    final lock = _kind == _Kind.lock;
    if (_phase == _Phase.done) return _done(context, state);
    return [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: TileIcon(lock ? Icons.lock_outline_rounded : Icons.devices_other_rounded, color: lock ? context.flow.violet : context.flow.brand),
        title: Text(context.tr(lock ? 'pair.lock.title' : 'pair.tuya.title'), style: Theme.of(context).textTheme.titleMedium),
        trailing: _busy ? null : TextButton(onPressed: () => setState(() => _kind = null), child: Text(context.tr('common.edit'))),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _name,
        enabled: !_busy,
        maxLength: 60,
        decoration: InputDecoration(labelText: context.tr('pair.name')),
      ),
      DropdownButtonFormField<String?>(
        initialValue: _roomId,
        isExpanded: true,
        decoration: InputDecoration(labelText: context.tr('pair.room')),
        items: [
          DropdownMenuItem(value: null, child: Text(context.tr('room.none'))),
          for (final r in state.rooms) DropdownMenuItem(value: r.id, child: Text(r.name, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: _busy ? null : (v) => setState(() => _roomId = v),
      ),
      const SizedBox(height: 16),
      if (lock) ..._lockSteps(context, state) else ..._tuyaSteps(context, state),
      if (_phase == _Phase.failed) ...[
        const SizedBox(height: 16),
        _Banner(icon: Icons.error_outline_rounded, color: context.flow.danger, title: context.tr('pair.failed'), message: _message),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(onPressed: _restart, icon: const Icon(Icons.refresh_rounded), label: Text(context.tr('common.retry'))),
      ],
    ];
  }

  List<Widget> _lockSteps(BuildContext context, AppState state) {
    if (!state.ble.available) {
      return [_Banner(icon: Icons.phone_android_rounded, color: context.flow.inkSoft, message: context.tr('pair.lock.androidOnly'))];
    }
    return [
      _Banner(icon: Icons.info_outline_rounded, color: context.flow.blue, message: context.tr('pair.lock.steps')),
      const SizedBox(height: 16),
      if (_phase == _Phase.idle)
        FilledButton.icon(onPressed: () => _startScan(state), icon: const Icon(Icons.bluetooth_searching_rounded), label: Text(context.tr('pair.lock.search'))),
      if (_phase == _Phase.scanning) ...[
        _Progress(context.tr(_found.isEmpty ? 'pair.lock.searching' : 'pair.lock.found')),
        for (final l in (_found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi))))
          Card(
            child: ListTile(
              leading: const Icon(Icons.lock_outline_rounded),
              title: Text(l.name),
              subtitle: Text(context.tr('pair.lock.signal', {'n': l.rssi})),
              trailing: const ForwardChevron(),
              onTap: () => _installLock(state, l),
            ),
          ),
        TextButton(onPressed: _restart, child: Text(context.tr('common.cancel'))),
      ],
      if (_phase == _Phase.installing) _Progress(context.tr('pair.lock.installing')),
      if (_phase == _Phase.registering) _Progress(context.tr('pair.lock.registering')),
    ];
  }

  List<Widget> _tuyaSteps(BuildContext context, AppState state) => [
        _Banner(icon: Icons.info_outline_rounded, color: context.flow.blue, message: context.tr('pair.tuya.steps')),
        const SizedBox(height: 16),
        if (_phase == _Phase.idle)
          FilledButton.icon(
            onPressed: () => _startTuya(state),
            icon: Icon(state.launcher.available ? Icons.open_in_new_rounded : Icons.check_rounded),
            label: Text(context.tr(state.launcher.available ? 'pair.tuya.open' : 'pair.tuya.added')),
          ),
        if (_phase == _Phase.waiting) ...[
          _Progress(context.tr('pair.tuya.waiting')),
          TextButton(onPressed: _restart, child: Text(context.tr('common.cancel'))),
        ],
      ];

  List<Widget> _done(BuildContext context, AppState state) {
    final device = state.devices[_deviceId];
    final room = state.roomById(device?.roomId);
    final name = device?.name ?? _nameOrNull ?? context.tr(_kind == _Kind.lock ? 'pair.lock.title' : 'pair.tuya.title');
    return [
      const SizedBox(height: 24),
      _Banner(
        icon: Icons.check_circle_rounded,
        color: context.flow.success,
        title: context.tr(_kind == _Kind.lock ? 'pair.lock.done' : 'pair.done', {'name': name}),
        message: [
          if (_kind == _Kind.lock) context.tr('pair.done', {'name': name}),
          if (room != null) room.name,
          if (_kind == _Kind.lock) context.tr('pair.lock.doneHint'),
        ].join('\n'),
      ),
      const SizedBox(height: 16),
      FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('pair.finish'))),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: () {
          _name.clear();
          _restart();
          setState(() => _kind = null);
        },
        child: Text(context.tr('pair.another')),
      ),
    ];
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, this.title, this.message});

  final IconData icon;
  final Color color;
  final String? title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (title != null) Text(title!, style: theme.textTheme.titleMedium),
              if (title != null && (message ?? '').isNotEmpty) const SizedBox(height: 4),
              if ((message ?? '').isNotEmpty) Text(message!, style: theme.textTheme.bodyMedium),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 14),
          Expanded(child: Text(label)),
        ]),
      );
}
