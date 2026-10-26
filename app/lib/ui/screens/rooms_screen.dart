import 'package:flutter/material.dart';

import '../../core/icons.dart';
import '../../core/l10n.dart';
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

    return Scaffold(
      floatingActionButton: state.canManage
          ? FloatingActionButton.extended(
              heroTag: 'room-add',
              onPressed: () => editRoom(context),
              icon: const Icon(Icons.add),
              label: Text(context.tr('room.add')),
            )
          : null,
      body: rooms.isEmpty && unassigned.isEmpty
          ? ListView(children: [
              EmptyState(icon: Icons.meeting_room_outlined, title: context.tr('room.emptyTitle'), message: context.tr(state.canManage ? 'room.emptyManager' : 'room.emptyMember')),
            ])
          : ReorderableListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 96),
              buildDefaultDragHandles: false,
              itemCount: rooms.length,
              footer: unassigned.isEmpty
                  ? null
                  : ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.help_outline)),
                      title: Text(context.tr('room.none')),
                      subtitle: Text(context.tr('room.deviceCount', {'n': unassigned.length})),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RoomPage(roomId: null))),
                    ),
              onReorderItem: (from, to) => _reorder(state, from, to),
              itemBuilder: (context, i) {
                final r = rooms[i];
                final devices = state.devicesInRoom(r.id);
                final on = devices.where((d) => d.isOnline && d.isOn == true).length;
                return ListTile(
                  key: ValueKey(r.id),
                  leading: CircleAvatar(child: Icon(roomIcon(r.icon))),
                  title: Text(r.name),
                  subtitle: Text([
                    context.tr('room.deviceCount', {'n': devices.length}),
                    if (on > 0) context.tr('room.onCount', {'n': on}),
                  ].join(' · ')),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoomPage(roomId: r.id))),
                  trailing: state.canManage
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(tooltip: context.tr('common.edit'), icon: const Icon(Icons.edit_outlined), onPressed: () => editRoom(context, room: r)),
                          ReorderableDragStartListener(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: Icon(Icons.drag_handle, semanticLabel: context.tr('room.reorder')),
                            ),
                          ),
                        ])
                      : null,
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
    return Scaffold(
      appBar: AppBar(title: Text(room?.name ?? context.tr('room.none'))),
      body: devices.isEmpty
          ? EmptyState(icon: roomIcon(room?.icon), title: context.tr('room.noDevices'), message: context.tr('room.noDevicesHelp'))
          : CustomScrollView(slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              DeviceGrid(devices, showRoom: false),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ]),
    );
  }
}
