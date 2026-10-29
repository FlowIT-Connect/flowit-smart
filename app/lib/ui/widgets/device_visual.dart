import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/device_photos.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import 'common.dart';

/// Visuel d'un appareil : sa photo réelle quand elle existe, sinon son icône.
///
/// Ordre de priorité : photo prise par l'utilisateur, photo officielle du produit
/// (Tuya / Smart Life), photo du type d'appareil livrée avec l'application, icône.
class DeviceVisual extends StatelessWidget {
  const DeviceVisual(this.device, {super.key, required this.size, required this.photoSize, this.active = false});

  final Device device;

  /// Diamètre de l'icône de repli.
  final double size;

  /// Côté de la vignette photo.
  final double photoSize;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final d = device;
    final accent = deviceAccent(context, d);
    Widget icon() => IconBubble(icon: deviceIcon(d), color: d.isOnline ? accent : f.inkFaint, size: size, filled: active, glow: active);

    final Widget? photo;
    if (d.photoPath != null) {
      photo = _StoragePhoto(path: d.photoPath!, fallback: icon);
    } else if (d.imageUrl != null) {
      photo = Image.network(
        d.imageUrl!,
        fit: BoxFit.contain,
        // Sur le web, affiche l'image même si son serveur n'autorise pas CORS.
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        errorBuilder: (_, _, _) => _assetOrIcon(d, icon),
      );
    } else if (DevicePhotoCatalog.assetFor(d) != null) {
      photo = _assetOrIcon(d, icon);
    } else {
      photo = null;
    }
    if (photo == null) return icon();

    final radius = BorderRadius.circular(photoSize * .28);
    return Semantics(
      image: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: photoSize,
        height: photoSize,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: radius,
          border: Border.all(color: active ? accent.withValues(alpha: .7) : f.cardBorder, width: active ? 2 : 1),
          boxShadow: active ? [BoxShadow(color: accent.withValues(alpha: .35), blurRadius: photoSize * .4, spreadRadius: -photoSize * .08)] : null,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: ColorFiltered(
            // Hors ligne : photo en gris, comme l'icône.
            colorFilter: d.isOnline ? const ColorFilter.mode(Colors.transparent, BlendMode.dst) : const ColorFilter.matrix(_grey),
            child: photo,
          ),
        ),
      ),
    );
  }

  static Widget _assetOrIcon(Device d, Widget Function() icon) {
    final asset = DevicePhotoCatalog.assetFor(d);
    if (asset == null) return Center(child: icon());
    return Image.asset(asset, fit: BoxFit.cover, errorBuilder: (_, _, _) => Center(child: icon()));
  }
}

const _grey = <double>[
  .33, .33, .33, 0, 0, //
  .33, .33, .33, 0, 0, //
  .33, .33, .33, 0, 0, //
  0, 0, 0, .75, 0,
];

/// Photo d'un bucket privé, téléchargée une fois puis gardée en mémoire.
class _StoragePhoto extends StatelessWidget {
  const _StoragePhoto({required this.path, required this.fallback});

  final String path;
  final Widget Function() fallback;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
        future: AppScope.read(context).devicePhoto(path),
        builder: (context, snap) {
          final bytes = snap.data;
          if (bytes != null) {
            return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => Center(child: fallback()));
          }
          if (snap.connectionState == ConnectionState.done) return Center(child: fallback());
          return ColoredBox(color: context.flow.chip);
        },
      );
}
