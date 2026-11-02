import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/device_qr.dart';
import '../../../core/l10n.dart';
import '../../../core/theme.dart';

/// Scanne le QR code de l'étiquette d'une caméra et renvoie son contenu lu ([DeviceQr]).
///
/// Si la caméra du téléphone n'est pas disponible (ordinateur, autorisation refusée), le texte
/// du QR peut être collé à la main.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode], detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;
  String? _unknown;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final qr = DeviceQr.parse(b.rawValue);
      if (qr != null) {
        _done = true;
        Navigator.of(context).pop(qr);
        return;
      }
    }
    if (capture.barcodes.isNotEmpty && mounted) setState(() => _unknown = context.tr('qr.unknown'));
  }

  Future<void> _typeIt() async {
    final text = TextEditingController();
    final qr = await showDialog<DeviceQr>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(ctx.tr('qr.typeTitle')),
            content: TextField(
              controller: text,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(hintText: '{SN:…,DT:…,SC:…}', errorText: error),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(ctx.tr('common.cancel'))),
              FilledButton(
                onPressed: () {
                  final parsed = DeviceQr.parse(text.text);
                  if (parsed == null) {
                    setLocal(() => error = ctx.tr('qr.unknown'));
                  } else {
                    Navigator.of(ctx).pop(parsed);
                  }
                },
                child: Text(ctx.tr('qr.use')),
              ),
            ],
          ),
        );
      },
    );
    text.dispose();
    if (qr != null && mounted) Navigator.of(context).pop(qr);
  }

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(context.tr('qr.title')), backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Stack(fit: StackFit.expand, children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (ctx, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(ctx.tr('qr.noCamera'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            ),
          ),
        ),
        // Cadre de visée
        IgnorePointer(
          child: Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(border: Border.all(color: f.brand, width: 3), borderRadius: BorderRadius.circular(24)),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              _unknown ?? context.tr('qr.help'),
              textAlign: TextAlign.center,
              style: TextStyle(color: _unknown == null ? Colors.white : f.warning, fontWeight: FontWeight.w600, height: 1.35),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
              onPressed: _typeIt,
              icon: const Icon(Icons.keyboard_rounded),
              label: Text(context.tr('qr.type')),
            ),
          ]),
        ),
      ]),
    );
  }
}
