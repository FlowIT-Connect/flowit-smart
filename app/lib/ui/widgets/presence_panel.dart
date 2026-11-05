import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/presence.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../screens/automations_screen.dart';
import 'common.dart';

/// « 2 h 15 » ou « 12 min ».
String formatPresenceDuration(BuildContext context, Duration d) {
  if (d.inMinutes < 60) return context.tr('duration.minutes', {'n': d.inMinutes < 1 ? 1 : d.inMinutes});
  final m = d.inMinutes % 60;
  return context.tr('duration.hm', {'h': d.inHours, 'm': m.toString().padLeft(2, '0')});
}

/// Fiche d'un détecteur de présence : état en grand, depuis quand, frise du jour,
/// raccourcis vers les automatisations.
class PresencePanel extends StatefulWidget {
  const PresencePanel(this.device, {super.key});

  final Device device;

  @override
  State<PresencePanel> createState() => _PresencePanelState();
}

class _PresencePanelState extends State<PresencePanel> {
  List<EventLog>? _events;
  Timer? _tick;

  DateTime get _midnight {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _load();
    // « depuis 12 min » et la frise avancent même sans nouveau passage.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(PresencePanel old) {
    super.didUpdateWidget(old);
    if (old.device.state['motion'] != widget.device.state['motion']) _load();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final state = AppScope.read(context);
    try {
      final events = await state.backend.listPresence(widget.device.id, _midnight);
      if (mounted) setState(() => _events = events);
    } catch (_) {
      if (mounted) setState(() => _events = const []); // base pas encore à jour : état seul
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final d = widget.device;
    final f = context.flow;
    final theme = Theme.of(context);
    final online = d.isOnline;
    final present = online && d.state['motion'] == true;
    final now = DateTime.now();
    final day = presenceDay(_events ?? const [], presentNow: present, from: _midnight, now: now);

    final String subtitle;
    if (!online) {
      subtitle = context.tr('device.offlineControls');
    } else if (day.lastChange != null) {
      subtitle = context.tr('presence.since', {'d': formatPresenceDuration(context, now.difference(day.lastChange!))});
    } else {
      subtitle = context.tr(present ? 'presence.hereToday' : 'presence.noneToday');
    }
    final accent = present ? f.pink : f.inkSoft;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Card(
          key: const ValueKey('presence-card'),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: present ? .18 : .10),
                    border: Border.all(color: accent.withValues(alpha: present ? .55 : .2), width: 2),
                  ),
                  child: Icon(present ? Icons.directions_walk_rounded : Icons.person_off_outlined, size: 32, color: accent),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      context.tr(present ? 'presence.here' : 'presence.empty'),
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: present ? f.ink : f.inkSoft),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: f.inkSoft)),
                  ]),
                ),
              ]),
              const SizedBox(height: 18),
              Row(children: [
                Text(context.tr('presence.today'), style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 12),
                const Spacer(),
                if (_events == null)
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Flexible(
                    child: Text(
                      [
                        context.tr('presence.arrivals', {'n': day.arrivals}),
                        if (day.total > Duration.zero) context.tr('presence.total', {'d': formatPresenceDuration(context, day.total)}),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft),
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
              _PresenceTimeline(day: day, from: _midnight, now: now, color: f.pink, track: f.chip),
              const SizedBox(height: 4),
              Row(children: [
                for (final h in const ['0h', '6h', '12h', '18h', '24h']) ...[
                  Text(h, style: theme.textTheme.labelSmall?.copyWith(color: f.inkFaint)),
                  if (h != '24h') const Spacer(),
                ],
              ]),
              if (day.lastArrival != null) ...[
                const SizedBox(height: 10),
                Text(
                  context.tr('presence.lastArrival', {'t': timeOfDay(context, day.lastArrival!)}),
                  style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft),
                ),
              ],
            ]),
          ),
        ),
      ),
      SettingsGroup(title: context.tr('presence.actions'), children: [
        if (state.canManage)
          ListTile(
            key: const ValueKey('presence-automation'),
            leading: TileIcon(Icons.lightbulb_rounded, color: f.amber),
            title: Text(context.tr('presence.automationTitle')),
            subtitle: Text(context.tr('presence.automationHelp')),
            trailing: const ForwardChevron(),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AutomationEditor(template: 'presence', triggerDeviceId: d.id),
            )),
          ),
        ListTile(
          leading: TileIcon(Icons.notifications_active_rounded, color: f.danger),
          title: Text(context.tr('presence.alertTitle')),
          subtitle: Text(context.tr('presence.alertHelp')),
          trailing: Icon(Icons.check_circle_rounded, color: f.success),
        ),
      ]),
    ]);
  }
}

/// Frise de la journée : une barre, les présences en couleur.
class _PresenceTimeline extends StatelessWidget {
  const _PresenceTimeline({required this.day, required this.from, required this.now, required this.color, required this.track});

  final PresenceDay day;
  final DateTime from;
  final DateTime now;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 22,
        child: CustomPaint(painter: _TimelinePainter(day, from, now, color, track), size: Size.infinite),
      );
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.day, this.from, this.now, this.color, this.track);

  final PresenceDay day;
  final DateTime from;
  final DateTime now;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const dayMs = 24 * 3600 * 1000;
    double x(DateTime t) => (t.difference(from).inMilliseconds / dayMs).clamp(0.0, 1.0) * size.width;
    final r = Radius.circular(size.height / 2);
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, r));
    canvas.drawRect(rect, Paint()..color = track);
    final paint = Paint()..color = color;
    for (final (a, b) in day.segments) {
      final left = x(a);
      final right = x(b);
      canvas.drawRect(Rect.fromLTRB(left, 0, (right - left) < 2 ? left + 2 : right, size.height), paint);
    }
    // Heure actuelle.
    final nx = x(now);
    canvas.drawRect(Rect.fromLTWH(nx - 1, 0, 2, size.height), Paint()..color = color.withValues(alpha: .9));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TimelinePainter old) => old.day != day || old.now != now;
}
