import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/icons.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/device_controls.dart';
import '../widgets/device_visual.dart';

/// Ouvre la fiche d'un appareil (feuille modale, suit l'état en direct).
Future<void> showDeviceDetail(BuildContext context, String deviceId) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scroll) => DeviceDetail(deviceId: deviceId, scrollController: scroll),
      ),
    );

class DeviceDetail extends StatelessWidget {
  const DeviceDetail({super.key, required this.deviceId, this.scrollController});

  final String deviceId;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final d = state.devices[deviceId];
    if (d == null) {
      return EmptyState(icon: Icons.devices_other_rounded, title: context.tr('device.gone'));
    }
    final theme = Theme.of(context);
    final f = context.flow;
    final room = state.roomById(d.roomId);
    final canEdit = state.role.canConfigureDevices;
    final active = d.isOnline && d.isOn == true;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            DeviceVisual(d, size: 64, photoSize: 92, active: active),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.name, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    [room?.name ?? context.tr('room.none'), if ((d.vendor ?? '').isNotEmpty) '${d.vendor} ${d.model ?? ''}'.trim()].join(' · '),
                    style: theme.textTheme.bodyMedium?.copyWith(color: f.inkSoft),
                  ),
                ]),
              ),
            ),
            if (canEdit)
              IconButton.filledTonal(
                tooltip: d.isPinned ? context.tr('device.unpin') : context.tr('device.pin'),
                style: IconButton.styleFrom(
                  backgroundColor: d.isPinned ? f.brandSoft : f.chip,
                  foregroundColor: d.isPinned ? f.brandInk : f.inkSoft,
                ),
                icon: Icon(d.isPinned ? Icons.star_rounded : Icons.star_outline_rounded),
                onPressed: () => state.updateDevice(d, isPinned: !d.isPinned),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            AvailabilityBadge(d.availability),
            InfoChip(icon: protocolIcon(d.protocol), label: context.tr('protocol.${d.protocol}')),
            InfoChip(icon: Icons.route_rounded, label: context.tr('source.${d.connectionSource}')),
            InfoChip(icon: Icons.schedule_rounded, label: context.tr('device.updated', {'when': relativeTime(context, d.lastSeenAt)})),
          ]),
        ),
        const SizedBox(height: 12),
        DeviceControlPanel(d),
        if (canEdit)
          SettingsGroup(title: context.tr('device.manage'), children: [
            ListTile(
              leading: const TileIcon(Icons.edit_rounded),
              title: Text(context.tr('device.rename')),
              trailing: const ForwardChevron(),
              onTap: () async {
                final name = await promptText(context, title: context.tr('device.rename'), initial: d.name, label: context.tr('common.name'));
                if (name != null) await state.updateDevice(d, name: name);
              },
            ),
            ListTile(
              leading: TileIcon(Icons.photo_camera_rounded, color: f.orange),
              title: Text(context.tr('photo.title')),
              subtitle: Text(context.tr(d.photoPath != null ? 'photo.custom' : 'photo.auto')),
              trailing: const ForwardChevron(),
              onTap: () => _editPhoto(context, state, d),
            ),
            ListTile(
              leading: TileIcon(Icons.meeting_room_rounded, color: f.blue),
              title: Text(context.tr('device.move')),
              subtitle: Text(room?.name ?? context.tr('room.none')),
              trailing: const ForwardChevron(),
              onTap: () => _pickRoom(context, state, d),
            ),
            SwitchListTile(
              secondary: TileIcon(Icons.visibility_off_rounded, color: f.inkSoft),
              title: Text(context.tr('device.hide')),
              subtitle: Text(context.tr('device.hideHelp')),
              value: d.isHidden,
              onChanged: (v) => state.updateDevice(d, isHidden: v),
            ),
          ]),
      ],
    );
  }

  Future<void> _editPhoto(BuildContext context, AppState state, Device d) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_rounded), title: Text(context.tr('photo.take')), onTap: () => Navigator.pop(ctx, 'camera')),
          ListTile(leading: const Icon(Icons.photo_library_rounded), title: Text(context.tr('photo.pick')), onTap: () => Navigator.pop(ctx, 'gallery')),
          if (d.photoPath != null)
            ListTile(leading: const Icon(Icons.auto_awesome_rounded), title: Text(context.tr('photo.reset')), onTap: () => Navigator.pop(ctx, 'reset')),
        ]),
      ),
    );
    if (choice == null) return;
    if (choice == 'reset') {
      await state.clearDevicePhoto(d);
      return;
    }
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
    } catch (_) {
      state.notify(state.tr('photo.invalid'), error: true);
      return;
    }
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final type = photoContentType(file.mimeType, file.name);
    if (type == null) {
      state.notify(state.tr('photo.invalid'), error: true);
    } else if (bytes.length > 5 * 1024 * 1024) {
      state.notify(state.tr('photo.tooBig'), error: true);
    } else {
      await state.setDevicePhoto(d, bytes, type);
    }
  }

  Future<void> _pickRoom(BuildContext context, AppState state, Device d) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(context.tr('device.move')),
        children: [
          for (final r in state.rooms)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, r.id),
              child: ListTile(leading: Icon(roomIcon(r.icon)), title: Text(r.name), selected: r.id == d.roomId),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ''),
            child: ListTile(leading: const Icon(Icons.block_rounded), title: Text(context.tr('room.none')), selected: d.roomId == null),
          ),
        ],
      ),
    );
    if (selected == null) return;
    if (selected.isEmpty) {
      await state.updateDevice(d, clearRoom: true);
    } else {
      await state.updateDevice(d, roomId: selected);
    }
  }
}

/// Type d'image d'après le sélecteur (ou l'extension du fichier quand il ne le donne pas).
String? photoContentType(String? mime, String name) {
  final m = mime?.toLowerCase();
  if (m == 'image/jpeg' || m == 'image/png' || m == 'image/webp') return m;
  final ext = name.toLowerCase().split('.').last;
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => null,
  };
}
