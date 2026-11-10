import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/backend.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import 'live_video_view.dart';

/// Écran vidéo d'une caméra, pensé comme les applications de caméra : grande vidéo en haut,
/// boutons Direct / Historique, puis une barre du temps qu'on fait glisser du doigt pour
/// remonter dans la carte mémoire (relue par le boîtier vidéo, rien n'est copié ailleurs).
class CameraVideoPanel extends StatefulWidget {
  const CameraVideoPanel({super.key, required this.device});

  final Device device;

  @override
  State<CameraVideoPanel> createState() => _CameraVideoPanelState();
}

class _CameraVideoPanelState extends State<CameraVideoPanel> {
  bool _history = false;
  DateTime? _playback; // heure demandée au boîtier
  DateTime? _playingSince; // première image de la relecture
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// Position actuelle de la relecture : heure demandée + temps écoulé depuis la première image.
  DateTime? get _position {
    final p = _playback;
    if (p == null) return null;
    final since = _playingSince;
    return since == null ? p : p.add(DateTime.now().difference(since));
  }

  void _play(DateTime t) {
    _tick?.cancel();
    setState(() {
      _history = true;
      _playback = t;
      _playingSince = null;
    });
  }

  void _live() {
    _tick?.cancel();
    setState(() {
      _history = false;
      _playback = null;
      _playingSince = null;
    });
  }

  void _firstFrame() {
    if (_playback == null) return;
    _playingSince = DateTime.now();
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LiveVideoView(
          key: ValueKey('video-${d.id}'),
          device: d,
          playbackStart: _playback,
          onBackToLive: _live,
          onFirstFrame: _firstFrame,
        ),
        if (d.hasPlayback) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, icon: const Icon(Icons.sensors_rounded), label: Text(context.tr('history.live'))),
                ButtonSegment(value: true, icon: const Icon(Icons.history_rounded), label: Text(context.tr('history.replay'))),
              ],
              selected: {_history},
              onSelectionChanged: (s) => s.first ? setState(() => _history = true) : _live(),
            ),
          ),
          if (_history) CameraHistory(device: d, position: _position, onPlay: _play),
        ],
        if (!_history && d.udi.has('ptz_control')) CameraPtzPad(device: d),
      ],
    );
  }
}

/// Historique : choix du jour, puis barre du temps à faire glisser (enregistrements en couleur).
class CameraHistory extends StatefulWidget {
  const CameraHistory({super.key, required this.device, required this.onPlay, this.position});

  final Device device;

  /// Moment en cours de relecture (la barre le suit tant qu'on ne la touche pas).
  final DateTime? position;
  final ValueChanged<DateTime> onPlay;

  @override
  State<CameraHistory> createState() => _CameraHistoryState();
}

class _CameraHistoryState extends State<CameraHistory> {
  static const _days = 7;
  static const _pxPerMinute = 4.0; // une heure = 240 points : précis au doigt
  late DateTime _day = _today();
  final _cache = <DateTime, List<RecordingSlot>>{};
  bool _loading = false;
  String? _error;
  int _load = 0;
  DateTime? _cursor; // moment sous le trait central pendant qu'on fait glisser
  bool _dragging = false;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  DateTime get _dayEnd {
    final end = _day.add(const Duration(days: 1));
    final now = DateTime.now();
    return end.isAfter(now) ? now : end;
  }

  /// Ce que montre le trait central : le doigt, sinon la relecture, sinon le dernier enregistrement.
  DateTime get _shown {
    if (_dragging && _cursor != null) return _cursor!;
    final p = widget.position;
    if (p != null && _sameDay(p, _day)) return p;
    if (_cursor != null && _sameDay(_cursor!, _day)) return _cursor!;
    final slots = _cache[_day];
    if (slots != null && slots.isNotEmpty) return slots.last.start;
    return _dayEnd.subtract(const Duration(minutes: 30));
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _clamp(DateTime t) {
    if (t.isBefore(_day)) return _day;
    if (t.isAfter(_dayEnd)) return _dayEnd;
    return t;
  }

  Future<void> _fetch({bool force = false}) async {
    final day = _day;
    if (!force && _cache.containsKey(day) && day != _today()) return;
    final load = ++_load;
    setState(() {
      _loading = true;
      _error = null;
    });
    final backend = AppScope.read(context).backend;
    try {
      final id = await backend.requestVideoRecordings(widget.device.id, day);
      // Le boîtier interroge la caméra heure par heure : quelques secondes.
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      RecordingQuery? q;
      while (mounted && load == _load && DateTime.now().isBefore(deadline)) {
        q = await backend.getVideoRecordings(id);
        if (q != null && q.status != 'pending') break;
        await Future.delayed(const Duration(milliseconds: 800));
      }
      if (!mounted || load != _load) return;
      if (q == null || q.status == 'pending') throw BackendException('timeout', context.tr('history.noAnswer'));
      if (q.status == 'failed') throw BackendException('failed', q.error ?? context.tr('history.failed'));
      setState(() {
        _cache[day] = q!.slots;
        _loading = false;
      });
    } on BackendException catch (e) {
      if (mounted && load == _load) setState(() => (_loading = false, _error = e.message));
    } catch (_) {
      if (mounted && load == _load) setState(() => (_loading = false, _error = context.tr('history.failed')));
    }
  }

  void _pickDay(DateTime day) {
    setState(() {
      _day = day;
      _cursor = null;
    });
    _fetch();
  }

  RecordingSlot? _slotAt(DateTime t) {
    for (final s in _cache[_day] ?? const <RecordingSlot>[]) {
      if (!t.isBefore(s.start) && t.isBefore(s.end)) return s;
    }
    return null;
  }

  /// Lecture au moment choisi ; rien d'enregistré : on saute au prochain enregistrement.
  void _playAt(DateTime t) {
    var slot = _slotAt(t);
    var at = t;
    if (slot == null) {
      final next = (_cache[_day] ?? const <RecordingSlot>[]).where((s) => s.start.isAfter(t)).toList();
      if (next.isEmpty) {
        _toast(context.tr('history.nothingHere'));
        return;
      }
      slot = next.first;
      at = slot.start;
    }
    if (!slot.playable) {
      _toast(context.tr('history.oldFormat'));
      return;
    }
    setState(() => _cursor = at);
    widget.onPlay(at);
  }

  void _toast(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  void _jump(Duration by) => _playAt(_clamp(_shown.add(by)));

  String _dayLabel(BuildContext context, DateTime d) {
    final diff = _today().difference(d).inDays;
    if (diff == 0) return context.tr('history.today');
    if (diff == 1) return context.tr('history.yesterday');
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final theme = Theme.of(context);
    final slots = _cache[_day];
    final shown = _shown;
    final slot = slots == null ? null : _slotAt(shown);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Jour : flèches comme dans l'application de la caméra (7 derniers jours).
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(border: Border.all(color: f.inkFaint), borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        key: const ValueKey('history-prev-day'),
                        tooltip: context.tr('history.prevDay'),
                        onPressed: _today().difference(_day).inDays >= _days - 1 ? null : () => _pickDay(_day.subtract(const Duration(days: 1))),
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Text(_dayLabel(context, _day), style: theme.textTheme.titleSmall),
                      IconButton(
                        key: const ValueKey('history-next-day'),
                        tooltip: context.tr('history.nextDay'),
                        onPressed: _day == _today() ? null : () => _pickDay(_day.add(const Duration(days: 1))),
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ]),
                  ),
                  const Spacer(),
                  if (_loading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  IconButton(
                    tooltip: context.tr('history.refresh'),
                    onPressed: _loading ? null : () => _fetch(force: true),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Heure sous le trait central, dans une bulle au milieu, et ce qu'il y a à ce moment.
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(border: Border.all(color: f.inkFaint), borderRadius: BorderRadius.circular(22)),
                  child: Text(_hms(shown),
                      key: const ValueKey('history-time'),
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  slots == null
                      ? ''
                      : slot == null
                          ? context.tr('history.nothingHere')
                          : slot.playable
                              ? context.tr('history.recorded')
                              : context.tr('history.oldFormatShort'),
                  style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft),
                ),
              ),
              const SizedBox(height: 4),
              if (_error != null && slots == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.sd_card_alert_rounded, color: f.inkSoft),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_error!, style: theme.textTheme.bodyMedium?.copyWith(color: f.inkSoft))),
                      TextButton(onPressed: () => _fetch(force: true), child: Text(context.tr('common.retry'))),
                    ],
                  ),
                ),
              // Barre du temps : glisser vers la droite pour revenir en arrière, relâcher pour lire.
              SizedBox(
                height: 72,
                child: LayoutBuilder(
                  builder: (context, box) => GestureDetector(
                    key: const ValueKey('history-timeline'),
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (_) => setState(() {
                      _dragging = true;
                      _cursor = shown;
                    }),
                    onHorizontalDragUpdate: (e) => setState(() {
                      final minutes = -e.delta.dx / _pxPerMinute;
                      _cursor = _clamp((_cursor ?? shown).add(Duration(milliseconds: (minutes * 60000).round())));
                    }),
                    onHorizontalDragEnd: (_) {
                      setState(() => _dragging = false);
                      if (_cursor != null) _playAt(_cursor!);
                    },
                    onTapUp: (e) {
                      final dx = e.localPosition.dx - box.maxWidth / 2;
                      _playAt(_clamp(shown.add(Duration(milliseconds: (dx / _pxPerMinute * 60000).round()))));
                    },
                    child: CustomPaint(
                      size: Size(box.maxWidth, 72),
                      painter: _TimelinePainter(
                        center: shown,
                        day: _day,
                        dayEnd: _dayEnd,
                        slots: slots ?? const [],
                        pxPerMinute: _pxPerMinute,
                        recorded: f.brand,
                        oldFormat: f.inkFaint,
                        tick: f.inkSoft,
                        cursor: f.danger,
                        empty: f.chip,
                        label: theme.textTheme.labelSmall?.copyWith(color: f.inkSoft) ?? const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(onPressed: () => _jump(const Duration(seconds: -30)), icon: const Icon(Icons.replay_30_rounded), label: const Text('30 s')),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(onPressed: () => _jump(const Duration(seconds: 30)), icon: const Icon(Icons.forward_30_rounded), label: const Text('30 s')),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                slots != null && slots.isEmpty ? context.tr('history.empty') : context.tr('history.hint'),
                style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft, height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _hms(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';

/// Règle horizontale centrée sur [center] : graduations toutes les 10 minutes, heures écrites,
/// enregistrements en couleur (gris : ancien format illisible), trait rouge au milieu.
class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.center,
    required this.day,
    required this.dayEnd,
    required this.slots,
    required this.pxPerMinute,
    required this.recorded,
    required this.oldFormat,
    required this.tick,
    required this.cursor,
    required this.empty,
    required this.label,
  });

  final DateTime center, day, dayEnd;
  final List<RecordingSlot> slots;
  final double pxPerMinute;
  final Color recorded, oldFormat, tick, cursor, empty;
  final TextStyle label;

  double _x(DateTime t, Size size) => size.width / 2 + t.difference(center).inSeconds / 60 * pxPerMinute;

  @override
  void paint(Canvas canvas, Size size) {
    const barTop = 22.0, barH = 18.0;
    final dayRect = Rect.fromLTRB(_x(day, size).clamp(0, size.width), barTop, _x(dayEnd, size).clamp(0, size.width), barTop + barH);
    canvas.drawRRect(RRect.fromRectAndRadius(dayRect, const Radius.circular(6)), Paint()..color = empty.withValues(alpha: .8));
    for (final s in slots) {
      final l = _x(s.start, size), r = _x(s.end, size);
      if (r < 0 || l > size.width) continue;
      final rect = Rect.fromLTRB(l.clamp(0, size.width), barTop, r.clamp(0, size.width), barTop + barH);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)), Paint()..color = (s.playable ? recorded : oldFormat).withValues(alpha: .9));
    }
    final halfMinutes = size.width / 2 / pxPerMinute;
    final from = center.subtract(Duration(minutes: halfMinutes.ceil() + 10));
    var t = DateTime(from.year, from.month, from.day, from.hour, from.minute - from.minute % 10);
    final tickPaint = Paint()
      ..color = tick.withValues(alpha: .6)
      ..strokeWidth = 1;
    while (_x(t, size) <= size.width) {
      final x = _x(t, size);
      if (x >= 0 && !t.isBefore(day) && !t.isAfter(dayEnd)) {
        final hour = t.minute == 0;
        canvas.drawLine(Offset(x, barTop + barH + 2), Offset(x, barTop + barH + (hour ? 12 : 6)), tickPaint);
        if (hour) {
          final tp = TextPainter(text: TextSpan(text: '${t.hour.toString().padLeft(2, '0')}:00', style: label), textDirection: TextDirection.ltr)..layout();
          tp.paint(canvas, Offset(x - tp.width / 2, 2));
        }
      }
      t = t.add(const Duration(minutes: 10));
    }
    final mid = size.width / 2;
    canvas.drawLine(Offset(mid, 14), Offset(mid, size.height - 4), Paint()
      ..color = cursor
      ..strokeWidth = 2.5);
    canvas.drawCircle(Offset(mid, 14), 4, Paint()..color = cursor);
  }

  @override
  bool shouldRepaint(_TimelinePainter old) => old.center != center || old.slots != slots || old.day != day || old.dayEnd != dayEnd || old.recorded != recorded;
}

/// Pavé de direction pour orienter une caméra motorisée (comme dans l'application de la caméra) :
/// la caméra tourne tant que le doigt reste appuyé, et s'arrête d'elle-même si la connexion se perd.
class CameraPtzPad extends StatefulWidget {
  const CameraPtzPad({super.key, required this.device});

  final Device device;

  @override
  State<CameraPtzPad> createState() => _CameraPtzPadState();
}

class _CameraPtzPadState extends State<CameraPtzPad> {
  static const _speed = 0.6;
  Timer? _repeat;
  Offset? _dir;
  late final Backend _backend = AppScope.read(context).backend;

  @override
  void initState() {
    super.initState();
    _backend; // lu tant que le contexte est valide (l'arrêt part encore à la fermeture)
  }

  @override
  void dispose() {
    _repeat?.cancel();
    if (_dir != null) _send('stop');
    super.dispose();
  }

  Future<void> _send(String action, {Offset dir = Offset.zero, String? preset}) async {
    try {
      await _backend.cameraPtz(widget.device.id, action, pan: dir.dx, tilt: dir.dy, preset: preset);
    } on BackendException catch (e) {
      if (!mounted) return;
      _stop(send: false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {/* un ordre perdu : la caméra s'arrête seule au bout d'une seconde */}
  }

  void _start(Offset dir) {
    _repeat?.cancel();
    setState(() => _dir = dir);
    _send('move', dir: dir);
    // La caméra s'arrête seule après 1 s : on renouvelle l'ordre tant que le doigt reste posé.
    _repeat = Timer.periodic(const Duration(milliseconds: 700), (_) => _send('move', dir: dir));
  }

  void _stop({bool send = true}) {
    _repeat?.cancel();
    _repeat = null;
    if (_dir == null) return;
    setState(() => _dir = null);
    if (send) _send('stop');
  }

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    Widget arrow(Offset dir, IconData icon, String label, Alignment at) => Align(
          alignment: at,
          child: Semantics(
            button: true,
            label: label,
            child: Listener(
              onPointerDown: (_) => _start(dir),
              onPointerUp: (_) => _stop(),
              onPointerCancel: (_) => _stop(),
              child: Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: _dir == dir ? f.brand.withValues(alpha: .25) : Colors.transparent),
                child: Icon(icon, size: 40, color: _dir == dir ? f.brand : f.inkSoft),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Column(children: [
        Center(
          child: Container(
            key: const ValueKey('ptz-pad'),
            width: 220,
            height: 220,
            decoration: BoxDecoration(shape: BoxShape.circle, color: f.chip.withValues(alpha: .7), border: Border.all(color: f.inkFaint.withValues(alpha: .5))),
            child: Stack(children: [
              arrow(const Offset(0, _speed), Icons.arrow_drop_up_rounded, context.tr('ptz.up'), Alignment.topCenter),
              arrow(const Offset(0, -_speed), Icons.arrow_drop_down_rounded, context.tr('ptz.down'), Alignment.bottomCenter),
              arrow(const Offset(-_speed, 0), Icons.arrow_left_rounded, context.tr('ptz.left'), Alignment.centerLeft),
              arrow(const Offset(_speed, 0), Icons.arrow_right_rounded, context.tr('ptz.right'), Alignment.centerRight),
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).colorScheme.surface.withValues(alpha: .9)),
                  child: Icon(Icons.open_with_rounded, color: f.inkFaint),
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const ValueKey('ptz-preset'),
          onPressed: () => _send('preset', preset: '1'),
          icon: const Icon(Icons.bookmark_border_rounded),
          label: Text(context.tr('ptz.favorite')),
        ),
      ]),
    );
  }
}
