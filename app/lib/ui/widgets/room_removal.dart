import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import 'common.dart';

/// Fenêtre « Supprimer la pièce » (verre dépoli) : si la pièce contient des appareils,
/// l'utilisateur choisit où les ranger (une autre pièce ou « Sans pièce »).
/// Réservé au propriétaire et à l'administrateur. Renvoie true si la pièce a été supprimée.
Future<bool> confirmRoomRemoval(BuildContext context, Room room) async {
  final state = AppScope.read(context);
  if (!state.canManage) {
    state.notify(state.tr('error.denied'), error: true);
    return false;
  }
  final result = await showDialog<_RoomRemoval>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .35),
    builder: (ctx) => _RoomRemovalDialog(room: room),
  );
  if (result == null || !context.mounted) return false;
  return state.deleteRoom(room, moveTo: result.moveTo);
}

class _RoomRemoval {
  const _RoomRemoval(this.moveTo);
  final String? moveTo;
}

class _RoomRemovalDialog extends StatefulWidget {
  const _RoomRemovalDialog({required this.room});

  final Room room;

  @override
  State<_RoomRemovalDialog> createState() => _RoomRemovalDialogState();
}

class _RoomRemovalDialogState extends State<_RoomRemovalDialog> {
  String? _moveTo;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final theme = Theme.of(context);
    final state = AppScope.of(context);
    final count = state.devices.values.where((d) => d.roomId == widget.room.id).length;
    final others = [for (final r in state.orderedRooms) if (r.id != widget.room.id) r];
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GlassPanel(
          radius: 28,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: f.dangerSoft, shape: BoxShape.circle),
                  child: Icon(Icons.delete_outline_rounded, color: f.danger),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.tr('room.removeTitle'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    Text(widget.room.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: f.inkSoft, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
              const SizedBox(height: 14),
              Text(context.tr('room.removeQuestion'), style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              if (count == 0)
                Text(context.tr('room.removeEmpty'), style: TextStyle(color: f.inkSoft))
              else ...[
                Text(context.tr('room.removeDevices', {'n': count}), style: TextStyle(color: f.inkSoft)),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  key: const ValueKey('room-remove-target'),
                  initialValue: _moveTo,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: context.tr('room.removeMoveTo')),
                  items: [
                    DropdownMenuItem<String?>(value: null, child: Text(context.tr('room.none'))),
                    for (final r in others) DropdownMenuItem<String?>(value: r.id, child: Text(r.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _moveTo = v),
                ),
              ],
              const SizedBox(height: 10),
              Text(context.tr('room.removeKeeps'), style: TextStyle(fontSize: 12.5, color: f.inkFaint, height: 1.3)),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(key: const ValueKey('room-remove-cancel'), onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('common.cancel'))),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('room-remove-confirm'),
                  style: FilledButton.styleFrom(backgroundColor: f.danger, foregroundColor: Colors.white),
                  onPressed: () => Navigator.of(context).pop(_RoomRemoval(_moveTo)),
                  child: Text(context.tr('common.delete')),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
