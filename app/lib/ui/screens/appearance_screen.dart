import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/appearance.dart';
import '../../core/glass.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import 'device_detail.dart' show photoContentType;

/// Apparence : thèmes, arrière-plans (bibliothèque ou photo), flou, luminosité
/// et transparence des cartes, avec aperçu avant d'enregistrer.
class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  late Appearance _look = AppearanceController.instance.value;
  Uint8List? _photo = AppearanceController.instance.photoBytes;
  Uint8List? _newPhoto;
  String? _newPhotoType;
  late String _category = (_look.libraryKey == null ? null : BackgroundLibrary.categoryOfImage(_look.libraryKey!))?.key ?? BackgroundLibrary.categories.first.key;
  bool _saving = false;

  void _update(Appearance a) => setState(() => _look = a);

  Future<void> _pickPhoto() async {
    final state = AppScope.read(context);
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1440, maxHeight: 2560, imageQuality: 82);
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
        _newPhoto = bytes;
        _newPhotoType = type;
        // Chemin provisoire pour l'aperçu ; le vrai est donné à l'enregistrement.
        _look = _look.copyWith(background: 'photo:local');
      });
    }
  }

  Future<void> _save() async {
    final state = AppScope.read(context);
    setState(() => _saving = true);
    final usesNewPhoto = _look.photoPath == 'local';
    final ok = await state.saveAppearance(_look, photo: usesNewPhoto ? _newPhoto : null, photoType: usesNewPhoto ? _newPhotoType : null);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = BackgroundLibrary.categories.firstWhere((c) => c.key == _category);
    // L'aperçu est peint avec les couleurs du thème choisi.
    final colors = _look.colors(_look.forcedMode == ThemeMode.light || (_look.forcedMode == null && theme.brightness == Brightness.light) ? Brightness.light : Brightness.dark);

    Widget title(String key) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: Text(context.tr(key), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        );

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(context.tr('appearance.screen')),
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
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
        Center(child: _Preview(look: _look, colors: colors, photo: _photo)),

        // ------------------------------------------------------------ Thèmes
        title('appearance.themes'),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: appThemes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final t = appThemes[i];
              return _ThemeSwatch(
                key: ValueKey('theme-$t'),
                look: _look.copyWith(theme: t),
                label: context.tr('appearance.theme.$t'),
                selected: _look.theme == t,
                onTap: () => _update(_look.copyWith(theme: t)),
              );
            },
          ),
        ),
        if (_look.theme == 'custom') ...[
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final c in customAccents)
              GestureDetector(
                onTap: () => _update(_look.copyWith(accent: c)),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: _look.accent.toARGB32() == c.toARGB32() ? 3 : 0),
                    boxShadow: [BoxShadow(color: c.withValues(alpha: .5), blurRadius: 8)],
                  ),
                ),
              ),
          ]),
        ],

        // ------------------------------------------------------------ Arrière-plan
        title('appearance.background'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(
            avatar: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: Text(context.tr('appearance.bgDefault')),
            selected: _look.background == null,
            onSelected: (_) => _update(_look.copyWith(clearBackground: true)),
          ),
          ActionChip(
            avatar: const Icon(Icons.photo_library_rounded, size: 18),
            label: Text(context.tr('appearance.bgPhoto')),
            onPressed: _pickPhoto,
          ),
        ]),
        const SizedBox(height: 10),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: BackgroundLibrary.categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = BackgroundLibrary.categories[i];
              return ChoiceChip(
                avatar: Icon(c.icon, size: 18),
                label: Text(context.tr(c.labelKey)),
                selected: c.key == _category,
                onSelected: (_) => setState(() => _category = c.key),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 9 / 14,
          children: [
            for (final key in BackgroundLibrary.imagesOf(category))
              _BackgroundTile(
                key: ValueKey('bg-$key'),
                imageKey: key,
                selected: _look.libraryKey == key,
                onTap: () => _update(_look.copyWith(background: 'lib:$key')),
              ),
          ],
        ),

        // ------------------------------------------------------------ Réglages
        title('appearance.adjust'),
        _SliderRow(
          icon: Icons.blur_on_rounded,
          label: context.tr('appearance.blur'),
          value: _look.blur,
          min: 0,
          max: 40,
          enabled: _look.background != null,
          onChanged: (v) => _update(_look.copyWith(blur: v)),
        ),
        _SliderRow(
          icon: Icons.brightness_6_rounded,
          label: context.tr('appearance.brightness'),
          value: _look.brightness,
          min: -.6,
          max: .3,
          enabled: _look.background != null,
          onChanged: (v) => _update(_look.copyWith(brightness: v)),
        ),
        _SliderRow(
          icon: Icons.opacity_rounded,
          label: context.tr('appearance.glass'),
          value: _look.glassOpacity,
          min: .4,
          max: 1.8,
          onChanged: (v) => _update(_look.copyWith(glassOpacity: v)),
        ),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            key: const ValueKey('appearance-reset'),
            onPressed: _look.isDefault
                ? null
                : () => setState(() {
                      _look = Appearance.defaults;
                      _newPhoto = null;
                      _newPhotoType = null;
                    }),
            icon: const Icon(Icons.restart_alt_rounded),
            label: Text(context.tr('appearance.reset')),
          ),
        ),
      ]),
    );
  }
}

/// Mini accueil peint avec les réglages en cours.
class _Preview extends StatelessWidget {
  const _Preview({required this.look, required this.colors, this.photo});

  final Appearance look;
  final FlowColors colors;
  final Uint8List? photo;

  @override
  Widget build(BuildContext context) {
    final brightness = colors.ink.computeLuminance() > .5 ? Brightness.dark : Brightness.light;
    return Theme(
      data: AppTheme.from(colors, brightness),
      child: Builder(builder: (context) {
        final f = context.flow;
        Widget card(IconData icon, String label, {bool on = false}) => Expanded(
              child: Container(
                height: 70,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: on ? f.tileOn : f.glass,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: f.glassBorder),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, size: 20, color: on ? f.amber : f.inkSoft),
                  const Spacer(),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: f.ink, fontWeight: FontWeight.w800, fontSize: 12)),
                ]),
              ),
            );
        return ClipRRect(
          key: const ValueKey('appearance-preview'),
          borderRadius: BorderRadius.circular(26),
          child: SizedBox(
            width: 220,
            height: 300,
            child: Stack(fit: StackFit.expand, children: [
              ColoredBox(color: f.backdrop),
              if (look.background == null)
                ...[for (var i = 0; i < 3; i++) Positioned(left: const [-30.0, 120.0, 10.0][i], top: const [-20.0, 90.0, 200.0][i], child: _Blob(color: f.blobs[i]))]
              else
                BackgroundView(appearance: look, photo: photo),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  Row(children: [
                    Icon(Icons.wb_sunny_rounded, color: f.brand, size: 22),
                    const SizedBox(width: 6),
                    Text('Solea', style: TextStyle(color: f.ink, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 12),
                  GlassPanel(
                    radius: 18,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      Icon(Icons.home_rounded, color: f.blue, size: 20),
                      Icon(Icons.verified_user_rounded, color: f.success, size: 20),
                      Icon(Icons.thermostat_rounded, color: f.violet, size: 20),
                      Icon(Icons.water_drop_rounded, color: f.cyan, size: 20),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [card(Icons.lightbulb_rounded, 'Plafonnier', on: true), const SizedBox(width: 8), card(Icons.power_rounded, 'Prise')]),
                  const SizedBox(height: 8),
                  Row(children: [card(Icons.blinds_rounded, 'Volet'), const SizedBox(width: 8), card(Icons.thermostat_rounded, '21 °C')]),
                  const Spacer(),
                  Container(
                    height: 34,
                    decoration: BoxDecoration(color: f.navBar, borderRadius: BorderRadius.circular(999), border: Border.all(color: f.glassBorder)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                        decoration: BoxDecoration(color: f.brand, borderRadius: BorderRadius.circular(999)),
                        child: Icon(Icons.home_rounded, size: 18, color: f.onBrand),
                      ),
                      Icon(Icons.meeting_room_rounded, size: 18, color: f.inkSoft),
                      Icon(Icons.lightbulb_outline_rounded, size: 18, color: f.inkSoft),
                      Icon(Icons.settings_rounded, size: 18, color: f.inkSoft),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: .8), boxShadow: [BoxShadow(color: color, blurRadius: 60, spreadRadius: 10)]),
      );
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({super.key, required this.look, required this.label, required this.selected, required this.onTap});

  final Appearance look;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final c = look.colors(look.forcedMode == ThemeMode.light ? Brightness.light : (look.theme == 'solea' ? Theme.of(context).brightness : Brightness.dark));
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 78,
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 62,
              height: 54,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.blobs[0], c.backdrop, c.blobs[2]]),
                border: Border.all(color: selected ? f.brand : Colors.white.withValues(alpha: .3), width: selected ? 3 : 1),
              ),
              child: Center(child: Icon(Icons.wb_sunny_rounded, color: c.brand, size: 22)),
            ),
            const SizedBox(height: 6),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: f.ink)),
          ]),
        ),
      ),
    );
  }
}

class _BackgroundTile extends StatelessWidget {
  const _BackgroundTile({super.key, required this.imageKey, required this.selected, required this.onTap});

  final String imageKey;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final asset = BackgroundLibrary.assetFor(imageKey);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? f.brand : Colors.white.withValues(alpha: .25), width: selected ? 3 : 1.2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(selected ? 13 : 15),
          child: asset == null ? BackgroundArt(imageKey) : Image.asset(asset, fit: BoxFit.cover, cacheWidth: 300, errorBuilder: (_, _, _) => BackgroundArt(imageKey)),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({required this.icon, required this.label, required this.value, required this.min, required this.max, required this.onChanged, this.enabled = true});

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    return Row(children: [
      Icon(icon, color: enabled ? f.inkSoft : f.inkFaint),
      const SizedBox(width: 10),
      SizedBox(width: 110, child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: enabled ? f.ink : f.inkFaint))),
      Expanded(child: Slider(value: value.clamp(min, max), min: min, max: max, onChanged: enabled ? onChanged : null)),
    ]);
  }
}
