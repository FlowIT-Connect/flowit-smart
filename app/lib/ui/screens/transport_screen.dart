import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../core/transport.dart';
import '../../core/transport_data.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

Future<void> openTransport(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TransportScreen()));

/// Bus urbains, cars inter-wilayas et trains de la région du logement (ou de la position du téléphone).
class TransportScreen extends StatefulWidget {
  const TransportScreen({super.key, this.now});

  /// Heure figée pour les tests.
  final DateTime? now;

  @override
  State<TransportScreen> createState() => _TransportScreenState();
}

class _TransportScreenState extends State<TransportScreen> {
  TransportRegion? _region;
  bool _resolved = false;
  bool _locating = false;
  bool _fromPhone = false;
  double? _lat;
  double? _lon;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    final h = AppScope.read(context).home;
    _lat = h?.latitude;
    _lon = h?.longitude;
    _region = findTransportRegion(lat: _lat, lon: _lon, place: h?.locationName ?? h?.name);
    _resolved = _region != null || (_lat != null && _lon != null);
    // Les « prochain départ » restent justes si l'écran reste ouvert.
    if (widget.now == null) _tick = Timer.periodic(const Duration(minutes: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _locate() async {
    final state = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.tr('transport.locateFailed');
    setState(() => _locating = true);
    final ok = await state.location.requestPermission();
    final p = ok ? await state.location.current() : null;
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (p != null) {
        _lat = p.$1;
        _lon = p.$2;
        _fromPhone = true;
        _region = findTransportRegion(lat: p.$1, lon: p.$2);
        _resolved = true;
      }
    });
    if (p == null) messenger.showSnackBar(SnackBar(content: Text(failed)));
  }

  @override
  Widget build(BuildContext context) {
    final region = _region;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('transport.title')),
          if (region != null)
            Text(
              context.tr(_fromPhone ? 'transport.regionPhone' : 'transport.regionHome', {'region': region.name}),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: context.flow.inkSoft),
            ),
        ]),
        actions: [
          IconButton(
            key: const ValueKey('transport-locate'),
            tooltip: context.tr('transport.locate'),
            onPressed: _locating ? null : _locate,
            icon: _locating
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location_rounded),
          ),
          IconButton(
            key: const ValueKey('transport-pick-region'),
            tooltip: context.tr('transport.pickRegion'),
            onPressed: _pickRegion,
            icon: const Icon(Icons.map_outlined),
          ),
        ],
      ),
      body: region == null ? _noRegion(context) : _RegionView(key: ValueKey(region.id), region: region, lat: _lat, lon: _lon, now: widget.now),
    );
  }

  Future<void> _pickRegion() async {
    final picked = await showModalBottomSheet<TransportRegion>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(context.tr('transport.pickRegion'), style: Theme.of(context).textTheme.titleMedium)),
          for (final r in transportRegions)
            ListTile(
              key: ValueKey('transport-region-${r.id}'),
              leading: const Icon(Icons.location_city_rounded),
              title: Text(r.name),
              onTap: () => Navigator.of(context).pop(r),
            ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            subtitle: Text(context.tr('transport.moreRegionsSoon')),
          ),
        ]),
      ),
    );
    if (picked != null) {
      setState(() {
        _region = picked;
        _resolved = true;
      });
    }
  }

  Widget _noRegion(BuildContext context) => ListView(children: [
        EmptyState(
          icon: Icons.directions_bus_rounded,
          title: context.tr(_resolved ? 'transport.notCovered' : 'transport.unknownPlace'),
          message: context.tr(_resolved ? 'transport.notCoveredHint' : 'transport.unknownPlaceHint', {'regions': transportRegions.map((r) => r.name).join(', ')}),
          action: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
            FilledButton.icon(
              key: const ValueKey('transport-locate-empty'),
              onPressed: _locating ? null : _locate,
              icon: const Icon(Icons.my_location_rounded),
              label: Text(context.tr('transport.locate')),
            ),
            OutlinedButton.icon(onPressed: _pickRegion, icon: const Icon(Icons.map_outlined), label: Text(context.tr('transport.pickRegion'))),
          ]),
        ),
      ]);
}

class _RegionView extends StatelessWidget {
  const _RegionView({super.key, required this.region, this.lat, this.lon, this.now});

  final TransportRegion region;
  final double? lat;
  final double? lon;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final t = DayTime.of(now ?? DateTime.now());
    return DefaultTabController(
      length: 3,
      child: Column(children: [
        TabBar(tabs: [
          Tab(key: const ValueKey('transport-tab-urban'), icon: const Icon(Icons.directions_bus_rounded), text: context.tr('transport.urban')),
          Tab(key: const ValueKey('transport-tab-inter'), icon: const Icon(Icons.airport_shuttle_rounded), text: context.tr('transport.interWilaya')),
          Tab(key: const ValueKey('transport-tab-train'), icon: const Icon(Icons.train_rounded), text: context.tr('transport.train')),
        ]),
        Expanded(
          child: TabBarView(children: [
            _UrbanTab(region: region, now: t),
            _InterWilayaTab(region: region, now: t),
            _TrainTab(region: region, now: t, nearest: region.nearestStation(lat, lon)),
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- Bus urbains

class _UrbanTab extends StatelessWidget {
  const _UrbanTab({required this.region, required this.now});

  final TransportRegion region;
  final DayTime now;

  @override
  Widget build(BuildContext context) {
    final lines = region.byMode(TransportMode.urban);
    final official = lines.where((l) => l.verified).toList();
    final others = lines.where((l) => !l.verified).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
      if (official.isNotEmpty) ...[
        _Header(context.tr('transport.officialLines', {'operator': official.first.operator})),
        for (final l in official) _UrbanCard(line: l, now: now),
        _SourceNote(official.first.source, verified: true),
      ],
      if (others.isNotEmpty) ...[
        _Header(context.tr('transport.privateLines')),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final l in others)
              ListTile(
                key: ValueKey('transport-line-${l.id}'),
                dense: true,
                leading: _LineBadge(l.code, muted: true),
                title: Text(l.title),
                subtitle: Text(context.tr('transport.noTimetable')),
              ),
          ]),
        ),
        _SourceNote(others.first.source, verified: false),
      ],
    ]);
  }
}

class _UrbanCard extends StatelessWidget {
  const _UrbanCard({required this.line, required this.now});

  final TransportLine line;
  final DayTime now;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final theme = Theme.of(context);
    return Card(
      key: ValueKey('transport-line-${line.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _LineBadge(line.code),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(line.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              for (final s in line.services) ...[
                Text(
                  context.tr('transport.range', {'from': s.from, 'first': s.firstTime?.format() ?? '?', 'last': s.lastTime?.format() ?? '?'}),
                  style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                _RunningChip(running: line.services.first.runningAt(now)),
                if (line.lengthKm != null) InfoChip(icon: Icons.straighten_rounded, label: context.tr('transport.length', {'km': _km(line.lengthKm!)})),
                if (line.stopCount != null) InfoChip(icon: Icons.place_outlined, label: context.tr('transport.stops', {'n': line.stopCount})),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  static String _km(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1).replaceAll('.', ',');
}

class _RunningChip extends StatelessWidget {
  const _RunningChip({required this.running});

  final bool? running;

  @override
  Widget build(BuildContext context) {
    if (running == null) return const SizedBox.shrink();
    return InfoChip(
      icon: running! ? Icons.play_circle_outline_rounded : Icons.nightlight_round,
      label: context.tr(running! ? 'transport.running' : 'transport.stopped'),
    );
  }
}

// ---------------------------------------------------------- Cars inter-wilayas

class _InterWilayaTab extends StatelessWidget {
  const _InterWilayaTab({required this.region, required this.now});

  final TransportRegion region;
  final DayTime now;

  @override
  Widget build(BuildContext context) {
    final lines = region.byMode(TransportMode.interWilaya);
    if (lines.isEmpty) return EmptyState(icon: Icons.airport_shuttle_rounded, title: context.tr('transport.noneYet'));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
      if (region.busStation != null)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.storefront_rounded),
          title: Text(region.busStation!, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(context.tr('transport.busStationHint')),
        ),
      if (lines.any((l) => !l.verified)) _Warning(context.tr('transport.toConfirm', {'date': _date(context, lines.first.source.date)})),
      for (final l in lines) _CarTile(line: l, now: now),
      _SourceNote(lines.first.source, verified: lines.first.verified),
    ]);
  }
}

class _CarTile extends StatelessWidget {
  const _CarTile({required this.line, required this.now});

  final TransportLine line;
  final DayTime now;

  @override
  Widget build(BuildContext context) {
    final s = line.services.first;
    final next = s.nextDeparture(now);
    final last = s.lastTime;
    String summary;
    if (s.every != null && next == null && last != null && now <= last) {
      summary = context.tr('transport.everyUntil', {'min': s.every, 'last': last.format()});
    } else if (next != null) {
      summary = context.tr('transport.next', {'time': next.format()});
    } else {
      summary = context.tr('transport.noMoreToday', {'time': s.firstTime?.format() ?? '?'});
    }
    return Card(
      key: ValueKey('transport-line-${line.id}'),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(Icons.airport_shuttle_rounded),
        title: Text(context.tr('transport.toDestination', {'to': s.to}), style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(summary),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in s.times) _TimeChip(t, past: t.minutes < now.minutes, highlight: t == next),
          ]),
          if (s.every != null && last != null) ...[
            const SizedBox(height: 8),
            Text(context.tr('transport.everyUntil', {'min': s.every, 'last': last.format()})),
          ],
          if (line.note != null) ...[const SizedBox(height: 8), Text(line.note!, style: TextStyle(color: context.flow.inkSoft))],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- Train

class _TrainTab extends StatefulWidget {
  const _TrainTab({required this.region, required this.now, this.nearest});

  final TransportRegion region;
  final DayTime now;
  final TransportStop? nearest;

  @override
  State<_TrainTab> createState() => _TrainTabState();
}

class _TrainTabState extends State<_TrainTab> {
  late String? _station = widget.nearest?.name ?? widget.region.trainStations.firstOrNull?.name;

  @override
  Widget build(BuildContext context) {
    final lines = widget.region.byMode(TransportMode.train);
    if (lines.isEmpty) return EmptyState(icon: Icons.train_rounded, title: context.tr('transport.noneYet'));
    final stations = widget.region.trainStations;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
      if (stations.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: DropdownButtonFormField<String>(
            key: const ValueKey('transport-station'),
            initialValue: _station,
            decoration: InputDecoration(
              labelText: context.tr('transport.myStation'),
              helperText: widget.nearest != null ? context.tr('transport.nearestStation', {'station': widget.nearest!.name}) : null,
              prefixIcon: const Icon(Icons.train_rounded),
            ),
            items: [for (final s in stations) DropdownMenuItem(value: s.name, child: Text(s.name))],
            onChanged: (v) => setState(() => _station = v),
          ),
        ),
      for (final l in lines)
        for (final s in l.services) _TrainCard(line: l, service: s, station: _station, now: widget.now),
      _SourceNote(lines.first.source, verified: lines.first.verified, extra: lines.first.note),
    ]);
  }
}

class _TrainCard extends StatelessWidget {
  const _TrainCard({required this.line, required this.service, required this.station, required this.now});

  final TransportLine line;
  final TransportService service;
  final String? station;
  final DayTime now;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final at = station == null ? null : service.timeAt(station!);
    final arrival = service.stops.lastOrNull?.dayTime;
    final departure = at ?? service.firstTime;
    final gone = departure != null && departure.minutes < now.minutes;
    return Card(
      key: ValueKey('transport-train-${service.from}'),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(Icons.train_rounded),
        title: Text('${service.from} → ${service.to}', style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          at != null
              ? context.tr(gone ? 'transport.trainGone' : 'transport.trainAt', {'station': station, 'time': at.format(), 'arrival': arrival?.format() ?? '?'})
              : context.tr('transport.trainNotStopping', {'station': station ?? '?', 'time': service.firstTime?.format() ?? '?'}),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final s in service.stops)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Icon(s.name == station ? Icons.radio_button_checked_rounded : Icons.circle_outlined, size: 14, color: s.name == station ? f.brand : f.inkFaint),
                const SizedBox(width: 10),
                Expanded(child: Text(s.name, style: TextStyle(fontWeight: s.name == station ? FontWeight.w800 : FontWeight.w500))),
                Text(s.dayTime?.format() ?? '', style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
              ]),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Partagés

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: context.flow.ink)),
      );
}

class _LineBadge extends StatelessWidget {
  const _LineBadge(this.code, {this.muted = false});

  final String code;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    return Container(
      constraints: const BoxConstraints(minWidth: 38),
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: muted ? f.chip : f.brand, borderRadius: BorderRadius.circular(12)),
      child: Text(code, style: TextStyle(fontWeight: FontWeight.w900, color: muted ? f.ink : f.onBrand)),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip(this.time, {this.past = false, this.highlight = false});

  final DayTime time;
  final bool past;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: highlight ? f.brand : f.chip, borderRadius: BorderRadius.circular(999)),
      child: Text(
        time.format(),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: highlight ? f.onBrand : (past ? f.inkFaint : f.ink),
          decoration: past ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.amber.withValues(alpha: .16), borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: Colors.amber),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ]),
      );
}

String _date(BuildContext context, String iso) {
  final p = iso.split('-');
  if (p.length == 3) return '${p[2]}/${p[1]}/${p[0]}';
  if (p.length == 2) return '${p[1]}/${p[0]}';
  return iso;
}

/// D'où vient l'information, de quand elle date, et si elle est officielle.
class _SourceNote extends StatelessWidget {
  const _SourceNote(this.source, {required this.verified, this.extra});

  final TransportSource source;
  final bool verified;
  final String? extra;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: f.inkSoft);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(verified ? Icons.verified_outlined : Icons.help_outline_rounded, size: 16, color: verified ? f.brand : f.inkFaint),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              context.tr(verified ? 'transport.sourceVerified' : 'transport.sourceUnverified', {'source': source.name, 'date': _date(context, source.date)}),
              style: style,
            ),
            if (extra != null) Text(extra!, style: style),
            GestureDetector(
              onLongPress: () => Clipboard.setData(ClipboardData(text: source.url)),
              child: SelectableText(source.url, style: style?.copyWith(decoration: TextDecoration.underline)),
            ),
          ]),
        ),
      ]),
    );
  }
}
