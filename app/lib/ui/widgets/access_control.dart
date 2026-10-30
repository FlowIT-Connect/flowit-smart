import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import 'common.dart';

/// Serrure / contrôle d'accès (TTLock) : activation par le propriétaire, codes au
/// clavier, ouverture à distance (avec passerelle) et historique des passages.
///
/// Fonctions de sécurité physique bloquées par défaut (§9) : le serveur refuse toute
/// commande tant que le propriétaire n'a pas activé l'appareil, puis ne l'accepte que
/// d'un propriétaire ou administrateur, à la main.
class AccessControlPanel extends StatefulWidget {
  const AccessControlPanel(this.device, {super.key});

  final Device device;

  @override
  State<AccessControlPanel> createState() => _AccessControlPanelState();
}

class _AccessControlPanelState extends State<AccessControlPanel> {
  List<AccessCode>? _codes;
  bool _revealed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_codes == null) _loadCodes();
  }

  Future<void> _loadCodes() async {
    final state = AppScope.of(context);
    if (!widget.device.isSecurityEnabled || !state.canManage) return;
    final codes = await state.accessCodes(widget.device.id);
    if (mounted) setState(() => _codes = codes);
  }

  Future<void> _enable(bool enabled) async {
    final state = AppScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(enabled ? Icons.lock_open_rounded : Icons.lock_rounded),
        title: Text(context.tr(enabled ? 'access.enableTitle' : 'access.disableTitle')),
        content: Text(context.tr(enabled ? 'access.enableBody' : 'access.disableBody')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.tr(enabled ? 'access.enable' : 'access.disable'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (await state.setDeviceSecurity(widget.device, enabled) && enabled) await _loadCodes();
  }

  Future<void> _createCode() async {
    final state = AppScope.of(context);
    final request = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CodeRequestSheet(),
    );
    if (request == null || !mounted) return;
    final result = await state.sendCommandAndWait(widget.device, 'access_code', request);
    if (result?.status != CommandStatus.confirmed || !mounted) return;
    final codes = await state.accessCodes(widget.device.id);
    if (!mounted) return;
    setState(() => _codes = codes);
    final created = codes.where((c) => c.commandId == result!.commandId).firstOrNull ?? codes.firstOrNull;
    if (created != null) await showDialog<void>(context: context, builder: (_) => _NewCodeDialog(created));
  }

  /// Partager (key == null), désactiver, réactiver, reprogrammer ou supprimer un accès.
  Future<void> _keyAction(SharedKey? key, [String action = 'send']) async {
    final state = AppScope.of(context);
    Map<String, dynamic>? value;
    if (action == 'send' || action == 'change_period') {
      value = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _KeyRequestSheet(existing: key),
      );
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('access.keyDeleteTitle', {'name': key!.name ?? key.receiver})),
          content: Text(context.tr('access.keyDeleteBody')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('common.cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.tr('access.keyDelete'))),
          ],
        ),
      );
      if (ok == true) value = {'action': 'delete', 'key_id': key!.id};
    } else {
      value = {'action': action, 'key_id': key!.id};
    }
    if (value == null || !mounted) return;
    final result = await state.sendCommandAndWait(widget.device, 'ekey', value);
    if (result?.status == CommandStatus.confirmed && mounted) state.notify(context.tr('access.keyDone.$action'));
  }

  Future<void> _unlock() async {
    final state = AppScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.door_front_door_rounded),
        title: Text(context.tr('access.unlockTitle', {'name': widget.device.name})),
        content: Text(context.tr('access.unlockBody')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.tr('access.unlock'))),
        ],
      ),
    );
    if (ok == true && mounted) await state.sendCommand(widget.device, 'lock_action', 'unlock');
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final d = widget.device;
    final f = context.flow;
    final theme = Theme.of(context);
    final isOwner = state.role == HomeRole.owner;
    final children = <Widget>[];

    if (d.isBlocked) {
      children.add(_Card(
        tint: f.warning,
        children: [
          Row(children: [
            TileIcon(Icons.shield_rounded, color: f.warning),
            const SizedBox(width: 14),
            Expanded(child: Text(context.tr('access.disabledTitle'), style: theme.textTheme.titleMedium)),
          ]),
          const SizedBox(height: 10),
          Text(context.tr('access.disabledBody'), style: theme.textTheme.bodyMedium?.copyWith(color: f.inkSoft, height: 1.4)),
          const SizedBox(height: 14),
          if (isOwner)
            FilledButton.icon(onPressed: () => _enable(true), icon: const Icon(Icons.lock_open_rounded), label: Text(context.tr('access.enable')))
          else
            Text(context.tr('access.ownerOnly'), style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft)),
        ],
      ));
    } else if (!state.canManage) {
      children.add(_Card(children: [Text(context.tr('access.managersOnly'), style: theme.textTheme.bodyMedium)]));
    } else {
      final codePending = state.pendingFor(d.id, 'access_code');
      final unlockPending = state.pendingFor(d.id, 'lock_action');
      final lockCap = d.capability('lock_action');
      final enabled = d.availability != Availability.unavailable;

      if (lockCap != null) {
        final lockState = d.state['lock_state'];
        children.add(_Card(children: [
          Row(children: [
            TileIcon(lockState == 'unlocked' ? Icons.lock_open_rounded : Icons.lock_rounded, color: f.violet),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr('access.remote'), style: theme.textTheme.titleMedium),
                Text(context.tr('access.lockState.${lockState is String ? lockState : 'unknown'}'), style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft)),
              ]),
            ),
            if (unlockPending != null) _status(context, unlockPending),
          ]),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: enabled && !(unlockPending?.isWaiting ?? false) ? _unlock : null,
            icon: const Icon(Icons.lock_open_rounded),
            label: Text(context.tr('access.unlock')),
          ),
        ]));
      }

      final codes = _codes;
      children.add(_Card(children: [
        Row(children: [
          TileIcon(Icons.dialpad_rounded, color: f.brand),
          const SizedBox(width: 14),
          Expanded(child: Text(context.tr('access.codes'), style: theme.textTheme.titleMedium)),
          if (codes != null && codes.isNotEmpty)
            IconButton(
              tooltip: context.tr(_revealed ? 'access.hideCodes' : 'access.showCodes'),
              onPressed: () => setState(() => _revealed = !_revealed),
              icon: Icon(_revealed ? Icons.visibility_off_rounded : Icons.visibility_rounded),
            ),
        ]),
        const SizedBox(height: 6),
        Text(context.tr(lockCap == null ? 'access.codesHintNoGateway' : 'access.codesHint'), style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft, height: 1.4)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: enabled && !(codePending?.isWaiting ?? false) ? _createCode : null,
          icon: codePending?.isWaiting ?? false
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add_rounded),
          label: Text(context.tr('access.newCode')),
        ),
        if (codes == null)
          const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
        else
          for (final c in codes.take(10)) _CodeRow(c, revealed: _revealed),
      ]));

      if (d.capability('ekey') != null) {
        final keyPending = state.pendingFor(d.id, 'ekey');
        final busy = keyPending?.isWaiting ?? false;
        final keys = SharedKey.fromState(d.state['ekeys']);
        children.add(_Card(children: [
          Row(children: [
            TileIcon(Icons.group_rounded, color: f.blue),
            const SizedBox(width: 14),
            Expanded(child: Text(context.tr('access.keys'), style: theme.textTheme.titleMedium)),
            if (keyPending != null) _status(context, keyPending),
          ]),
          const SizedBox(height: 6),
          Text(context.tr('access.keysHint'), style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft, height: 1.4)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: enabled && !busy ? () => _keyAction(null) : null,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: Text(context.tr('access.share')),
          ),
          if (keys.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(context.tr('access.keysEmpty'), style: theme.textTheme.bodyMedium?.copyWith(color: f.inkSoft)),
            ),
          for (final k in keys) _KeyRow(k, enabled: enabled && !busy, onAction: (action) => _keyAction(k, action)),
        ]));
      }
    }

    final log = AccessRecord.fromState(d.state['access_log']);
    if (d.capability('access_log') != null) {
      children.add(SectionHeader(context.tr('access.history')));
      children.add(_Card(children: [
        if (log.isEmpty) Text(context.tr('access.historyEmpty'), style: theme.textTheme.bodyMedium?.copyWith(color: f.inkSoft)),
        for (final r in log.take(10))
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(_methodIcon(r.method), color: r.ok ? f.brand : f.danger),
            title: Text([context.tr('access.method.${r.method}'), ?r.who].join(' · ')),
            subtitle: Text(_when(context, r.at) + (r.ok ? '' : ' · ${context.tr('access.refused')}')),
          ),
        Text(context.tr('access.historyHint'), style: theme.textTheme.bodySmall?.copyWith(color: f.inkFaint)),
      ]));
    }

    if (d.isSecurityEnabled && isOwner) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(onPressed: () => _enable(false), icon: const Icon(Icons.shield_rounded), label: Text(context.tr('access.disable'))),
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  Widget _status(BuildContext context, PendingCommand p) => p.isWaiting
      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
      : Icon(p.status == CommandStatus.confirmed ? Icons.check_circle : Icons.error_outline,
          color: p.status == CommandStatus.confirmed ? context.flow.success : Theme.of(context).colorScheme.error);
}

/// Date puis heure (TTLock : à l'heure près), dans l'année qui vient.
Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
  final now = DateTime.now();
  final day = await showDatePicker(context: context, initialDate: initial, firstDate: DateTime(now.year, now.month, now.day), lastDate: now.add(const Duration(days: 365)));
  if (day == null || !context.mounted) return null;
  final time = await showTimePicker(context: context, initialTime: TimeOfDay(hour: initial.hour, minute: 0));
  if (time == null) return null;
  return DateTime(day.year, day.month, day.day, time.hour);
}

DateTime _nextHour(DateTime t) => DateTime(t.year, t.month, t.day, t.hour).add(const Duration(hours: 1));

String _when(BuildContext context, DateTime t) {
  final loc = MaterialLocalizations.of(context);
  return '${loc.formatShortDate(t)} ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(t), alwaysUse24HourFormat: true)}';
}

IconData _methodIcon(String method) => switch (method) {
      'code' => Icons.dialpad_rounded,
      'app' => Icons.smartphone_rounded,
      'card' => Icons.credit_card_rounded,
      'fingerprint' => Icons.fingerprint_rounded,
      'key' => Icons.key_rounded,
      'remote' => Icons.cloud_rounded,
      _ => Icons.sensor_door_rounded,
    };

class _Card extends StatelessWidget {
  const _Card({required this.children, this.tint});

  final List<Widget> children;
  final Color? tint;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Card(
          color: tint?.withValues(alpha: .10),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      );
}

class _CodeRow extends StatelessWidget {
  const _CodeRow(this.code, {required this.revealed});

  final AccessCode code;
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final c = code;
    final validity = switch (c.kind) {
      'one_time' => context.tr('access.validOneTime', {'end': _when(context, c.endsAt ?? c.startsAt)}),
      'period' => context.tr('access.validPeriod', {'start': _when(context, c.startsAt), 'end': _when(context, c.endsAt ?? c.startsAt)}),
      _ => context.tr('access.validPermanent'),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.pin_rounded, color: c.isActive ? f.brand : f.inkFaint),
      title: Text([c.name ?? context.tr('access.kind.${c.kind}'), revealed ? c.code : '•' * c.code.length].join(' · '),
          style: TextStyle(fontFeatures: const [FontFeature.tabularFigures()], color: c.isActive ? f.ink : f.inkFaint)),
      subtitle: Text(c.isActive ? validity : context.tr('access.expired')),
      trailing: revealed
          ? IconButton(
              tooltip: context.tr('access.copy'),
              icon: const Icon(Icons.copy_rounded),
              onPressed: () => Clipboard.setData(ClipboardData(text: c.code)),
            )
          : null,
    );
  }
}

/// Code tout juste créé : en grand, à copier ou dicter.
class _NewCodeDialog extends StatelessWidget {
  const _NewCodeDialog(this.code);

  final AccessCode code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: const Icon(Icons.check_circle_rounded),
      title: Text(context.tr('access.created')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        SelectableText(
          code.code,
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall?.copyWith(letterSpacing: 4, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        const SizedBox(height: 12),
        Text(context.tr('access.createdHint.${code.kind}'), textAlign: TextAlign.center),
      ]),
      actions: [
        TextButton.icon(
          onPressed: () => Clipboard.setData(ClipboardData(text: code.code)),
          icon: const Icon(Icons.copy_rounded),
          label: Text(context.tr('access.copy')),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('common.close'))),
      ],
    );
  }
}

/// Demande de code : type, nom facultatif, période. Renvoie la valeur de la commande.
class _CodeRequestSheet extends StatefulWidget {
  const _CodeRequestSheet();

  @override
  State<_CodeRequestSheet> createState() => _CodeRequestSheetState();
}

class _CodeRequestSheetState extends State<_CodeRequestSheet> {
  String _kind = 'one_time';
  final _name = TextEditingController();
  late DateTime _start = _nextHour(DateTime.now());
  late DateTime _end = _start.add(const Duration(days: 1));

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final picked = await _pickDateTime(context, start ? _start : _end);
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _start = picked;
        if (!_end.isAfter(_start)) _end = _start.add(const Duration(hours: 1));
      } else {
        _end = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valid = _kind != 'period' || _end.isAfter(_start);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context.tr('access.newCode'), style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: [
            for (final k in ['one_time', 'period', 'permanent']) ButtonSegment(value: k, label: Text(context.tr('access.kind.$k'))),
          ],
          selected: {_kind},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _kind = s.first),
        ),
        const SizedBox(height: 10),
        Text(context.tr('access.kindHint.$_kind'), style: theme.textTheme.bodySmall?.copyWith(color: context.flow.inkSoft)),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          maxLength: 40,
          decoration: InputDecoration(labelText: context.tr('access.codeName'), hintText: context.tr('access.codeNameHint')),
        ),
        if (_kind == 'period') ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_rounded),
            title: Text(context.tr('access.from')),
            trailing: Text(_when(context, _start)),
            onTap: () => _pick(true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_busy_rounded),
            title: Text(context.tr('access.to')),
            trailing: Text(_when(context, _end)),
            onTap: () => _pick(false),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop(context, <String, dynamic>{
                    'type': _kind,
                    if (_name.text.trim().isNotEmpty) 'name': _name.text.trim(),
                    if (_kind == 'period') 'start': _start.toUtc().toIso8601String(),
                    if (_kind == 'period') 'end': _end.toUtc().toIso8601String(),
                  })
              : null,
          child: Text(context.tr('access.create')),
        ),
      ]),
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow(this.k, {required this.enabled, required this.onAction});

  final SharedKey k;
  final bool enabled;
  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final status = k.isExpired ? 'expired' : k.status;
    final period = k.isScheduled
        ? context.tr('access.validPeriod', {'start': _when(context, k.start!), 'end': _when(context, k.end!)})
        : context.tr('access.validPermanent');
    final dim = k.isFrozen || k.isExpired;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(k.isFrozen ? Icons.pause_circle_rounded : Icons.vpn_key_rounded, color: dim ? f.inkFaint : f.blue),
      title: Text(k.name ?? k.receiver, style: TextStyle(color: dim ? f.inkFaint : f.ink)),
      subtitle: Text([if (k.name != null && k.name != k.receiver) k.receiver, context.tr('access.keyStatus.$status'), period].join(' · ')),
      trailing: PopupMenuButton<String>(
        enabled: enabled,
        tooltip: context.tr('access.keyActions'),
        onSelected: onAction,
        itemBuilder: (context) => [
          PopupMenuItem(value: k.isFrozen ? 'unfreeze' : 'freeze', child: Text(context.tr(k.isFrozen ? 'access.keyUnfreeze' : 'access.keyFreeze'))),
          PopupMenuItem(value: 'change_period', child: Text(context.tr('access.keySchedule'))),
          PopupMenuItem(value: 'delete', child: Text(context.tr('access.keyDelete'))),
        ],
      ),
    );
  }
}

/// Partage d'un accès (destinataire, nom, dates) ou nouvelles dates d'un accès existant.
class _KeyRequestSheet extends StatefulWidget {
  const _KeyRequestSheet({this.existing});

  final SharedKey? existing;

  @override
  State<_KeyRequestSheet> createState() => _KeyRequestSheetState();
}

class _KeyRequestSheetState extends State<_KeyRequestSheet> {
  final _receiver = TextEditingController();
  final _name = TextEditingController();
  late bool _scheduled = widget.existing?.isScheduled ?? false;
  late DateTime _start = widget.existing?.start ?? _nextHour(DateTime.now());
  late DateTime _end = widget.existing?.end ?? _start.add(const Duration(days: 7));

  @override
  void dispose() {
    _receiver.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final picked = await _pickDateTime(context, start ? _start : _end);
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _start = picked;
        if (!_end.isAfter(_start)) _end = _start.add(const Duration(hours: 1));
      } else {
        _end = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existing = widget.existing;
    final receiver = _receiver.text.trim();
    final valid = (existing != null || RegExp(r'^\S{3,80}$').hasMatch(receiver)) && (!_scheduled || _end.isAfter(_start));
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(existing == null ? context.tr('access.share') : context.tr('access.keySchedule'), style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        if (existing == null) ...[
          Text(context.tr('access.shareHint'), style: theme.textTheme.bodySmall?.copyWith(color: context.flow.inkSoft, height: 1.4)),
          const SizedBox(height: 12),
          TextField(
            controller: _receiver,
            keyboardType: TextInputType.emailAddress,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: context.tr('access.receiver'), hintText: context.tr('access.receiverHint')),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            maxLength: 40,
            decoration: InputDecoration(labelText: context.tr('access.codeName'), hintText: context.tr('access.keyNameHint')),
          ),
        ] else
          Text(existing.name ?? existing.receiver, style: theme.textTheme.bodyMedium),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.tr('access.scheduled')),
          subtitle: Text(context.tr(_scheduled ? 'access.scheduledOn' : 'access.scheduledOff')),
          value: _scheduled,
          onChanged: (v) => setState(() => _scheduled = v),
        ),
        if (_scheduled) ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_rounded),
            title: Text(context.tr('access.from')),
            trailing: Text(_when(context, _start)),
            onTap: () => _pick(true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_busy_rounded),
            title: Text(context.tr('access.to')),
            trailing: Text(_when(context, _end)),
            onTap: () => _pick(false),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop(context, <String, dynamic>{
                    if (existing == null) ...{
                      'action': 'send',
                      'receiver': receiver,
                      if (_name.text.trim().isNotEmpty) 'name': _name.text.trim(),
                    } else ...{
                      'action': 'change_period',
                      'key_id': existing.id,
                    },
                    if (_scheduled) 'start': _start.toUtc().toIso8601String(),
                    if (_scheduled) 'end': _end.toUtc().toIso8601String(),
                  })
              : null,
          child: Text(context.tr(existing == null ? 'access.shareConfirm' : 'common.save')),
        ),
      ]),
    );
  }
}
