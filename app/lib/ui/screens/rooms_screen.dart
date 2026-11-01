import 'package:flutter/material.dart';

import '../../core/icons.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/device_controls.dart';
import '../widgets/room_visual.dart';
import 'room_editor.dart';

export 'room_editor.dart' show editRoom;

/// Pièces : cartes photo, création, image, réordonnancement, suppression (§5.2).
class RoomsScreen extends StatelessWidget {
  const RoomsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final rooms = state.rooms;
    final unassigned = state.devicesInRoom(null);

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
          : CustomScrollView(slivers: [
              if (state.canManage && rooms.length > 1)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 8, 4),
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton.icon(
                        onPressed: () => _showReorder(context),
                        icon: const Icon(Icons.swap_vert_rounded),
                        label: Text(context.tr('room.reorderAll')),
                      ),
                    ),
                  ),
                )
              else
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
              RoomCardGrid(children: [
                for (final r in rooms)
                  RoomPhotoCard(
                    key: ValueKey(r.id),
                    room: r,
                    devices: state.devicesInRoom(r.id),
                    onTap: () => openRoom(context, r.id),
                  ),
                if (unassigned.isNotEmpty)
                  RoomPhotoCard(
                    key: const ValueKey('no-room'),
                    room: null,
                    devices: unassigned,
                    icon: Icons.help_outline_rounded,
                    onTap: () => openRoom(context, null),
                  ),
              ]),
              const SliverToBoxAdapter(child: SizedBox(height: 104)),
            ]),
    );
  }
}

void openRoom(BuildContext context, String? roomId) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoomPage(roomId: roomId)));

/// Ordre des pièces : liste à glisser dans une feuille.
Future<void> _showReorder(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const _ReorderSheet(),
    );

class _ReorderSheet extends StatelessWidget {
  const _ReorderSheet();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final f = context.flow;
    final rooms = state.rooms;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(context.tr('room.reorderAll'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              itemCount: rooms.length,
              onReorderItem: (from, to) => _reorder(state, from, to),
              itemBuilder: (context, i) {
                final r = rooms[i];
                return ListTile(
                  key: ValueKey(r.id),
                  leading: ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: 52, height: 40, child: RoomImage(room: r))),
                  title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(context.tr('room.deviceCount', {'n': state.devicesInRoom(r.id).length})),
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.drag_indicator_rounded, color: f.inkFaint, semanticLabel: context.tr('room.reorder')),
                    ),
                  ),
                );
              },
            ),
          ),
        ]),
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

/// Appareils d'une pièce, sous sa photo.
class RoomPage extends StatelessWidget {
  const RoomPage({super.key, required this.roomId});

  final String? roomId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final room = state.roomById(roomId);
    final devices = state.devicesInRoom(roomId);
    final on = devices.where((d) => d.isOnline && d.isOn == true).length;
    final name = room?.name ?? context.tr('room.none');
    const white = Colors.white;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 240,
          foregroundColor: white,
          backgroundColor: Colors.black.withValues(alpha: .35),
          title: Text(name, overflow: TextOverflow.ellipsis),
          actions: [
            if (room != null && state.canManage)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: FilledButton.tonalIcon(
                  key: const ValueKey('room-edit'),
                  style: FilledButton.styleFrom(backgroundColor: white.withValues(alpha: .2), foregroundColor: white),
                  onPressed: () => editRoom(context, room: room),
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: Text(context.tr('room.edit')),
                ),
              ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            collapseMode: CollapseMode.parallax,
            background: Stack(fit: StackFit.expand, children: [
              if (room != null) RoomImage(room: room) else const RoomIllustration('salon_moderne_1'),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x66000000), Color(0x00000000), Color(0x99000000)],
                    stops: [0, .4, 1],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Row(children: [
                  Icon(room == null ? Icons.help_outline_rounded : roomIcon(room.icon), color: white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      [context.tr('room.deviceCount', {'n': devices.length}), if (on > 0) context.tr('room.onCount', {'n': on})].join(' · '),
                      style: const TextStyle(color: white, fontWeight: FontWeight.w700),
                    ),
                  ),
                  RoomStatusPill(devices: devices),
                ]),
              ),
            ]),
          ),
        ),
        if (devices.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(icon: roomIcon(room?.icon), title: context.tr('room.noDevices'), message: context.tr('room.noDevicesHelp')),
          )
        else ...[
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          DeviceGrid(devices, showRoom: false),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ]),
    );
  }
}
