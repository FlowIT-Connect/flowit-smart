import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/icons.dart';
import '../../core/l10n.dart';
import '../../core/room_library.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';

/// Image d'une pièce : photo personnelle > image de la bibliothèque (photo livrée
/// ou illustration de secours), avec le cadrage choisi.
///
/// Les paramètres [imageKey], [photo] et [fit] servent à l'aperçu de l'éditeur
/// (valeurs pas encore enregistrées).
class RoomImage extends StatelessWidget {
  const RoomImage({super.key, required this.room, this.imageKey, this.photo, this.fit, this.ignorePhotoPath = false});

  final Room room;
  final String? imageKey;
  final Uint8List? photo;
  final RoomImageFit? fit;

  /// Aperçu : la photo enregistrée a été retirée.
  final bool ignorePhotoPath;

  @override
  Widget build(BuildContext context) {
    final f = fit ?? room.imageFit;
    final Widget content;
    if (photo != null) {
      content = Image.memory(photo!, fit: BoxFit.cover, alignment: f.alignment, gaplessPlayback: true);
    } else if (room.photoPath != null && !ignorePhotoPath) {
      content = _StoredPhoto(path: room.photoPath!, fallbackKey: imageKey ?? room.libraryImage, fit: f);
    } else {
      content = LibraryImage(imageKey ?? room.libraryImage, alignment: f.alignment);
    }
    return ClipRect(
      child: Transform.scale(
        scale: f.zoom,
        alignment: f.alignment,
        child: SizedBox.expand(child: content),
      ),
    );
  }
}

class _StoredPhoto extends StatelessWidget {
  const _StoredPhoto({required this.path, required this.fallbackKey, required this.fit});

  final String path;
  final String fallbackKey;
  final RoomImageFit fit;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return FutureBuilder<Uint8List?>(
      future: state.roomPhoto(path),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes != null) return Image.memory(bytes, fit: BoxFit.cover, alignment: fit.alignment, gaplessPlayback: true);
        // Pendant le chargement (ou si la photo est illisible) : l'image de la bibliothèque.
        return LibraryImage(fallbackKey, alignment: fit.alignment);
      },
    );
  }
}

/// Image de la bibliothèque Solea : la photo livrée si elle existe, sinon une
/// illustration peinte aux couleurs de la catégorie.
class LibraryImage extends StatelessWidget {
  const LibraryImage(this.imageKey, {super.key, this.alignment = Alignment.center});

  final String imageKey;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final asset = RoomLibrary.assetFor(imageKey);
    final illustration = RoomIllustration(imageKey);
    if (asset == null) return illustration;
    return Image.asset(
      asset,
      fit: BoxFit.cover,
      alignment: alignment,
      cacheWidth: 900,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => illustration,
    );
  }
}

/// Illustration de secours : dégradé de la catégorie, lumière de fenêtre, sol et
/// grande icône estompée. Chaque variante (1, 2, 3) a sa propre composition.
class RoomIllustration extends StatelessWidget {
  const RoomIllustration(this.imageKey, {super.key});

  final String imageKey;

  @override
  Widget build(BuildContext context) {
    final cat = RoomLibrary.categoryOfImage(imageKey) ?? RoomLibrary.categories.first;
    final variant = RoomLibrary.variantOf(imageKey);
    return CustomPaint(
      painter: _IllustrationPainter(cat.colors, variant),
      child: LayoutBuilder(
        builder: (context, c) => Align(
          alignment: switch (variant % 3) { 1 => const Alignment(.45, .25), 2 => const Alignment(-.45, .3), _ => const Alignment(0, .2) },
          child: Icon(cat.icon, size: math.min(c.maxWidth, c.maxHeight) * .42, color: Colors.white.withValues(alpha: .26)),
        ),
      ),
    );
  }
}

class _IllustrationPainter extends CustomPainter {
  _IllustrationPainter(this.colors, this.variant);

  final List<Color> colors;
  final int variant;

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    final angle = [0.0, .35, -.35][variant % 3];
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(-1 + angle, -1),
          end: Alignment(1 - angle, 1),
          colors: colors,
          stops: const [0, .55, 1],
        ).createShader(rect),
    );
    // Fenêtre lumineuse.
    final wx = [.18, .62, .40][variant % 3] * s.width;
    final window = Rect.fromLTWH(wx, s.height * .12, s.width * .26, s.height * .42);
    canvas.drawRRect(
      RRect.fromRectAndRadius(window, Radius.circular(s.width * .02)),
      Paint()..color = Colors.white.withValues(alpha: .22),
    );
    canvas.drawLine(window.topCenter, window.bottomCenter, Paint()..color = colors.last.withValues(alpha: .25)..strokeWidth = s.width * .008);
    // Halo de lumière.
    canvas.drawCircle(
      window.center,
      s.width * .45,
      Paint()
        ..color = Colors.white.withValues(alpha: .18)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.width * .18),
    );
    // Sol.
    final floor = Path()
      ..moveTo(0, s.height * .72)
      ..lineTo(s.width, s.height * .66)
      ..lineTo(s.width, s.height)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(floor, Paint()..color = Colors.black.withValues(alpha: .22));
  }

  @override
  bool shouldRepaint(covariant _IllustrationPainter old) => old.colors != colors || old.variant != variant;
}

/// Carte de pièce façon « Mes Pièces » : photo, pastille de connexion, bandeau de
/// verre avec l'icône, le nom et les familles d'appareils (icône + nombre).
class RoomPhotoCard extends StatelessWidget {
  const RoomPhotoCard({super.key, required this.room, required this.devices, this.onTap, this.title, this.icon, this.image});

  /// null : appareils sans pièce.
  final Room? room;
  final List<Device> devices;
  final VoidCallback? onTap;
  final String? title;
  final IconData? icon;

  /// Image imposée (aperçu de l'éditeur).
  final Widget? image;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final r = room;
    final name = title ?? r?.name ?? context.tr('room.none');
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: f.shadow, blurRadius: 26, offset: const Offset(0, 10), spreadRadius: -6)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Stack(fit: StackFit.expand, children: [
              image ?? (r != null ? RoomImage(room: r) : RoomIllustration(RoomLibrary.defaultImageFor('other'))),
              Positioned(top: 10, right: 10, child: RoomStatusPill(devices: devices)),
              Positioned(left: 0, right: 0, bottom: 0, child: _GlassBand(name: name, icon: icon ?? roomIcon(r?.icon), devices: devices)),
              // Filet clair du verre sur le bord de la carte.
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: Colors.white.withValues(alpha: .28), width: 1.2),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Pastille « En ligne » / « n hors ligne » (masquée pour une pièce vide).
class RoomStatusPill extends StatelessWidget {
  const RoomStatusPill({super.key, required this.devices});

  final List<Device> devices;

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) return const SizedBox.shrink();
    final f = context.flow;
    final offline = devices.where((d) => d.availability == Availability.unavailable).length;
    final ok = offline == 0;
    final label = ok ? context.tr('room.online') : context.tr('room.offlineCount', {'n': offline});
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .32),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: .22)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ok ? f.success : f.warning,
                boxShadow: [BoxShadow(color: (ok ? f.success : f.warning).withValues(alpha: .7), blurRadius: 6)],
              ),
            ),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}

/// Familles d'appareils d'une pièce : icône, nombre, et s'il y en a d'allumés.
List<({DeviceKind kind, IconData icon, int count, bool lit})> deviceGroups(List<Device> devices) {
  final byKind = <DeviceKind, List<Device>>{};
  for (final d in devices) {
    byKind.putIfAbsent(deviceKind(d), () => []).add(d);
  }
  final groups = [
    for (final e in byKind.entries)
      (
        kind: e.key,
        icon: deviceIcon(e.value.first),
        count: e.value.length,
        lit: e.value.any((d) => d.isOnline && d.isOn == true),
      ),
  ];
  groups.sort((a, b) => b.count.compareTo(a.count));
  return groups;
}

class _GlassBand extends StatelessWidget {
  const _GlassBand({required this.name, required this.icon, required this.devices});

  final String name;
  final IconData icon;
  final List<Device> devices;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final groups = deviceGroups(devices);
    const white = Colors.white;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 8, 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: .26), Colors.black.withValues(alpha: .42)],
            ),
            border: Border(top: BorderSide(color: white.withValues(alpha: .18))),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(icon, color: white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: white, fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: groups.isEmpty
                    ? Text(context.tr('room.noDevicesShort'), style: TextStyle(color: white.withValues(alpha: .75), fontSize: 12, fontWeight: FontWeight.w600))
                    : ClipRect(
                        child: Wrap(spacing: 10, runSpacing: 4, clipBehavior: Clip.hardEdge, children: [
                          for (final g in groups.take(3))
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(g.icon, size: 17, color: g.lit ? f.amber : white.withValues(alpha: .9), shadows: g.lit ? [Shadow(color: f.amber, blurRadius: 10)] : null),
                              const SizedBox(width: 3),
                              Text('${g.count}', style: const TextStyle(color: white, fontSize: 13, fontWeight: FontWeight.w700)),
                            ]),
                        ]),
                      ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(shape: BoxShape.circle, color: white.withValues(alpha: .16), border: Border.all(color: white.withValues(alpha: .25))),
                child: Icon(Directionality.of(context) == TextDirection.rtl ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded, size: 16, color: white),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Grille de cartes de pièces (2 colonnes sur téléphone, plus sur grand écran).
class RoomCardGrid extends StatelessWidget {
  const RoomCardGrid({super.key, required this.children, this.padding = const EdgeInsets.symmetric(horizontal: 16)});

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: padding,
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: .95,
          ),
          delegate: SliverChildListDelegate(children),
        ),
      );
}
