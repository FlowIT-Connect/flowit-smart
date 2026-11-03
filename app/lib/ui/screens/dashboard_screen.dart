import 'climate_screen.dart';
import 'package:flutter/material.dart';

import '../../core/icons.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/device_controls.dart';
import '../widgets/device_visual.dart';
import '../widgets/organize.dart';
import 'add_device_menu.dart';
import '../widgets/weather_widgets.dart';
import 'device_detail.dart';
import '../widgets/home_modes_bar.dart';
import '../widgets/home_summary_panel.dart';
import '../widgets/room_visual.dart';
import 'rooms_screen.dart';

/// Accueil : synthèse de la maison, scènes rapides, pièces, favoris, appareils à surveiller.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.onNavigate});

  final void Function(int index) onNavigate;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _organize = OrganizeController();

  void Function(int index) get onNavigate => widget.onNavigate;

  @override
  void initState() {
    super.initState();
    _organize.addListener(_onOrganize);
  }

  void _onOrganize() => setState(() {});

  @override
  void dispose() {
    _organize.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final f = context.flow;
    final all = state.visibleDevices;
    // Météo extérieure : actualisée au plus toutes les 15 min, sans bloquer l'affichage.
    WidgetsBinding.instance.addPostFrameCallback((_) => state.refreshWeather());
    if (all.isEmpty && state.scenes.isEmpty) {
      return ListView(children: [
        EmptyState(
          icon: Icons.devices_other_rounded,
          title: context.tr('dashboard.emptyTitle'),
          message: context.tr(state.canManage ? 'dashboard.emptyManager' : 'dashboard.emptyMember'),
          action: state.canManage
              ? FilledButton.icon(onPressed: () => onNavigate(5), icon: const Icon(Icons.hub_rounded), label: Text(context.tr('integrations.title')))
              : null,
        ),
      ]);
    }
    final pinned = all.where((d) => d.isPinned).toList();
    final attention = all.where((d) => d.availability == Availability.unavailable).toList();
    final scenes = state.orderedScenes.where((s) => s.enabled).toList();
    final rooms = state.orderedRooms;

    return OrganizeFrame(
      controller: _organize,
      onDropToRoom: state.role.canConfigureDevices
          ? (id, roomId) {
              final d = state.devices[id];
              if (d != null) state.moveDeviceToRoom(d, roomId);
            }
          : null,
      child: CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: HomeSummaryPanel(devices: all, onShowDevices: () => onNavigate(2)),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _StatusPills(devices: all, onShowDevices: () => onNavigate(2)),
        ),
      ),
      const SliverToBoxAdapter(
        child: Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 0), child: HomeModesBar()),
      ),
      SliverToBoxAdapter(child: SectionHeader(context.tr('dashboard.favorites'))),
      if (pinned.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: f.line, width: 1.2),
              ),
              child: Row(children: [
                Icon(Icons.star_outline_rounded, color: f.inkFaint),
                const SizedBox(width: 12),
                Expanded(child: Text(context.tr('dashboard.noFavorites'), style: TextStyle(color: f.inkSoft, fontWeight: FontWeight.w600))),
              ]),
            ),
          ),
        )
      else
        OrganizableDeviceGrid(pinned, section: 'favorites', fromFavorites: true),
      if (attention.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionHeader(context.tr('dashboard.attention'))),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final d in attention)
                  ListTile(
                    leading: DeviceVisual(d, size: 40, photoSize: 44),
                    title: Text(d.name),
                    subtitle: Text(context.tr('device.lastSeen', {'when': relativeTime(context, d.lastSeenAt)})),
                    trailing: const ForwardChevron(),
                    onTap: () => showDeviceDetail(context, d.id),
                  ),
              ]),
            ),
          ),
        ),
      ],
      if (scenes.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionHeader(
            context.tr('nav.scenes'),
            trailing: TextButton(onPressed: () => onNavigate(3), child: Text(context.tr('common.seeAll'))),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: scenes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _SceneShortcut(scene: scenes[i]),
            ),
          ),
        ),
      ],
      const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 0), child: ClimateHomeCard())),
      if (rooms.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionHeader(
            context.tr('dashboard.myRooms'),
            trailing: TextButton(onPressed: () => onNavigate(1), child: Text(context.tr('common.seeAll'))),
          ),
        ),
        RoomCardGrid(children: [
          for (final r in rooms) RoomPhotoCard(key: ValueKey('home-room-${r.id}'), room: r, devices: state.devicesInRoom(r.id), onTap: () => openRoom(context, r.id)),
        ]),
      ],
      SliverToBoxAdapter(child: SizedBox(height: _organize.editing ? 120 : 32)),
    ]),
    );
  }
}

/// Pastilles sous le tableau : météo extérieure, appareils à vérifier, puissance.
class _StatusPills extends StatelessWidget {
  const _StatusPills({required this.devices, required this.onShowDevices});

  final List<Device> devices;
  final VoidCallback onShowDevices;

  @override
  Widget build(BuildContext context) {
    final weather = AppScope.of(context).weather;
    final unavailable = devices.where((d) => d.availability == Availability.unavailable).length;
    final power = devices.where((d) => d.isOnline && d.state['power'] is num).fold<double>(0, (sum, d) => sum + (d.state['power'] as num));
    final canAdd = AppScope.of(context).canManage;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      if (canAdd)
        _HeroPill(
          key: const ValueKey('add-device'),
          icon: Icons.add_rounded,
          label: context.tr('add.menu.button'),
          onTap: () => showAddDeviceMenu(context),
          strong: true,
        ),
      if (weather != null)
        _HeroPill(
          icon: weatherIcon(weather),
          label: '${context.tr('weather.outside')} ${formatDegrees(weather.temperature)}',
          onTap: () => showWeatherSheet(context),
        ),
      _HeroPill(
        icon: unavailable > 0 ? Icons.error_outline_rounded : Icons.check_circle_rounded,
        label: unavailable > 0 ? context.tr('dashboard.unavailableCount', {'n': unavailable}) : context.tr('dashboard.allGood'),
        onTap: unavailable > 0 ? onShowDevices : null,
        strong: unavailable > 0,
      ),
      if (power > 0)
        _HeroPill(icon: Icons.bolt_rounded, label: power >= 1000 ? '${(power / 1000).toStringAsFixed(1)} kW' : '${power.round()} W'),
    ]);
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({super.key, required this.icon, required this.label, this.onTap, this.strong = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    return Material(
      color: strong ? f.brand : f.glass,
      shape: StadiumBorder(side: BorderSide(color: strong ? Colors.transparent : f.glassBorder)),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: strong ? f.onBrand : f.brand),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: strong ? f.onBrand : f.ink, fontWeight: FontWeight.w700),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Raccourci de scène : carte en dégradé, lancement en un geste.
class _SceneShortcut extends StatelessWidget {
  const _SceneShortcut({required this.scene});

  final Scene scene;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final s = scene;
    final running = state.sceneRuns.any((r) => r.sceneId == s.id && r.finishedAt == null);
    final colors = sceneGradient(context, s.icon);
    return SizedBox(
      width: 156,
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Colors.white.withValues(alpha: .35))),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          // Verre teinté aux couleurs de la scène.
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [for (final c in colors) c.withValues(alpha: .72)]),
          ),
          child: InkWell(
            onTap: running ? null : () => state.executeScene(s),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .22), shape: BoxShape.circle),
                    child: running
                        ? const Padding(padding: EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(sceneIcon(s.icon), size: 19, color: Colors.white),
                  ),
                  const Spacer(),
                  Icon(Icons.play_arrow_rounded, color: Colors.white.withValues(alpha: .8)),
                ]),
                const Spacer(),
                Text(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Raccourci de pièce : icône, nom, appareils allumés.
