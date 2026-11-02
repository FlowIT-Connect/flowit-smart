import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/icons.dart';
import '../../core/l10n.dart';
import '../../core/room_library.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/room_visual.dart';
import 'device_detail.dart' show photoContentType;

/// Création / modification d'une pièce : nom, icône et image (bibliothèque Solea,
/// galerie, appareil photo), cadrage par glisser-zoomer et aperçu avant validation.
Future<void> editRoom(BuildContext context, {Room? room}) =>
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => RoomEditorScreen(room: room)));

class RoomEditorScreen extends StatefulWidget {
  const RoomEditorScreen({super.key, this.room});

  final Room? room;

  @override
  State<RoomEditorScreen> createState() => _RoomEditorScreenState();
}

class _RoomEditorScreenState extends State<RoomEditorScreen> {
  late final _name = TextEditingController(text: widget.room?.name);
  late String _icon = widget.room?.icon ?? 'sofa';
  late String? _imageKey = widget.room?.imageKey;
  late RoomImageFit _fit = widget.room?.imageFit ?? RoomImageFit.centered;
  Uint8List? _photo;
  String? _photoType;
  late bool _removePhoto = false;
  late String _category = (RoomLibrary.categoryOfImage(_draft.libraryImage) ?? RoomLibrary.categories.first).key;
  bool _saving = false;

  // Geste en cours sur l'aperçu.
  RoomImageFit? _gestureStart;
  Offset _gestureOrigin = Offset.zero;

  bool get _hasStoredPhoto => widget.room?.photoPath != null && !_removePhoto;
  bool get _showsPhoto => _photo != null || _hasStoredPhoto;

  /// Pièce telle qu'elle sera enregistrée (pour l'aperçu).
  Room get _draft => (widget.room ?? Room(id: '', homeId: '', name: '')).copyWith(
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        icon: _icon,
        imageKey: _imageKey,
        clearImageKey: _imageKey == null,
        imageFit: _fit,
        clearPhoto: _removePhoto,
      );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _chooseLibrary(String key) => setState(() {
        _imageKey = key;
        _photo = null;
        _photoType = null;
        _removePhoto = widget.room?.photoPath != null;
        _fit = RoomImageFit.centered;
      });

  void _restoreDefault() => setState(() {
        _imageKey = null;
        _photo = null;
        _photoType = null;
        _removePhoto = widget.room?.photoPath != null;
        _fit = RoomImageFit.centered;
        _category = (RoomLibrary.categoryOfImage(RoomLibrary.defaultImageFor(_icon)) ?? RoomLibrary.categories.first).key;
      });

  Future<void> _pick(ImageSource source) async {
    final state = AppScope.read(context);
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
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
    } else if (mounted) {
      setState(() {
        _photo = bytes;
        _photoType = type;
        _removePhoto = false;
        _fit = RoomImageFit.centered;
      });
    }
  }

  Future<void> _save() async {
    final state = AppScope.read(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      state.notify(state.tr('validation.nameRequired'), error: true);
      return;
    }
    setState(() => _saving = true);
    var room = widget.room;
    var ok = true;
    if (room == null) {
      ok = await state.run(() async {
        room = await state.backend.createRoom(state.home!.id, name, _icon, state.rooms.length);
      });
    }
    if (ok && room != null) {
      ok = await state.saveRoom(
        room!,
        name: name,
        icon: _icon,
        imageKey: _imageKey,
        fit: _fit,
        photo: _photo,
        photoType: _photoType,
        removePhoto: _removePhoto,
      );
    }
    if (ok) await state.refreshHome(silent: true);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final state = AppScope.read(context);
    final room = widget.room!;
    final ok = await confirmDialog(context,
        title: context.tr('room.deleteTitle', {'name': room.name}), message: context.tr('room.deleteMessage'), destructive: true, confirmLabel: context.tr('common.delete'));
    if (!ok || !mounted) return;
    if (await state.run(() => state.backend.deleteRoom(room.id))) {
      await state.refreshHome(silent: true);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final theme = Theme.of(context);
    final state = AppScope.of(context);
    final draft = _draft;
    final devices = widget.room == null ? <Device>[] : state.devicesInRoom(widget.room!.id);
    final selectedKey = _showsPhoto ? null : draft.libraryImage;
    final category = RoomLibrary.category(_category) ?? RoomLibrary.categories.first;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(context.tr(widget.room == null ? 'room.add' : 'room.edit')),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(context.tr('common.save')),
            ),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
        // ---------------------------------------------------------- Aperçu
        Text(context.tr('roomEditor.preview'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: AspectRatio(
              aspectRatio: .95,
              child: LayoutBuilder(
                builder: (context, c) => GestureDetector(
                  key: const ValueKey('room-preview'),
                  onScaleStart: (d) {
                    _gestureStart = _fit;
                    _gestureOrigin = d.localFocalPoint;
                  },
                  onScaleUpdate: (d) {
                    final start = _gestureStart;
                    if (start == null) return;
                    final zoom = (start.zoom * d.scale).clamp(1.0, 3.0);
                    final delta = d.localFocalPoint - _gestureOrigin;
                    // Glisser vers la droite montre la partie gauche de l'image.
                    setState(() => _fit = start.copyWith(
                          zoom: zoom,
                          x: start.x - delta.dx * 2 / (c.maxWidth * zoom),
                          y: start.y - delta.dy * 2 / (c.maxHeight * zoom),
                        ));
                  },
                  onScaleEnd: (_) => _gestureStart = null,
                  child: _PreviewCard(
                    room: draft,
                    devices: devices,
                    photo: _photo,
                    ignorePhotoPath: _removePhoto,
                    imageKey: _showsPhoto ? null : draft.libraryImage,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(context.tr('roomEditor.adjustHelp'), textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft)),
        Row(children: [
          Icon(Icons.zoom_out_rounded, color: f.inkSoft),
          Expanded(
            child: Slider(
              value: _fit.zoom,
              min: 1,
              max: 3,
              label: context.tr('roomEditor.zoom'),
              onChanged: (v) => setState(() => _fit = _fit.copyWith(zoom: v)),
            ),
          ),
          Icon(Icons.zoom_in_rounded, color: f.inkSoft),
          IconButton(
            tooltip: context.tr('roomEditor.recenter'),
            onPressed: _fit == RoomImageFit.centered ? null : () => setState(() => _fit = RoomImageFit.centered),
            icon: const Icon(Icons.center_focus_strong_rounded),
          ),
        ]),

        // ---------------------------------------------------------- Nom et icône
        const SizedBox(height: 12),
        GlassPanel(
          radius: 22,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _name,
              autofocus: widget.room == null,
              decoration: InputDecoration(labelText: context.tr('common.name')),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in roomIcons.entries)
                ChoiceChip(
                  label: Icon(e.value, size: 20, semanticLabel: e.key),
                  selected: _icon == e.key,
                  onSelected: (_) => setState(() => _icon = e.key),
                ),
            ]),
          ]),
        ),

        // ---------------------------------------------------------- Sources d'image
        const SizedBox(height: 20),
        Text(context.tr('roomEditor.image'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: () => _pick(ImageSource.gallery), icon: const Icon(Icons.photo_library_rounded), label: Text(context.tr('photo.pick'))),
          OutlinedButton.icon(onPressed: () => _pick(ImageSource.camera), icon: const Icon(Icons.photo_camera_rounded), label: Text(context.tr('photo.take'))),
          OutlinedButton.icon(
            onPressed: draft.hasCustomImage || _photo != null ? _restoreDefault : null,
            icon: const Icon(Icons.restart_alt_rounded),
            label: Text(context.tr('roomEditor.restore')),
          ),
        ]),

        // ---------------------------------------------------------- Bibliothèque
        const SizedBox(height: 18),
        Text(context.tr('roomEditor.library'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: RoomLibrary.categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = RoomLibrary.categories[i];
              return ChoiceChip(
                avatar: Icon(c.icon, size: 18),
                label: Text(context.tr(c.labelKey)),
                selected: c.key == _category,
                onSelected: (_) => setState(() => _category = c.key),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1,
          children: [
            for (final key in RoomLibrary.imagesOf(category))
              _LibraryTile(
                key: ValueKey('lib-$key'),
                imageKey: key,
                selected: key == selectedKey,
                onTap: () => _chooseLibrary(key),
              ),
          ],
        ),

        if (widget.room != null) ...[
          const SizedBox(height: 28),
          Center(
            child: TextButton.icon(
              onPressed: _saving ? null : _delete,
              icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
              label: Text(context.tr('common.delete'), style: TextStyle(color: theme.colorScheme.error)),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Aperçu fidèle de la carte, avec l'image en cours de modification.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.room, required this.devices, this.photo, this.ignorePhotoPath = false, this.imageKey});

  final Room room;
  final List<Device> devices;
  final Uint8List? photo;
  final bool ignorePhotoPath;
  final String? imageKey;

  @override
  Widget build(BuildContext context) => RoomPhotoCard(
        room: room,
        devices: devices,
        title: room.name.isEmpty ? context.tr('common.name') : room.name,
        image: RoomImage(room: room, photo: photo, ignorePhotoPath: ignorePhotoPath, imageKey: imageKey),
      );
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({super.key, required this.imageKey, required this.selected, required this.onTap});

  final String imageKey;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    return Semantics(
      selected: selected,
      button: true,
      label: imageKey,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? f.brand : Colors.white.withValues(alpha: .25), width: selected ? 3 : 1.2),
            boxShadow: selected ? [BoxShadow(color: f.brand.withValues(alpha: .45), blurRadius: 14)] : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(selected ? 13 : 15),
            child: Stack(fit: StackFit.expand, children: [
              LibraryImage(imageKey),
              if (selected)
                Positioned(
                  top: 6,
                  right: 6,
                  child: CircleAvatar(radius: 11, backgroundColor: f.brand, child: const Icon(Icons.check_rounded, size: 15, color: Colors.white)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
