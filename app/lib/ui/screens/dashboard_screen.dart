import 'package:flutter/material.dart';

import '../../core/icons.dart';
import '../../core/l10n.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/device_controls.dart';
import 'device_detail.dart';

/// Accueil : favoris, scènes rapides, appareils à surveiller.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onNavigate});

  final void Function(int index) onNavigate;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final all = state.visibleDevices;
    if (all.isEmpty && state.scenes.isEmpty) {
      return ListView(children: [
        EmptyState(
          icon: Icons.devices_other_outlined,
          title: context.tr('dashboard.emptyTitle'),
          message: context.tr(state.canManage ? 'dashboard.emptyManager' : 'dashboard.emptyMember'),
          action: state.canManage
              ? FilledButton.tonal(onPressed: () => onNavigate(5), child: Text(context.tr('integrations.title')))
              : null,
        ),
      ]);
    }
    final pinned = all.where((d) => d.isPinned).toList();
    final online = all.where((d) => d.isOnline).length;
    final attention = all.where((d) => d.availability == Availability.unavailable).toList();
    final active = all.where((d) => d.isOnline && d.isOn == true).length;
    final scenes = state.scenes.where((s) => s.enabled).toList();

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Row(children: [
              Expanded(child: _Stat(icon: Icons.wifi_tethering, value: '$online/${all.length}', label: context.tr('dashboard.online'))),
              const SizedBox(width: 8),
              Expanded(child: _Stat(icon: Icons.power_settings_new, value: '$active', label: context.tr('dashboard.active'))),
              const SizedBox(width: 8),
              Expanded(
                child: _Stat(
                  icon: Icons.link_off,
                  value: '${attention.length}',
                  label: context.tr('dashboard.unavailable'),
                  highlight: attention.isNotEmpty,
                ),
              ),
            ]),
          ),
        ),
      ),
      if (scenes.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionHeader(context.tr('nav.scenes'), trailing: TextButton(onPressed: () => onNavigate(3), child: Text(context.tr('common.seeAll'))))),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: scenes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final s = scenes[i];
                final running = state.sceneRuns.any((r) => r.sceneId == s.id && r.finishedAt == null);
                return ActionChip(
                  avatar: running ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(sceneIcon(s.icon)),
                  label: Text(s.name),
                  onPressed: running ? null : () => state.executeScene(s),
                );
              },
            ),
          ),
        ),
      ],
      SliverToBoxAdapter(child: SectionHeader(context.tr('dashboard.favorites'))),
      if (pinned.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(context.tr('dashboard.noFavorites'), style: Theme.of(context).textTheme.bodyMedium),
          ),
        )
      else
        DeviceGrid(pinned),
      if (attention.isNotEmpty) ...[
        SliverToBoxAdapter(child: SectionHeader(context.tr('dashboard.attention'))),
        SliverList.list(children: [
          for (final d in attention)
            ListTile(
              leading: Icon(deviceIcon(d), color: Theme.of(context).colorScheme.error),
              title: Text(d.name),
              subtitle: Text(context.tr('device.lastSeen', {'when': relativeTime(context, d.lastSeenAt)})),
              trailing: const AvailabilityBadge(Availability.unavailable),
              onTap: () => showDeviceDetail(context, d.id),
            ),
        ]),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ]);
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label, this.highlight = false});

  final IconData icon;
  final String value;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: highlight ? scheme.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 20, color: highlight ? scheme.onErrorContainer : scheme.primary),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(value, style: Theme.of(context).textTheme.titleLarge),
              ),
            ),
          ]),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}
