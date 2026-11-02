import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'appearance.dart';
import 'theme.dart';

/// Glassmorphism Solea : fond de lumières floutées et panneaux de verre dépoli.

/// Fond d'ambiance : taches de lumière chaudes et très floues, comme une photo
/// d'intérieur au coucher du soleil vue à travers un verre dépoli. Peint une
/// seule fois par écran ; un fond imbriqué ne repeint rien.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (context.dependOnInheritedWidgetOfExactType<_AmbientScope>() != null) return child;
    final f = context.flow;
    return _AmbientScope(
      child: Stack(children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(child: CustomPaint(painter: _BackdropPainter(f.backdrop, f.blobs))),
          ),
        ),
        // Arrière-plan choisi par l'utilisateur (bibliothèque ou photo), flouté.
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<Appearance>(
              valueListenable: AppearanceController.instance,
              builder: (context, look, _) => look.background == null
                  ? const SizedBox.shrink()
                  : RepaintBoundary(child: BackgroundView(appearance: look, photo: AppearanceController.instance.photoBytes)),
            ),
          ),
        ),
        Positioned.fill(child: child),
      ]),
    );
  }
}

class _AmbientScope extends InheritedWidget {
  const _AmbientScope({required super.child});

  @override
  bool updateShouldNotify(_AmbientScope oldWidget) => false;
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.base, this.blobs);

  final Color base;
  final List<Color> blobs;

  // Position (fraction de l'écran) et rayon (fraction du plus grand côté) de chaque tache.
  static const _spots = [
    (Offset(.12, .06), .42),
    (Offset(.92, .18), .40),
    (Offset(.20, .55), .38),
    (Offset(.88, .78), .42),
    (Offset(.15, .98), .36),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final unit = size.longestSide;
    for (var i = 0; i < _spots.length && i < blobs.length; i++) {
      final (pos, r) = _spots[i];
      final radius = unit * r;
      canvas.drawCircle(
        Offset(size.width * pos.dx, size.height * pos.dy),
        radius,
        Paint()
          ..color = blobs[i].withValues(alpha: .85)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * .45),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter old) => old.base != base || old.blobs != blobs;
}

/// Panneau de verre dépoli : floute ce qui est derrière, teinte translucide,
/// reflet en dégradé et filet clair sur le bord.
class GlassPanel extends StatelessWidget {
  const GlassPanel({super.key, required this.child, this.radius = 28, this.blur = 22, this.tint, this.padding});

  final Widget child;
  final double radius;
  final double blur;

  /// Teinte du verre (par défaut le verre neutre du thème).
  final Color? tint;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [BoxShadow(color: f.shadow, blurRadius: 30, offset: const Offset(0, 12), spreadRadius: -6)],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: shape,
              gradient: tint == null
                  ? f.glassGradient
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [tint!.withValues(alpha: (tint!.a + .12).clamp(0, 1)), tint!],
                    ),
              border: Border.all(color: f.glassBorder, width: 1.2),
            ),
            child: padding == null ? child : Padding(padding: padding!, child: child),
          ),
        ),
      ),
    );
  }
}

/// Transitions de page qui posent chaque écran sur le fond de verre, pour que
/// les pages ouvertes (pièce, réglages…) gardent la même ambiance que l'accueil.
class GlassPageTransitions extends PageTransitionsTheme {
  const GlassPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      super.buildTransitions(route, context, animation, secondaryAnimation, AmbientBackground(child: child));
}

/// Arrière-plan d'apparence : image (bibliothèque ou photo importée), flou et
/// luminosité réglables. Sert aussi à l'aperçu de l'écran Apparence.
class BackgroundView extends StatelessWidget {
  const BackgroundView({super.key, required this.appearance, this.photo});

  final Appearance appearance;
  final Uint8List? photo;

  @override
  Widget build(BuildContext context) {
    final a = appearance;
    final Widget image;
    if (a.photoPath != null && photo != null) {
      image = Image.memory(photo!, fit: BoxFit.cover, gaplessPlayback: true);
    } else {
      final key = a.libraryKey ?? 'abstrait_couleurs_1';
      final asset = BackgroundLibrary.assetFor(key);
      final fallback = BackgroundArt(key);
      image = asset == null ? fallback : Image.asset(asset, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => fallback);
    }
    final b = a.brightness;
    return Stack(fit: StackFit.expand, children: [
      ClipRect(
        child: a.blur <= 0
            ? image
            : ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: a.blur, sigmaY: a.blur, tileMode: TileMode.mirror), child: image),
      ),
      ColoredBox(color: b < 0 ? Colors.black.withValues(alpha: -b) : Colors.white.withValues(alpha: b)),
    ]);
  }
}

/// Dégradé de secours d'une image de la bibliothèque des arrière-plans.
class BackgroundArt extends StatelessWidget {
  const BackgroundArt(this.imageKey, {super.key});

  final String imageKey;

  @override
  Widget build(BuildContext context) {
    final cat = BackgroundLibrary.categoryOfImage(imageKey) ?? BackgroundLibrary.categories.first;
    final v = BackgroundLibrary.variantOf(imageKey);
    return CustomPaint(painter: _ArtPainter(cat.colors, v));
  }
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.colors, this.variant);

  final List<Color> colors;
  final int variant;

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    final shift = [0.0, .5, -.5][variant % 3];
    canvas.drawRect(
      rect,
      Paint()..shader = LinearGradient(begin: Alignment(-1, -1 + shift), end: Alignment(1, 1 - shift), colors: colors, stops: const [0, .5, 1]).createShader(rect),
    );
    final unit = s.longestSide;
    for (var i = 0; i < 3; i++) {
      final dx = [.2, .8, .5][(i + variant) % 3];
      final dy = [.25, .55, .85][i];
      canvas.drawCircle(
        Offset(s.width * dx, s.height * dy),
        unit * .22,
        Paint()
          ..color = colors[i % 2].withValues(alpha: .55)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * .12),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArtPainter old) => old.colors != colors || old.variant != variant;
}
