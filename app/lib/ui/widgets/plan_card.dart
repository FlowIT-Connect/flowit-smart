import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';

/// Compteur d'appareils du logement (5 gratuits) et demande de déblocage.
///
/// Rien n'est affiché tant que la base ne connaît pas encore l'offre.
class PlanCard extends StatelessWidget {
  const PlanCard({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final plan = state.plan;
    if (plan == null) return const SizedBox.shrink();
    final f = context.flow;
    final theme = Theme.of(context);
    final color = plan.isFull ? f.orange : f.brand;
    final until = plan.paidUntil;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(plan.isPaid ? Icons.workspace_premium_rounded : Icons.inventory_2_outlined, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr('plan.count', {'n': plan.deviceCount, 'limit': plan.deviceLimit}),
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (plan.deviceCount / plan.deviceLimit).clamp(0, 1).toDouble(),
              minHeight: 8,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            plan.isPaid
                ? (until == null ? context.tr('plan.paidForever') : context.tr('plan.paidUntil', {'date': formatDay(until)}))
                : context.tr('plan.free', {'limit': HomePlan.freeLimit}),
            style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft),
          ),
          if (plan.waitingDevices > 0) ...[
            const SizedBox(height: 6),
            Text(context.tr('plan.waiting', {'n': plan.waitingDevices}), style: TextStyle(color: f.orange, fontWeight: FontWeight.w600)),
          ],
          if (plan.isFull && state.canManage) ...[
            const SizedBox(height: 12),
            if (plan.pendingRequest)
              Row(children: [
                Icon(Icons.hourglass_top_rounded, size: 18, color: f.inkSoft),
                const SizedBox(width: 8),
                Expanded(child: Text(context.tr('plan.pending'), style: TextStyle(color: f.inkSoft))),
              ])
            else
              FilledButton.icon(
                onPressed: () => state.requestUpgrade(),
                icon: const Icon(Icons.lock_open_rounded),
                label: Text(context.tr('plan.unlock')),
              ),
          ],
        ]),
      ),
    );
  }
}

/// Date courte « 30/11/2026 ».
String formatDay(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.day)}/${two(l.month)}/${l.year}';
}
