import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';

/// Image en direct d'une caméra (rafraîchie environ chaque seconde par la passerelle).
///
/// Le flux n'existe que tant que cet écran est ouvert : à la fermeture, la passerelle
/// cesse d'envoyer des images.
class CameraLiveView extends StatefulWidget {
  const CameraLiveView({super.key, required this.device, this.fullscreen = false});

  final Device device;
  final bool fullscreen;

  @override
  State<CameraLiveView> createState() => _CameraLiveViewState();
}

class _CameraLiveViewState extends State<CameraLiveView> {
  StreamSubscription<CameraFrame>? _sub;
  Timer? _tick;
  CameraFrame? _frame;
  DateTime? _receivedAt;
  late DateTime _openedAt;

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    final state = AppScope.read(context);
    _sub = state.backend.watchCamera(widget.device.homeId, widget.device.id).listen((frame) {
      if (!mounted) return;
      setState(() {
        _frame = frame;
        _receivedAt = DateTime.now();
      });
    });
    // Met à jour « en direct » / « image figée » même sans nouvelle image.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = context.flow;
    final frame = _frame;
    final now = DateTime.now();
    final fresh = frame != null && frame.live && _receivedAt != null && now.difference(_receivedAt!) < const Duration(seconds: 6);
    final waitedLong = now.difference(_openedAt) > const Duration(seconds: 12);
    const white = Colors.white;

    final Widget body;
    if (frame != null) {
      body = Image.memory(frame.bytes, fit: BoxFit.contain, gaplessPlayback: true, filterQuality: FilterQuality.medium);
    } else {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!waitedLong) const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: white)),
            if (waitedLong) Icon(Icons.videocam_off_rounded, color: white.withValues(alpha: .8), size: 34),
            const SizedBox(height: 12),
            Text(
              context.tr(waitedLong ? 'camera.noImage' : 'camera.connecting'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: white.withValues(alpha: .85), height: 1.4),
            ),
          ]),
        ),
      );
    }

    final view = ColoredBox(
      color: const Color(0xFF14110F),
      child: Stack(fit: StackFit.expand, children: [
        widget.fullscreen ? InteractiveViewer(maxScale: 5, child: body) : body,
        PositionedDirectional(
          top: 10,
          start: 10,
          child: _Badge(
            color: fresh ? f.danger : Colors.black.withValues(alpha: .55),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: fresh ? white : white.withValues(alpha: .5), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(context.tr(fresh ? 'camera.live' : (frame == null ? 'camera.waiting' : 'camera.frozen')),
                  style: theme.textTheme.labelSmall?.copyWith(color: white, fontWeight: FontWeight.w800, letterSpacing: .6)),
            ]),
          ),
        ),
        if (frame != null)
          PositionedDirectional(
            bottom: 10,
            end: 10,
            child: _Badge(
              color: Colors.black.withValues(alpha: .55),
              child: Text(_hms(frame.at), style: theme.textTheme.labelSmall?.copyWith(color: white, fontFeatures: const [FontFeature.tabularFigures()])),
            ),
          ),
        if (!widget.fullscreen)
          PositionedDirectional(
            top: 4,
            end: 4,
            child: IconButton(
              tooltip: context.tr('camera.fullscreen'),
              icon: const Icon(Icons.fullscreen_rounded, color: white),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => _CameraFullscreen(device: widget.device),
              )),
            ),
          ),
      ]),
    );

    if (widget.fullscreen) return view;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: AspectRatio(aspectRatio: 16 / 9, child: view),
      ),
    );
  }

  static String _hms(DateTime t) => [t.hour, t.minute, t.second].map((v) => v.toString().padLeft(2, '0')).join(':');
}

class _Badge extends StatelessWidget {
  const _Badge({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
        child: child,
      );
}

class _CameraFullscreen extends StatelessWidget {
  const _CameraFullscreen({required this.device});

  final Device device;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF14110F),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          title: Text(device.name),
        ),
        body: SafeArea(child: CameraLiveView(device: device, fullscreen: true)),
      );
}
