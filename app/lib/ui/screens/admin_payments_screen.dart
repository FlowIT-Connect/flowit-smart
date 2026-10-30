import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/backend.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/plan_card.dart';

/// Page « Paiements » de l'exploitant Solea : demandes de déblocage des logements.
///
/// Le paiement est vérifié à la main (versement, espèces…) ; « Paiement reçu » débloque
/// le logement et la passerelle y ajoute toute seule les appareils en attente.
class AdminPaymentsScreen extends StatefulWidget {
  const AdminPaymentsScreen({super.key});

  @override
  State<AdminPaymentsScreen> createState() => _AdminPaymentsScreenState();
}

class _AdminPaymentsScreenState extends State<AdminPaymentsScreen> {
  List<UpgradeRequest>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = AppScope.read(context);
    try {
      final items = await state.backend.adminListUpgrades();
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _approve(UpgradeRequest r) async {
    final choice = await showDialog<(int, int?)>(context: context, builder: (_) => _ApproveDialog(request: r));
    if (choice == null || !mounted) return;
    final state = AppScope.read(context);
    final ok = await state.run(
      () => state.backend.adminDecideUpgrade(r.id, approve: true, deviceLimit: choice.$1, months: choice.$2),
      success: state.tr('admin.approved', {'home': r.homeName}),
    );
    if (ok) {
      await _load();
      if (r.homeId == state.home?.id) await state.refreshPlan();
    }
  }

  Future<void> _reject(UpgradeRequest r) async {
    final state = AppScope.read(context);
    final sure = await confirmDialog(context,
        title: state.tr('admin.reject'), message: state.tr('admin.rejectConfirm', {'home': r.homeName}), destructive: true, confirmLabel: state.tr('admin.reject'));
    if (!sure || !mounted) return;
    if (await state.run(() => state.backend.adminDecideUpgrade(r.id, approve: false))) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('admin.payments')),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: context.tr('common.retry'))],
      ),
      body: _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : items == null
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? EmptyState(icon: Icons.payments_outlined, title: context.tr('admin.empty'), message: context.tr('admin.emptyHelp'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                        for (final r in items) _RequestCard(request: r, onApprove: () => _approve(r), onReject: () => _reject(r)),
                      ]),
                    ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.onApprove, required this.onReject});

  final UpgradeRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final f = context.flow;
    final theme = Theme.of(context);
    final until = r.paidUntil;
    final statusColor = switch (r.status) {
      'approved' => f.brand,
      'rejected' => f.danger,
      _ => f.orange,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(r.homeName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            Text(context.tr('admin.status.${r.status}'), style: TextStyle(color: statusColor, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          Text([if (r.ownerName != null) r.ownerName!, if (r.ownerEmail != null) r.ownerEmail!].join(' · '), style: TextStyle(color: f.inkSoft)),
          const SizedBox(height: 8),
          Text(context.tr('plan.count', {'n': r.deviceCount, 'limit': r.deviceLimit})),
          if (r.waitingDevices > 0) Text(context.tr('plan.waiting', {'n': r.waitingDevices}), style: TextStyle(color: f.orange)),
          if (r.status == 'approved')
            Text(until == null ? context.tr('plan.paidForever') : context.tr('plan.paidUntil', {'date': formatDay(until)}), style: TextStyle(color: f.inkSoft)),
          if (r.note != null) ...[
            const SizedBox(height: 6),
            Text('« ${r.note} »', style: const TextStyle(fontStyle: FontStyle.italic)),
          ],
          Text(context.tr('admin.requestedOn', {'date': formatDay(r.createdAt)}), style: theme.textTheme.bodySmall?.copyWith(color: f.inkFaint)),
          if (r.isPending) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(onPressed: onApprove, icon: const Icon(Icons.check_circle_rounded), label: Text(context.tr('admin.approve'))),
              OutlinedButton(onPressed: onReject, child: Text(context.tr('admin.reject'))),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// Choix du déblocage : nombre d'appareils et durée.
class _ApproveDialog extends StatefulWidget {
  const _ApproveDialog({required this.request});

  final UpgradeRequest request;

  @override
  State<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends State<_ApproveDialog> {
  static const _limits = [10, 20, 50, 100];
  static const _durations = <int?>[1, 3, 12, null]; // mois ; null = sans fin

  int _limit = 20;
  int? _months = 1;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('admin.approveTitle', {'home': widget.request.homeName})),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('admin.deviceLimit')),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final l in _limits)
              ChoiceChip(label: Text('$l'), selected: _limit == l, onSelected: (_) => setState(() => _limit = l)),
          ]),
          const SizedBox(height: 16),
          Text(context.tr('admin.duration')),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in _durations)
              ChoiceChip(
                label: Text(m == null ? context.tr('admin.forever') : context.tr('admin.months', {'n': m})),
                selected: _months == m,
                onSelected: (_) => setState(() => _months = m),
              ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('common.cancel'))),
        FilledButton(onPressed: () => Navigator.pop(context, (_limit, _months)), child: Text(context.tr('admin.confirmPayment'))),
      ],
    );
  }
}
