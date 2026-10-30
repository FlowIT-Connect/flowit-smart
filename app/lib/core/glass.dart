import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

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
