import 'package:flutter/material.dart';

import '../../core/icons.dart';
import '../../core/l10n.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/organize.dart';
import '../widgets/device_controls.dart';
import '../widgets/room_removal.dart';
import '../widgets/room_visual.dart';
import 'room_editor.dart';

export 'room_editor.dart' show editRoom;

/// Pièces : cartes photo, création, image ; appui long pour réorganiser (ordre propre à
/// chaque utilisateur et à chaque logement) et supprimer une pièce.
class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  final _organize = OrganizeController();

  @override
  void dispose() {
    _organize.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final rooms = state.orderedRooms;
    final unassigned = state.devicesInRoom(null);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: state.canManage
          ? ListenableBuilder(
              listenable: _organize,
              builder: (context, _) => _organize.editing
                  ? const SizedBox.shrink()
                  : FloatingActionButton.extended(
                      heroTag: 'room-add',
                      onPressed: () => editRoom(context),
                      icon: const Icon(Icons.add_rounded),
                      label: Text(context.tr('room.add')),
                    ),
            )
          : null,
      body: rooms.isEmpty && unassigned.isEmpty
          ? ListView(children: [
              EmptyState(icon: Icons.meeting_room_rounded, title: context.tr('room.emptyTitle'), message: context.tr(state.canManage ? 'room.emptyManager' : 'room.emptyMember')),
            ])
          : OrganizeFrame(
              controller: _organize,
              title: 'room.organizeTitle',
              hint: state.canManage ? 'room.organizeHint' : 'room.organizeHintMember',
              child: CustomScrollView(slivers: [
                if (rooms.length > 1)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 8, 4),
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: ListenableBuilder(
                          listenable: _organize,
                          builder: (context, _) => TextButton.icon(
                            key: const ValueKey('rooms-organize'),
                            onPressed: _organize.editing ? null : _organize.start,
                            icon: const Icon(Icons.open_with_rounded),
                            label: Text(context.tr('room.reorderAll')),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                ReorderableTileGrid<Room>(
                  items: rooms,
                  idOf: (r) => r.id,
                  maxCrossAxisExtent: 260,
                  childAspectRatio: .95,
                  spacing: 14,
                  removeIcon: Icons.delete_outline_rounded,
                  removeLabel: context.tr('room.removeTitle'),
                  onRemove: state.canManage ? (r) => confirmRoomRemoval(context, r) : null,
                  onReorder: (ids) => state.saveOrder('rooms', ids),
                  itemBuilder: (context, r, editing) => RoomPhotoCard(
                    key: ValueKey(r.id),
                    room: r,
                    devices: state.devicesInRoom(r.id),
                    onTap: editing ? null : () => openRoom(context, r.id),
                  ),
                ),
                if (unassigned.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SizedBox(height: 14)),
                  RoomCardGrid(children: [
                    RoomPhotoCard(
                      key: const ValueKey('no-room'),
                      room: null,
                      devices: unassigned,
                      icon: Icons.help_outline_rounded,
                      onTap: () => openRoom(context, null),
                    ),
                  ]),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ]),
            ),
    );
  }
}

void openRoom(BuildContext context, String? roomId) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RoomPage(roomId: roomId)));

class RoomPage extends StatefulWidget {
  const RoomPage({super.key, required this.roomId});

  final String? roomId;

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  final _organize = OrganizeController();

  String? get roomId => widget.roomId;

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
    final room = state.roomById(roomId);
    final devices = state.devicesInRoom(roomId);
    final on = devices.where((d) => d.isOnline && d.isOn == true).length;
    final name = room?.name ?? context.tr('room.none');
    const white = Colors.white;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: OrganizeFrame(
        controller: _organize,
        currentRoomId: roomId,
        onDropToRoom: state.role.canConfigureDevices
            ? (id, target) {
                final d = state.devices[id];
                if (d != null) state.moveDeviceToRoom(d, target);
              }
            : null,
        child: CustomScrollView(slivers: [
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
          OrganizableDeviceGrid(devices, section: AppState.roomSection(roomId), showRoom: false),
          SliverToBoxAdapter(child: SizedBox(height: _organize.editing ? 200 : 24)),
        ],
      ]),
      ),
    );
  }
}
