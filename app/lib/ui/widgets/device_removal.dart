import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import 'common.dart';

enum RemovalChoice { favorite, home, unlink }

/// Fenêtre de confirmation « Supprimer l'appareil » (verre dépoli).
///
/// [fromFavorites] : ouverte depuis les favoris, propose aussi de retirer seulement le favori.
/// Retirer / dissocier est réservé au propriétaire et à l'administrateur.
/// Renvoie true si quelque chose a été supprimé.
Future<bool> confirmDeviceRemoval(BuildContext context, Device device, {bool fromFavorites = false}) async {
  final state = AppScope.read(context);
  final canRemove = state.role.canManage;
  final canUnpin = fromFavorites && device.isPinned && state.role.canConfigureDevices;
  if (!canRemove && !canUnpin) {
    state.notify(state.tr('error.denied'), error: true);
    return false;
  }
  final choice = await showDialog<RemovalChoice>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .35),
    builder: (ctx) => _RemovalDialog(device: device, canUnpin: canUnpin, canRemove: canRemove),
  );
  if (choice == null || !context.mounted) return false;
  switch (choice) {
    case RemovalChoice.favorite:
      return state.updateDevice(device, isPinned: false);
    case RemovalChoice.home:
      return await state.removeDevice(device, unlink: false) != null;
    case RemovalChoice.unlink:
      return await state.removeDevice(device, unlink: true) != null;
  }
}

class _RemovalDialog extends StatefulWidget {
  const _RemovalDialog({required this.device, required this.canUnpin, required this.canRemove});

  final Device device;
  final bool canUnpin;
  final bool canRemove;

  @override
  State<_RemovalDialog> createState() => _RemovalDialogState();
}

class _RemovalDialogState extends State<_RemovalDialog> {
  late RemovalChoice _choice = widget.canUnpin ? RemovalChoice.favorite : RemovalChoice.home;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final theme = Theme.of(context);
    Widget option(RemovalChoice value, IconData icon, String title, String help, {bool danger = false}) {
      final selected = _choice == value;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: selected ? (danger ? f.dangerSoft : f.brandSoft) : f.chip.withValues(alpha: .6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: selected ? (danger ? f.danger : f.brand) : f.cardBorder, width: selected ? 1.6 : 1),
          ),
          child: InkWell(
            key: ValueKey('removal-${value.name}'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _choice = value),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, color: danger ? f.danger : f.brand),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.tr(title), style: TextStyle(fontWeight: FontWeight.w800, color: f.ink)),
                    const SizedBox(height: 2),
                    Text(context.tr(help), style: TextStyle(fontSize: 12.5, color: f.inkSoft, height: 1.3)),
                  ]),
                ),
                Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? (danger ? f.danger : f.brand) : f.inkFaint),
              ]),
            ),
          ),
        ),
      );
    }

    final destructive = _choice != RemovalChoice.favorite;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: GlassPanel(
          radius: 28,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: f.dangerSoft, shape: BoxShape.circle),
                  child: Icon(Icons.delete_outline_rounded, color: f.danger),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.tr('remove.title'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    Text(widget.device.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: f.inkSoft, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
              const SizedBox(height: 14),
              Text(context.tr('remove.question'), style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              if (widget.canUnpin) option(RemovalChoice.favorite, Icons.star_outline_rounded, 'remove.favorite', 'remove.favoriteHelp'),
              if (widget.canRemove) ...[
                option(RemovalChoice.home, Icons.home_outlined, 'remove.home', 'remove.homeHelp'),
                option(RemovalChoice.unlink, Icons.link_off_rounded, 'remove.unlink', 'remove.unlinkHelp', danger: true),
              ],
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(key: const ValueKey('removal-cancel'), onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('common.cancel'))),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('removal-confirm'),
                  style: destructive ? FilledButton.styleFrom(backgroundColor: f.danger, foregroundColor: Colors.white) : null,
                  onPressed: () => Navigator.of(context).pop(_choice),
                  child: Text(context.tr(destructive ? 'remove.confirm' : 'remove.favoriteConfirm')),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Appareils retirés du logement ou dissociés : les remettre / les autoriser de nouveau.
class RemovedDevicesScreen extends StatefulWidget {
  const RemovedDevicesScreen({super.key});

  @override
  State<RemovedDevicesScreen> createState() => _RemovedDevicesScreenState();
}

class _RemovedDevicesScreenState extends State<RemovedDevicesScreen> {
  List<RemovedDevice>? _removed;
  List<ExcludedDevice>? _excluded;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = AppScope.read(context);
    final results = await Future.wait([state.loadRemovedDevices(), state.loadExcludedDevices()]);
    if (!mounted) return;
    setState(() {
      _removed = results[0] as List<RemovedDevice>;
      _excluded = results[1] as List<ExcludedDevice>;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final f = context.flow;
    final removed = _removed;
    final excluded = _excluded;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('remove.listTitle'))),
      body: removed == null || excluded == null
          ? const Center(child: CircularProgressIndicator())
          : removed.isEmpty && excluded.isEmpty
              ? ListView(children: [EmptyState(icon: Icons.inventory_2_outlined, title: context.tr('remove.listEmpty'))])
              : ListView(padding: const EdgeInsets.only(bottom: 32), children: [
                  if (removed.isNotEmpty)
                    SettingsGroup(title: context.tr('remove.listRemoved'), children: [
                      for (final d in removed)
                        ListTile(
                          leading: TileIcon(Icons.home_outlined, color: f.blue),
                          title: Text(d.name),
                          subtitle: Text([if ((d.vendor ?? '').isNotEmpty) '${d.vendor} ${d.model ?? ''}'.trim(), relativeTime(context, d.removedAt)].join(' · ')),
                          trailing: TextButton(
                            onPressed: () async {
                              if (await state.restoreDevice(d)) await _load();
                            },
                            child: Text(context.tr('remove.restore')),
                          ),
                        ),
                    ]),
                  if (excluded.isNotEmpty)
                    SettingsGroup(title: context.tr('remove.listUnlinked'), children: [
                      for (final d in excluded)
                        ListTile(
                          leading: TileIcon(Icons.link_off_rounded, color: f.danger),
                          title: Text(d.name),
                          subtitle: Text(context.tr('remove.unlinkedHelp')),
                          trailing: TextButton(
                            onPressed: () async {
                              if (await state.allowExcludedDevice(d)) await _load();
                            },
                            child: Text(context.tr('remove.allow')),
                          ),
                        ),
                    ]),
                ]),
    );
  }
}
