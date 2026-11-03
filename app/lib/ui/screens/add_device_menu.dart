import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/qr/qr_recognition.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'add_device_screen.dart';
import 'brand_library_screen.dart';
import 'device_scanner_screen.dart';
import 'qr_device_flow_screen.dart';
import 'security/add_video_device_screen.dart';

/// « + Ajouter un appareil » : scanner un QR code, recherche à proximité, ajout manuel ou
/// bibliothèque des marques (menu en verre dépoli).
Future<void> showAddDeviceMenu(BuildContext context) async {
  final state = AppScope.read(context);
  // Logement équipé par l'installateur : l'écran d'ajout explique la marche à suivre.
  if (state.plan?.managed ?? false) {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AddDeviceScreen()));
    return;
  }
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: true,
    builder: (ctx) => const _AddMenu(),
  );
  if (choice == null || !context.mounted) return;
  final nav = Navigator.of(context);
  switch (choice) {
    case 'scan':
      final result = await nav.push<QrRecognition>(MaterialPageRoute(builder: (_) => const DeviceScannerScreen()));
      if (result != null && context.mounted) {
        await nav.push(MaterialPageRoute(builder: (_) => QrDeviceFlowScreen(recognition: result)));
      }
    case 'nearby':
      await showNearbySearch(context);
    case 'manual':
      await nav.push(MaterialPageRoute(builder: (_) => const AddDeviceScreen()));
    case 'brands':
      await nav.push(MaterialPageRoute(builder: (_) => const BrandLibraryScreen()));
  }
}

class _AddMenu extends StatelessWidget {
  const _AddMenu();

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    Widget option(String value, IconData icon, Color color, String title, String help) => ListTile(
          key: ValueKey('add-menu-$value'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          leading: TileIcon(icon, color: color),
          title: Text(context.tr(title), style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(context.tr(help)),
          trailing: const ForwardChevron(),
          onTap: () => Navigator.of(context).pop(value),
        );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: GlassPanel(
            radius: 28,
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: f.line, borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: Row(children: [
                  Icon(Icons.add_circle_rounded, color: f.brand),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(context.tr('add.menu.title'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                ]),
              ),
              option('scan', Icons.qr_code_scanner_rounded, f.brand, 'add.menu.scan', 'add.menu.scanHelp'),
              option('nearby', Icons.radar_rounded, f.blue, 'add.menu.nearby', 'add.menu.nearbyHelp'),
              option('manual', Icons.edit_note_rounded, f.violet, 'add.menu.manual', 'add.menu.manualHelp'),
              option('brands', Icons.menu_book_rounded, f.orange, 'add.menu.brands', 'add.menu.brandsHelp'),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Recherche automatique : seules les recherches réellement faites par Solea sont proposées.
Future<void> showNearbySearch(BuildContext context) async {
  final f = context.flow;
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: GlassPanel(
          radius: 28,
          padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Text(ctx.tr('add.nearby.title'), style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(ctx.tr('add.nearby.help'), style: TextStyle(color: f.inkSoft)),
            ),
            for (final (value, icon, color) in [
              ('lock', Icons.bluetooth_searching_rounded, f.violet),
              ('camera', Icons.videocam_rounded, f.blue),
              ('tuya', Icons.wifi_find_rounded, f.brand),
            ])
              ListTile(
                key: ValueKey('nearby-$value'),
                leading: TileIcon(icon, color: color),
                title: Text(ctx.tr('add.nearby.$value')),
                subtitle: Text(ctx.tr('add.nearby.${value}Help')),
                trailing: const ForwardChevron(),
                onTap: () => Navigator.of(ctx).pop(value),
              ),
          ]),
        ),
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  final nav = Navigator.of(context);
  await nav.push(MaterialPageRoute(
    builder: (_) => switch (choice) {
      'camera' => const AddVideoDeviceScreen(),
      'lock' => const AddDeviceScreen(initialKind: 'lock'),
      _ => const AddDeviceScreen(initialKind: 'tuya'),
    },
  ));
}
