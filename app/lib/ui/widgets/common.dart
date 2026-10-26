import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';

/// État vide (§5.11).
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant), textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// État d'erreur avec nouvel essai (§5.11).
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: Icons.error_outline,
        title: context.tr('error.title'),
        message: message,
        action: onRetry == null ? null : FilledButton.tonal(onPressed: onRetry, child: Text(context.tr('common.retry'))),
      );
}

/// Bandeau hors ligne / temps réel interrompu.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final String? text = !state.online
        ? context.tr('banner.offline')
        : (!state.realtimeConnected ? context.tr('banner.realtime') : null);
    final scheme = Theme.of(context).colorScheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: text == null
          ? const SizedBox(width: double.infinity)
          : Material(
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off_outlined, size: 18, color: scheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(child: Text(text, style: TextStyle(color: scheme.onErrorContainer))),
                    TextButton(
                      onPressed: () => state.home == null ? state.loadHomes() : state.refreshHome(),
                      child: Text(context.tr('common.retry')),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Disponibilité : disponible / indisponible / inconnu, distinct d'un état éteint (§10).
class AvailabilityBadge extends StatelessWidget {
  const AvailabilityBadge(this.availability, {super.key, this.compact = false});

  final Availability availability;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, icon) = switch (availability) {
      Availability.available => (Colors.green.shade600, Icons.circle),
      Availability.unavailable => (scheme.error, Icons.link_off),
      Availability.unknown => (scheme.outline, Icons.help_outline),
    };
    final label = context.tr('availability.${availability.name}');
    if (compact) {
      return Tooltip(message: label, child: Icon(icon, size: availability == Availability.available ? 10 : 16, color: color, semanticLabel: label));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color),
      const SizedBox(width: 4),
      Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
    ]);
  }
}

class InfoChip extends StatelessWidget {
  const InfoChip({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: scheme.onSecondaryContainer),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSecondaryContainer)),
      ]),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 20, 8, 8),
        child: Row(children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary))),
          ?trailing,
        ]),
      );
}

Future<bool> confirmDialog(BuildContext context, {required String title, required String message, String? confirmLabel, bool destructive = false}) async {
  final scheme = Theme.of(context).colorScheme;
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('common.cancel'))),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel ?? context.tr('common.confirm')),
        ),
      ],
    ),
  );
  return res ?? false;
}

Future<String?> promptText(BuildContext context, {required String title, String? initial, String? label, String? hint, TextInputType? keyboard}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      void submit() {
        final v = controller.text.trim();
        if (v.isNotEmpty) Navigator.pop(ctx, v);
      }

      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: keyboard,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onSubmitted: (_) => submit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('common.cancel'))),
          FilledButton(onPressed: submit, child: Text(context.tr('common.save'))),
        ],
      );
    },
  );
}

/// "il y a 5 min", "hier 18:20"…
String relativeTime(BuildContext context, DateTime? t) {
  if (t == null) return context.tr('time.never');
  final diff = DateTime.now().difference(t);
  if (diff.inSeconds < 45) return context.tr('time.now');
  if (diff.inMinutes < 60) return context.tr('time.minutes', {'n': diff.inMinutes});
  if (diff.inHours < 24) return context.tr('time.hours', {'n': diff.inHours});
  return MaterialLocalizations.of(context).formatShortDate(t);
}

String timeOfDay(BuildContext context, DateTime t) =>
    MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(t), alwaysUse24HourFormat: true);

/// Chevron « suivant » orienté selon le sens de lecture (RTL pour l'arabe).
class ForwardChevron extends StatelessWidget {
  const ForwardChevron({super.key});

  @override
  Widget build(BuildContext context) =>
      Transform.flip(flipX: Directionality.of(context) == TextDirection.rtl, child: const Icon(Icons.chevron_right));
}
