import 'package:flutter/material.dart';

import '../../core/icons.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/device_controls.dart';

/// Pièces : création, icône, réordonnancement (glisser), suppression (§5.2).
class RoomsScreen extends StatelessWidget {
  const RoomsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final rooms = state.rooms;
    final unassigned = state.devicesInRoom(null);
    final f = context.flow;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: state.canManage
          ? FloatingActionButton.extended(
              heroTag: 'room-add',
              onPressed: () => editRoom(context),
              icon: const Icon(Icons.add_rounded),
              label: Text(context.tr('room.add')),
            )
          : null,
      body: rooms.isEmpty && unassigned.isEmpty
          ? ListView(children: [
              EmptyState(icon: Icons.meeting_room_rounded, title: context.tr('room.emptyTitle'), message: context.tr(state.canManage ? 'room.emptyManager' : 'room.emptyMember')),
            ])
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 104),
              buildDefaultDragHandles: false,
              itemCount: rooms.length,
              proxyDecorator: (child, _, _) => Material(color: Colors.transparent, child: child),
              footer: unassigned.isEmpty
                  ? null
                  : _RoomCard(
                      icon: Icons.help_outline_rounded,
                      color: f.inkSoft,
                      title: context.tr('room.none'),
                      subtitle: context.tr('room.deviceCount', {'n': unassigned.length}),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RoomPage(roomId: null))),
                    ),
              onReorderItem: (from, to) => _reorder(state, from, to),
              itemBuilder: (context, i) {
                final r = rooms[i];
                final devices = state.devicesInRoom(r.id);
                final on = devices.where((d) => d.isOnline && d.isOn == true).length;
                return _RoomCard(
                  key: ValueKey(r.id),
                  icon: roomIcon(r.icon),
                  color: on > 0 ? f.amber : f.brand,
                  lit: on > 0,
                  title: r.name,
                  subtitle: context.tr('room.deviceCount', {'n': devices.length}),
                  badge: on > 0 ? context.tr('room.onCount', {'n': on}) : null,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoomPage(roomId: r.id))),
                  trailing: state.canManage
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(tooltip: context.tr('common.edit'), icon: Icon(Icons.edit_rounded, color: f.inkSoft), onPressed: () => editRoom(context, room: r)),
                          ReorderableDragStartListener(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(Icons.drag_indicator_rounded, color: f.inkFaint, semanticLabel: context.tr('room.reorder')),
                            ),
                          ),
                        ])
                      : const ForwardChevron(),
                );
              },
            ),
    );
  }

  Future<void> _reorder(AppState state, int from, int to) async {
    final list = [...state.rooms];
    final moved = list.removeAt(from);
    list.insert(to, moved);
    state.setRooms([for (var i = 0; i < list.length; i++) list[i].copyWith(sortOrder: i)]);
    await state.run(() async {
      for (final r in state.rooms) {
        await state.backend.updateRoom(r);
      }
    });
  }
}

/// Carte de pièce : icône lumineuse si des appareils sont allumés.
class _RoomCard extends StatelessWidget {
  const _RoomCard({super.key, required this.icon, required this.color, required this.title, required this.subtitle, this.badge, this.lit = false, this.trailing, this.onTap});

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? badge;
  final bool lit;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 8, 14),
            child: Row(children: [
              IconBubble(icon: icon, color: color, size: 50, filled: lit, glow: lit),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: f.inkSoft)),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: f.amber.withValues(alpha: .18), borderRadius: BorderRadius.circular(999)),
                        child: Text(badge!, style: theme.textTheme.labelSmall?.copyWith(color: f.warning, fontWeight: FontWeight.w800)),
                      ),
                  ]),
                ]),
              ),
              ?trailing,
            ]),
          ),
        ),
      ),
    );
  }
}

/// Création / modification d'une pièce (nom + icône).
Future<void> editRoom(BuildContext context, {Room? room}) async {
  final state = AppScope.read(context);
  final name = TextEditingController(text: room?.name);
  var icon = room?.icon ?? 'sofa';
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(context.tr(room == null ? 'room.add' : 'room.edit')),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: context.tr('common.name'))),
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in roomIcons.entries)
                ChoiceChip(
                  label: Icon(e.value, size: 20, semanticLabel: e.key),
                  selected: icon == e.key,
                  onSelected: (_) => setLocal(() => icon = e.key),
                ),
            ]),
          ]),
        ),
        actions: [
          if (room != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              child: Text(context.tr('common.delete'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(context.tr('common.cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, name.text.trim().isEmpty ? null : 'save'), child: Text(context.tr('common.save'))),
        ],
      ),
    ),
  );
  if (result == null || !context.mounted) return;
  if (result == 'delete') {
    final ok = await confirmDialog(context,
        title: context.tr('room.deleteTitle', {'name': room!.name}), message: context.tr('room.deleteMessage'), destructive: true, confirmLabel: context.tr('common.delete'));
    if (!ok) return;
    if (await state.run(() => state.backend.deleteRoom(room.id))) await state.refreshHome(silent: true);
    return;
  }
  final ok = await state.run(() async {
    if (room == null) {
      await state.backend.createRoom(state.home!.id, name.text, icon, state.rooms.length);
    } else {
      await state.backend.updateRoom(room.copyWith(name: name.text.trim(), icon: icon));
    }
  });
  if (ok) await state.refreshHome(silent: true);
}

/// Appareils d'une pièce.
class RoomPage extends StatelessWidget {
  const RoomPage({super.key, required this.roomId});

  final String? roomId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final room = state.roomById(roomId);
    final devices = state.devicesInRoom(roomId);
    final f = context.flow;
    final on = devices.where((d) => d.isOnline && d.isOn == true).length;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Row(children: [
          IconBubble(icon: roomIcon(room?.icon), color: on > 0 ? f.amber : f.brand, size: 40, filled: on > 0, glow: on > 0),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(room?.name ?? context.tr('room.none'), overflow: TextOverflow.ellipsis),
              Text(
                [context.tr('room.deviceCount', {'n': devices.length}), if (on > 0) context.tr('room.onCount', {'n': on})].join(' · '),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: f.inkSoft, fontWeight: FontWeight.w600),
              ),
            ]),
          ),
        ]),
      ),
      body: devices.isEmpty
          ? EmptyState(icon: roomIcon(room?.icon), title: context.tr('room.noDevices'), message: context.tr('room.noDevicesHelp'))
          : CustomScrollView(slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              DeviceGrid(devices, showRoom: false),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ]),
    );
  }
}
