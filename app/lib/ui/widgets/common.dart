import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';

export '../../core/glass.dart' show AmbientBackground, GlassPanel;

/// Logo Solea : un soleil en dégradé, du jaune à l'orange.
class SoleaLogo extends StatelessWidget {
  const SoleaLogo({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: SunPainter(context.flow.brandGradient)),
      );
}

/// Logo accompagné du nom de la marque.
class SoleaWordmark extends StatelessWidget {
  const SoleaWordmark({super.key, this.size = 32, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        SoleaLogo(size: size),
        SizedBox(width: size * .3),
        Text(
          'Solea',
          style: TextStyle(fontSize: size * .62, fontWeight: FontWeight.w800, letterSpacing: -.3, color: color ?? context.flow.ink),
        ),
      ]);
}

/// Dessin du soleil : disque central et rayons arrondis.
class SunPainter extends CustomPainter {
  SunPainter(this.gradient);

  final Gradient gradient;

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    final c = rect.center;
    final r = s.shortestSide / 2;
    final shader = gradient.createShader(rect);
    canvas.drawCircle(c, r * .44, Paint()..shader = shader);
    final ray = Paint()
      ..shader = shader
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * .15;
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 - math.pi / 2;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (r * .64), c + d * (r * .9), ray);
    }
  }

  @override
  bool shouldRepaint(covariant SunPainter oldDelegate) => oldDelegate.gradient != gradient;
}

/// Pastille ronde colorée portant une icône.
class IconBubble extends StatelessWidget {
  const IconBubble({super.key, required this.icon, required this.color, this.size = 40, this.filled = false, this.glow = false});

  final IconData icon;
  final Color color;
  final double size;

  /// Fond plein (icône blanche) plutôt que teinté.
  final bool filled;
  final bool glow;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: .16),
          shape: BoxShape.circle,
          boxShadow: glow ? [BoxShadow(color: color.withValues(alpha: .45), blurRadius: size * .55, spreadRadius: -size * .05)] : null,
        ),
        child: Icon(icon, size: size * .52, color: filled ? Colors.white : color),
      );
}

/// Groupe de réglages : lignes regroupées dans une carte arrondie, façon iOS.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) items.add(Divider(indent: 64, endIndent: 16, color: f.line.withValues(alpha: .7)));
      items.add(children[i]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (title != null) SectionHeader(title!),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Card(clipBehavior: Clip.antiAlias, child: Column(children: items)),
      ),
    ]);
  }
}

/// Icône de ligne de réglage : petite tuile colorée.
class TileIcon extends StatelessWidget {
  const TileIcon(this.icon, {super.key, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.flow.brand;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(color: c.withValues(alpha: .14), borderRadius: BorderRadius.circular(11)),
      child: Icon(icon, size: 19, color: c),
    );
  }
}

/// Largeur de lecture confortable sur grand écran.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 1120});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}

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
    final f = context.flow;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [f.brand.withValues(alpha: .22), f.brand.withValues(alpha: .04)]),
                ),
                child: Icon(icon, size: 44, color: f.brand),
              ),
              const SizedBox(height: 20),
              Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(message!, style: theme.textTheme.bodyMedium?.copyWith(color: f.inkSoft, height: 1.5), textAlign: TextAlign.center),
              ],
              if (action != null) ...[const SizedBox(height: 24), action!],
            ],
          ),
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
        icon: Icons.cloud_off_rounded,
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
    final f = context.flow;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: text == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Material(
                color: f.dangerSoft,
                borderRadius: BorderRadius.circular(18),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 6, 6),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off_rounded, size: 18, color: f.dangerInk),
                      const SizedBox(width: 10),
                      Expanded(child: Text(text, style: TextStyle(color: f.dangerInk, fontWeight: FontWeight.w600))),
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: f.dangerInk),
                        onPressed: () => state.home == null ? state.loadHomes() : state.refreshHome(),
                        child: Text(context.tr('common.retry')),
                      ),
                    ],
                  ),
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
    final f = context.flow;
    final (color, icon) = switch (availability) {
      Availability.available => (f.success, Icons.circle),
      Availability.unavailable => (f.danger, Icons.link_off_rounded),
      Availability.unknown => (f.inkFaint, Icons.help_outline_rounded),
    };
    final label = context.tr('availability.${availability.name}');
    if (compact) {
      if (availability == Availability.available) {
        return Tooltip(
          message: label,
          child: Semantics(
            label: label,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle, boxShadow: [BoxShadow(color: color.withValues(alpha: .5), blurRadius: 6)]),
            ),
          ),
        );
      }
      return Tooltip(message: label, child: Icon(icon, size: 16, color: color, semanticLabel: label));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: availability == Availability.available ? 8 : 14, color: color),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class InfoChip extends StatelessWidget {
  const InfoChip({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: f.chip, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: f.inkSoft),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: f.ink)),
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
        padding: const EdgeInsetsDirectional.fromSTEB(20, 22, 8, 8),
        child: Row(children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: context.flow.ink)),
          ),
          ?trailing,
        ]),
      );
}

Future<bool> confirmDialog(BuildContext context, {required String title, required String message, String? confirmLabel, bool destructive = false}) async {
  final f = context.flow;
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message, style: TextStyle(color: f.inkSoft, height: 1.45)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('common.cancel'))),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: f.danger, foregroundColor: Colors.white) : null,
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
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: keyboard,
            decoration: InputDecoration(labelText: label, hintText: hint),
            onSubmitted: (_) => submit(),
          ),
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
  Widget build(BuildContext context) => Transform.flip(
        flipX: Directionality.of(context) == TextDirection.rtl,
        child: Icon(Icons.chevron_right_rounded, color: context.flow.inkFaint),
      );
}
