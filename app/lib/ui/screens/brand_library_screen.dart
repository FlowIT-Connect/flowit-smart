import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/qr/brand_catalog.dart';
import '../../core/qr/qr_recognition.dart';
import '../../core/theme.dart';
import '../widgets/common.dart';
import 'qr_device_flow_screen.dart';

/// Bibliothèque des marques : ce que Solea sait faire avec chacune, puis le bon parcours.
class BrandLibraryScreen extends StatefulWidget {
  const BrandLibraryScreen({super.key});

  @override
  State<BrandLibraryScreen> createState() => _BrandLibraryScreenState();
}

class _BrandLibraryScreenState extends State<BrandLibraryScreen> {
  String _query = '';

  void _open(Brand b) {
    // Même parcours qu'après un scan, avec la marque choisie à la main.
    final r = QrRecognition(raw: '', redactedPayload: 'brand:${b.id}', type: QrCodeType.proprietary, parser: 'library', brand: b);
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => QrDeviceFlowScreen(recognition: r)));
  }

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final brands = BrandCatalog.search(_query);
    final groups = <BrandSupport, List<Brand>>{
      for (final s in BrandSupport.values) s: [for (final b in brands) if (b.support == s) b],
    };
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('add.menu.brands'))),
      body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            key: const ValueKey('brand-search'),
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: context.tr('brand.search')),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Text(context.tr('brand.help'), style: TextStyle(color: f.inkSoft)),
        ),
        for (final s in BrandSupport.values)
          if (groups[s]!.isNotEmpty)
            SettingsGroup(title: context.tr('brand.support.${s.name}'), children: [
              for (final b in groups[s]!)
                ListTile(
                  key: ValueKey('brand-${b.id}'),
                  leading: TileIcon(_icon(b), color: s == BrandSupport.supported ? f.brand : (s == BrandSupport.homeAssistant ? f.blue : f.inkSoft)),
                  title: Text(b.name),
                  subtitle: Text(context.tr('qrflow.route.${b.route.name}')),
                  trailing: const ForwardChevron(),
                  onTap: () => _open(b),
                ),
            ]),
        if (brands.isEmpty) EmptyState(icon: Icons.search_off_rounded, title: context.tr('brand.none')),
      ]),
    );
  }

  static IconData _icon(Brand b) => switch (b.category) {
        'lock' => Icons.lock_outline_rounded,
        'camera' => Icons.videocam_outlined,
        'ac' => Icons.ac_unit_rounded,
        'light' => Icons.lightbulb_outline_rounded,
        _ => Icons.devices_other_rounded,
      };
}
