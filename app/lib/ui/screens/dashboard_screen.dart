import 'package:flutter/material.dart';

import '../../core/icons.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/device_controls.dart';
import 'device_detail.dart';
import 'rooms_screen.dart';

/// Accueil : synthèse de la maison, scènes rapides, pièces, favoris, appareils à surveiller.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onNavigate});

  final void Function(int index) onNavigate;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final f = context.flow;
    final all = state.visibleDevices;
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
    final scenes = state.scenes.where((s) => s.enabled).toList();
    final rooms = state.rooms;

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: _HomeHero(devices: all, onShowDevices: () => onNavigate(2)),
        ),
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
        DeviceGrid(pinned),
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
                    leading: IconBubble(icon: deviceIcon(d), color: f.danger, size: 40),
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
      if (rooms.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SectionHeader(
            context.tr('nav.rooms'),
            trailing: TextButton(onPressed: () => onNavigate(1), child: Text(context.tr('common.seeAll'))),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: rooms.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _RoomShortcut(room: rooms[i]),
            ),
          ),
        ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 32)),
    ]);
  }
}

/// Carte d'accueil : salutation, appareils allumés, santé du réseau, climat.
class _HomeHero extends StatelessWidget {
  const _HomeHero({required this.devices, required this.onShowDevices});

  final List<Device> devices;
  final VoidCallback onShowDevices;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final theme = Theme.of(context);
    final online = devices.where((d) => d.isOnline).length;
    final active = devices.where((d) => d.isOnline && d.isOn == true).length;
    final unavailable = devices.where((d) => d.availability == Availability.unavailable).length;
    final temps = [
      for (final d in devices)
        if (d.isOnline && d.state['temperature'] is num) (d.state['temperature'] as num).toDouble(),
    ];
    final avgTemp = temps.isEmpty ? null : temps.reduce((a, b) => a + b) / temps.length;
    final hour = DateTime.now().hour;
    final greeting = context.tr(hour < 5 || hour >= 18 ? 'greeting.evening' : (hour < 12 ? 'greeting.morning' : 'greeting.afternoon'));
    final ratio = devices.isEmpty ? 0.0 : online / devices.length;
    const white = Colors.white;

    return Container(
      decoration: BoxDecoration(
        gradient: f.brandGradient,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: f.brand.withValues(alpha: .28), blurRadius: 32, offset: const Offset(0, 14))],
      ),
      child: Stack(children: [
        // Ondes décoratives, rappel du logo.
        Positioned.fill(child: CustomPaint(painter: _WavesPainter())),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(greeting, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium?.copyWith(color: white.withValues(alpha: .85))),
                  const SizedBox(height: 4),
                  Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                    Text('$active', style: theme.textTheme.displaySmall?.copyWith(color: white, fontWeight: FontWeight.w800, height: 1.1)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        context.tr('dashboard.active').toLowerCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(color: white, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    context.tr('dashboard.onlineOf', {'n': online, 'total': devices.length}),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: white.withValues(alpha: .85)),
                  ),
                ]),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 68,
                height: 68,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: ratio,
                      strokeWidth: 6,
                      strokeCap: StrokeCap.round,
                      color: white,
                      backgroundColor: white.withValues(alpha: .2),
                    ),
                  ),
                  Text('${(ratio * 100).round()}%', style: theme.textTheme.titleMedium?.copyWith(color: white, fontWeight: FontWeight.w800)),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _HeroPill(
                icon: unavailable > 0 ? Icons.error_outline_rounded : Icons.check_circle_rounded,
                label: unavailable > 0 ? context.tr('dashboard.unavailableCount', {'n': unavailable}) : context.tr('dashboard.allGood'),
                onTap: unavailable > 0 ? onShowDevices : null,
                strong: unavailable > 0,
              ),
              if (avgTemp != null)
                _HeroPill(icon: Icons.device_thermostat_rounded, label: '${avgTemp.toStringAsFixed(1)} °C'),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label, this.onTap, this.strong = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool strong;

  @override
  Widget build(BuildContext context) => Material(
        color: strong ? Colors.white : Colors.white.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: strong ? context.flow.danger : Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: strong ? context.flow.tileOnInk : Colors.white, fontWeight: FontWeight.w700),
              ),
            ]),
          ),
        ),
      );
}

class _WavesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: .10);
    for (var k = 0; k < 4; k++) {
      final path = Path();
      final y0 = size.height * (.55 + k * .12);
      path.moveTo(size.width * .35, y0);
      path.cubicTo(size.width * .55, y0 - 40, size.width * .75, y0 + 40, size.width * 1.05, y0 - 18);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors)),
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
class _RoomShortcut extends StatelessWidget {
  const _RoomShortcut({required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final f = context.flow;
    final devices = state.devicesInRoom(room.id);
    final on = devices.where((d) => d.isOnline && d.isOn == true).length;
    return SizedBox(
      width: 168,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoomPage(roomId: room.id))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              IconBubble(icon: roomIcon(room.icon), color: on > 0 ? f.amber : f.brand, size: 42, filled: on > 0, glow: on > 0),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(room.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    on > 0 ? context.tr('room.onCount', {'n': on}) : context.tr('room.deviceCount', {'n': devices.length}),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: on > 0 ? f.warning : f.inkSoft, fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
