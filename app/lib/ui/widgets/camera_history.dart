import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/backend.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import 'common.dart';
import 'live_video_view.dart';

/// Vidéo d'une caméra avec son historique (carte mémoire relue par le boîtier vidéo) :
/// le direct en haut, la frise des heures enregistrées en dessous. Toucher une heure lit
/// le passage enregistré dans la même vue ; « Revenir au direct » rebascule.
class CameraVideoPanel extends StatefulWidget {
  const CameraVideoPanel({super.key, required this.device});

  final Device device;

  @override
  State<CameraVideoPanel> createState() => _CameraVideoPanelState();
}

class _CameraVideoPanelState extends State<CameraVideoPanel> {
  DateTime? _playback;

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LiveVideoView(key: ValueKey('video-${d.id}'), device: d, playbackStart: _playback, onBackToLive: () => setState(() => _playback = null)),
        if (d.hasPlayback)
          CameraHistory(
            device: d,
            selected: _playback,
            onPlay: (t) => setState(() => _playback = t),
            onLive: _playback == null ? null : () => setState(() => _playback = null),
          ),
      ],
    );
  }
}

/// Frise d'une journée : 24 cases, colorées quand la carte mémoire a quelque chose.
class CameraHistory extends StatefulWidget {
  const CameraHistory({super.key, required this.device, required this.onPlay, this.selected, this.onLive});

  final Device device;
  final DateTime? selected;
  final ValueChanged<DateTime> onPlay;
  final VoidCallback? onLive;

  @override
  State<CameraHistory> createState() => _CameraHistoryState();
}

class _CameraHistoryState extends State<CameraHistory> {
  static const _days = 7;
  late DateTime _day = _today();
  final _cache = <DateTime, List<RecordingSlot>>{};
  bool _loading = false;
  String? _error;
  int? _hour; // heure ouverte pour choisir les minutes
  int _load = 0;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _fetch();
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
      _hour = null;
    });
    _fetch();
  }

  void _tapHour(int h, RecordingSlot? slot) {
    if (slot == null) return;
    if (!slot.playable) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('history.oldFormat'))));
      return;
    }
    setState(() => _hour = _hour == h ? null : h);
    widget.onPlay(DateTime(_day.year, _day.month, _day.day, h));
  }

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
    final byHour = {for (final s in slots ?? const <RecordingSlot>[]) s.start.hour: s};
    final now = DateTime.now();
    final sel = widget.selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(context.tr('history.title')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (var i = 0; i < _days; i++)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 6),
                            child: ChoiceChip(
                              label: Text(_dayLabel(context, _today().subtract(Duration(days: i)))),
                              selected: _day == _today().subtract(Duration(days: i)),
                              onSelected: (_) => _pickDay(_today().subtract(Duration(days: i))),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_loading && slots == null)
                    Row(
                      children: [
                        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(context.tr('history.loading'), style: theme.textTheme.bodyMedium?.copyWith(color: f.inkSoft)),
                        ),
                      ],
                    )
                  else if (_error != null && slots == null)
                    Row(
                      children: [
                        Icon(Icons.sd_card_alert_rounded, color: f.inkSoft),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_error!, style: theme.textTheme.bodyMedium?.copyWith(color: f.inkSoft)),
                        ),
                        TextButton(onPressed: () => _fetch(force: true), child: Text(context.tr('common.retry'))),
                      ],
                    )
                  else ...[
                    // 24 cases : 4 rangées de 6 heures, lisibles au doigt.
                    LayoutBuilder(
                      builder: (context, box) {
                        const cols = 6;
                        final w = (box.maxWidth - 6 * (cols - 1)) / cols;
                        return Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (var h = 0; h < 24; h++)
                              _HourCell(
                                width: w,
                                hour: h,
                                slot: byHour[h],
                                future: DateTime(_day.year, _day.month, _day.day, h).isAfter(now),
                                playing: sel != null && sel.year == _day.year && sel.month == _day.month && sel.day == _day.day && sel.hour == h,
                                onTap: () => _tapHour(h, byHour[h]),
                              ),
                          ],
                        );
                      },
                    ),
                    if (_hour != null && byHour[_hour] != null) ...[
                      const SizedBox(height: 10),
                      Text(context.tr('history.pickMinute'), style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (var m = 0; m < 60; m += 10)
                            ActionChip(
                              label: Text('${_hour.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}'),
                              onPressed: () => widget.onPlay(DateTime(_day.year, _day.month, _day.day, _hour!, m)),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            slots != null && slots.isEmpty ? context.tr('history.empty') : context.tr('history.hint'),
                            style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft, height: 1.35),
                          ),
                        ),
                        if (_loading) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        IconButton(
                          tooltip: context.tr('history.refresh'),
                          onPressed: _loading ? null : () => _fetch(force: true),
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    if (widget.onLive != null)
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: widget.onLive,
                          icon: const Icon(Icons.live_tv_rounded),
                          label: Text(context.tr('history.backToLive')),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HourCell extends StatelessWidget {
  const _HourCell({required this.width, required this.hour, required this.slot, required this.future, required this.playing, required this.onTap});

  final double width;
  final int hour;
  final RecordingSlot? slot;
  final bool future;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final has = slot != null;
    final readable = slot?.playable ?? false;
    final bg = playing
        ? f.brandStrong
        : !has
        ? f.chip.withValues(alpha: future ? .35 : .8)
        : readable
        ? f.brand.withValues(alpha: .85)
        : f.inkFaint.withValues(alpha: .45);
    final fg = playing || (has && readable) ? f.onBrand : f.inkSoft.withValues(alpha: future ? .5 : 1);
    return Semantics(
      button: has,
      label: '${hour.toString().padLeft(2, '0')} h',
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: has ? onTap : null,
          child: SizedBox(
            width: width,
            height: 38,
            child: Center(
              child: Text(
                '${hour.toString().padLeft(2, '0')}h',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg, fontWeight: has ? FontWeight.w800 : FontWeight.w500),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
