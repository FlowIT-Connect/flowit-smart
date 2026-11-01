import 'package:flutter/material.dart';

import '../../core/home_summary.dart';
import '../../core/icons.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import 'common.dart';
import 'device_controls.dart';

/// Un indicateur du tableau d'accueil. Pour en ajouter un (qualité de l'air,
/// consommation, présence…), il suffit d'ajouter une entrée à [summaryTiles].
class SummaryTile {
  final String key;
  final IconData icon;
  final Color Function(FlowColors f, HomeOverview s) color;
  final String labelKey;
  final String Function(BuildContext context, HomeOverview s) value;
  final void Function(BuildContext context, HomeOverview s)? onTap;

  /// Pastille de couleur à côté de la valeur (null : aucune).
  final Color? Function(FlowColors f, HomeOverview s)? dot;

  const SummaryTile({required this.key, required this.icon, required this.color, required this.labelKey, required this.value, this.onTap, this.dot});
}

String _deg(double v) => '${v.round()} °C';

Color _levelColor(FlowColors f, SummaryLevel l) => switch (l) {
      SummaryLevel.ok => f.success,
      SummaryLevel.warning => f.warning,
      SummaryLevel.alert => const Color(0xFFE5484D),
      SummaryLevel.none => f.inkFaint,
    };

List<SummaryTile> summaryTiles(VoidCallback onShowDevices) => [
      SummaryTile(
        key: 'home',
        icon: Icons.home_rounded,
        color: (f, _) => f.blue,
        labelKey: 'summary.home',
        value: (c, s) => c.tr('summary.devices', {'n': s.total}),
        dot: (f, s) => s.total == 0 ? null : _levelColor(f, s.homeLevel),
        onTap: (c, s) => _showHomeSheet(c, s, onShowDevices),
      ),
      SummaryTile(
        key: 'security',
        icon: Icons.verified_user_rounded,
        color: (f, s) => s.securityLevel == SummaryLevel.none ? f.inkSoft : _levelColor(f, s.securityLevel),
        labelKey: 'summary.security',
        value: (c, s) => switch (s.securityLevel) {
              SummaryLevel.none => c.tr('summary.noSensor'),
              SummaryLevel.alert => c.tr('summary.alert'),
              SummaryLevel.warning when s.openings > 0 => c.tr('summary.openings', {'n': s.openings}),
              SummaryLevel.warning => c.tr('summary.unlocked', {'n': s.unlocked}),
              SummaryLevel.ok => c.tr('summary.allClosed'),
            },
        onTap: (c, s) => _showDevicesSheet(c, c.tr('summary.security'), _securityDevices(c)),
      ),
      SummaryTile(
        key: 'climate',
        icon: Icons.thermostat_rounded,
        color: (f, _) => f.violet,
        labelKey: 'summary.climate',
        value: (c, s) => s.indoorTemperature == null ? '—' : _deg(s.indoorTemperature!),
        onTap: (c, s) => _showDevicesSheet(c, c.tr('summary.climate'), _climateDevices(c), header: _climateHeader(c, s)),
      ),
      SummaryTile(
        key: 'humidity',
        icon: Icons.water_drop_rounded,
        color: (f, _) => f.cyan,
        labelKey: 'summary.humidity',
        value: (c, s) => s.humidity == null ? '—' : '${s.humidity!.round()} %',
        onTap: (c, s) => _showHumiditySheet(c, s),
      ),
    ];

/// Bandeau de verre à 4 indicateurs : Maison connectée, Sécurité, Climatisation, Humidité.
class HomeSummaryPanel extends StatelessWidget {
  const HomeSummaryPanel({super.key, required this.devices, required this.onShowDevices});

  final List<Device> devices;
  final VoidCallback onShowDevices;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final summary = HomeOverview.of(devices);
    final tiles = summaryTiles(onShowDevices);
    return GlassPanel(
      radius: 28,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) VerticalDivider(width: 1, thickness: 1, indent: 14, endIndent: 14, color: f.glassBorder),
            Expanded(child: _Tile(tile: tiles[i], summary: summary)),
          ],
        ]),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.tile, required this.summary});

  final SummaryTile tile;
  final HomeOverview summary;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final theme = Theme.of(context);
    final color = tile.color(f, summary);
    final dot = tile.dot?.call(f, summary);
    return InkWell(
      key: ValueKey('summary-${tile.key}'),
      onTap: tile.onTap == null ? null : () => tile.onTap!(context, summary),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(tile.icon, size: 30, color: color, shadows: [Shadow(color: color.withValues(alpha: .55), blurRadius: 14)]),
          const SizedBox(height: 6),
          Text(
            context.tr(tile.labelKey),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(color: f.inkSoft, fontWeight: FontWeight.w600, height: 1.15),
          ),
          const SizedBox(height: 3),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(
                tile.value(context, summary),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(color: f.ink, fontWeight: FontWeight.w800, height: 1.15),
              ),
            ),
            if (dot != null) ...[
              const SizedBox(width: 5),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: dot, boxShadow: [BoxShadow(color: dot.withValues(alpha: .7), blurRadius: 6)]),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ Détails

List<Device> _securityDevices(BuildContext context) {
  final state = AppScope.read(context);
  return state.visibleDevices.where((d) {
    final k = deviceKind(d);
    return k == DeviceKind.lock || k == DeviceKind.door || k == DeviceKind.motion || ['smoke', 'water_leak', 'leak', 'moisture', 'gas'].any((c) => d.capability(c) != null);
  }).toList();
}

List<Device> _climateDevices(BuildContext context) {
  final state = AppScope.read(context);
  return state.visibleDevices.where((d) {
    final k = deviceKind(d);
    return k == DeviceKind.climate || k == DeviceKind.airConditioner || (k == DeviceKind.sensor && d.capability('temperature') != null);
  }).toList();
}

Widget _climateHeader(BuildContext context, HomeOverview s) {
  final f = context.flow;
  final parts = [
    if (s.indoorTemperature != null) '${context.tr('summary.indoor')} ${s.indoorTemperature!.toStringAsFixed(1)} °C',
    if (s.setpoint != null) '${context.tr('summary.setpoint')} ${s.setpoint!.toStringAsFixed(1)} °C',
    context.tr('summary.hvac.${s.climateState}'),
  ];
  return Text(parts.join(' · '), style: TextStyle(color: f.inkSoft, fontWeight: FontWeight.w700));
}

void _showHomeSheet(BuildContext context, HomeOverview s, VoidCallback onShowDevices) {
  final state = AppScope.read(context);
  final offline = state.visibleDevices.where((d) => d.availability == Availability.unavailable).toList();
  _showDevicesSheet(
    context,
    context.tr('summary.home'),
    offline,
    header: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(context.tr('summary.homeDetail', {'total': s.total, 'online': s.online, 'offline': s.offline}),
          style: TextStyle(color: context.flow.inkSoft, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Builder(
        builder: (ctx) => FilledButton.tonalIcon(
          onPressed: () {
            Navigator.pop(ctx);
            onShowDevices();
          },
          icon: const Icon(Icons.devices_rounded),
          label: Text(context.tr('summary.allDevices')),
        ),
      ),
    ]),
  );
}

void _showHumiditySheet(BuildContext context, HomeOverview s) {
  final state = AppScope.read(context);
  final f = context.flow;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.tr('summary.humidity'), style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (s.humidityByRoom.isEmpty)
            Text(context.tr('summary.noHumidity'), style: TextStyle(color: f.inkSoft))
          else
            for (final e in s.humidityByRoom.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(roomIcon(state.roomById(e.key)?.icon), color: f.cyan),
                title: Text(state.roomById(e.key)?.name ?? context.tr('room.none')),
                trailing: Text('${e.value.round()} %', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
        ]),
      ),
    ),
  );
}

void _showDevicesSheet(BuildContext context, String title, List<Device> devices, {Widget? header}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .6,
      maxChildSize: .92,
      builder: (ctx, scroll) => CustomScrollView(controller: scroll, slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              if (header != null) ...[const SizedBox(height: 6), header],
            ]),
          ),
        ),
        if (devices.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(context.tr('summary.nothing'), style: TextStyle(color: context.flow.inkSoft)),
            ),
          )
        else
          DeviceGrid(devices),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
    ),
  );
}
