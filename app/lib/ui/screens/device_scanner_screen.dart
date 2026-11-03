import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/glass.dart';
import '../../core/l10n.dart';
import '../../core/qr/qr_recognition.dart';
import '../../core/theme.dart';

/// Scanner de QR code d'appareil : caméra, cadre animé, lampe, image de la galerie, saisie.
/// Renvoie la [QrRecognition] du premier QR code lu (reconnu ou non : la suite décide).
class DeviceScannerScreen extends StatefulWidget {
  const DeviceScannerScreen({super.key, this.recognizer = const QrRecognizer()});

  final QrRecognizer recognizer;

  @override
  State<DeviceScannerScreen> createState() => _DeviceScannerScreenState();
}

class _DeviceScannerScreenState extends State<DeviceScannerScreen> with SingleTickerProviderStateMixin {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode], detectionSpeed: DetectionSpeed.noDuplicates);
  late final AnimationController _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  bool _done = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sweep.repeat(reverse: true);
  }

  @override
  void dispose() {
    _sweep.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _finish(String? raw) {
    if (_done || raw == null || raw.trim().isEmpty) return;
    _done = true;
    Navigator.of(context).pop(widget.recognizer.recognize(raw));
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      if ((b.rawValue ?? '').trim().isNotEmpty) {
        _finish(b.rawValue);
        return;
      }
    }
    if (capture.barcodes.isNotEmpty && mounted) setState(() => _error = context.tr('scanner.unreadable'));
  }

  Future<void> _fromImage() async {
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(source: ImageSource.gallery);
    } catch (_) {
      if (mounted) setState(() => _error = context.tr('scanner.imageError'));
      return;
    }
    if (file == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final capture = await _controller.analyzeImage(file.path, formats: const [BarcodeFormat.qrCode]);
      final raw = capture?.barcodes.map((b) => b.rawValue).whereType<String>().where((v) => v.trim().isNotEmpty).firstOrNull;
      if (raw == null) {
        if (mounted) setState(() => _error = context.tr('scanner.noQrInImage'));
      } else {
        _finish(raw);
      }
    } catch (_) {
      if (mounted) setState(() => _error = context.tr('scanner.imageError'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _typeIt() async {
    final text = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('scanner.typeTitle')),
        content: TextField(
          key: const ValueKey('scanner-type-field'),
          controller: text,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(hintText: ctx.tr('scanner.typeHint')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(ctx.tr('common.cancel'))),
          FilledButton(key: const ValueKey('scanner-type-ok'), onPressed: () => Navigator.of(ctx).pop(text.text), child: Text(ctx.tr('qr.use'))),
        ],
      ),
    );
    text.dispose();
    if (raw != null && raw.trim().isNotEmpty) {
      _finish(raw);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    const white = Colors.white;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(context.tr('scanner.title')),
        backgroundColor: Colors.black.withValues(alpha: .3),
        foregroundColor: white,
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, s, _) {
              if (s.torchState == TorchState.unavailable) return const SizedBox.shrink();
              final on = s.torchState == TorchState.on;
              return IconButton(
                key: const ValueKey('scanner-torch'),
                tooltip: context.tr(on ? 'scanner.torchOff' : 'scanner.torchOn'),
                icon: Icon(on ? Icons.flash_on_rounded : Icons.flash_off_rounded, color: on ? f.amber : white),
                onPressed: () => _controller.toggleTorch(),
              );
            },
          ),
        ],
      ),
      body: Stack(fit: StackFit.expand, children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (ctx, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.no_photography_outlined, color: white, size: 42),
                const SizedBox(height: 12),
                Text(
                  ctx.tr(error.errorCode == MobileScannerErrorCode.permissionDenied ? 'scanner.permission' : 'qr.noCamera'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: white, height: 1.35),
                ),
              ]),
            ),
          ),
        ),
        // Cadre de lecture animé.
        IgnorePointer(
          child: Center(
            child: SizedBox(
              width: 250,
              height: 250,
              child: AnimatedBuilder(
                animation: _sweep,
                builder: (context, _) => CustomPaint(painter: _FramePainter(color: f.brand, t: _sweep.value)),
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 20,
          child: SafeArea(
            top: false,
            child: GlassPanel(
              radius: 24,
              tint: Colors.black.withValues(alpha: .35),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    _error ?? context.tr('scanner.help'),
                    key: ValueKey(_error),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _error == null ? white : f.warning, fontWeight: FontWeight.w600, height: 1.35),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('scanner-gallery'),
                      style: OutlinedButton.styleFrom(foregroundColor: white, side: const BorderSide(color: Colors.white54)),
                      onPressed: _busy ? null : _fromImage,
                      icon: _busy
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: white))
                          : const Icon(Icons.photo_library_outlined),
                      label: Text(context.tr('scanner.gallery'), overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('scanner-type'),
                      style: OutlinedButton.styleFrom(foregroundColor: white, side: const BorderSide(color: Colors.white54)),
                      onPressed: _typeIt,
                      icon: const Icon(Icons.keyboard_rounded),
                      label: Text(context.tr('qr.type'), overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Coins arrondis du viseur et trait de balayage.
class _FramePainter extends CustomPainter {
  _FramePainter({required this.color, required this.t});

  final Color color;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const l = 38.0, r = 22.0;
    final w = size.width, h = size.height;
    for (final (dx, dy) in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)]) {
      final x = dx * w, y = dy * h;
      final sx = dx == 0 ? 1 : -1, sy = dy == 0 ? 1 : -1;
      final path = Path()
        ..moveTo(x, y + sy * l)
        ..lineTo(x, y + sy * r)
        ..arcToPoint(Offset(x + sx * r, y), radius: const Radius.circular(r), clockwise: sx * sy > 0)
        ..lineTo(x + sx * l, y);
      canvas.drawPath(path, p);
    }
    final y = 14 + (h - 28) * t;
    canvas.drawLine(
      Offset(18, y),
      Offset(w - 18, y),
      Paint()
        ..shader = LinearGradient(colors: [color.withValues(alpha: 0), color, color.withValues(alpha: 0)]).createShader(Rect.fromLTWH(0, y, w, 2))
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.t != t || old.color != color;
}
