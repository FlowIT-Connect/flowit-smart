import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/backend.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

/// Page « Appareils à attribuer » de l'exploitant Solea.
///
/// L'installateur couple les appareils dans son propre compte Smart Life / TTLock ; la
/// passerelle de la plateforme les liste ici et l'exploitant range chacun dans un logement.
/// Le résident ne voit que Solea.
class AdminDevicesScreen extends StatefulWidget {
  const AdminDevicesScreen({super.key});

  @override
  State<AdminDevicesScreen> createState() => _AdminDevicesScreenState();
}

class _AdminDevicesScreenState extends State<AdminDevicesScreen> {
  List<PlatformDevice>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = AppScope.read(context);
    try {
      final items = await state.backend.adminListPlatformDevices();
      if (mounted) {
        setState(() {
          _items = items;
          _error = null;
        });
      }
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _assign(PlatformDevice d) async {
    final home = await showModalBottomSheet<HomeSummary>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HomePicker(device: d),
    );
    if (home == null || !mounted) return;
    final state = AppScope.read(context);
    final ok = await state.run(
      () => state.backend.adminAssignDevice(d.externalId, home.id),
      success: state.tr('adminDevices.assigned', {'device': d.name, 'home': home.name}),
    );
    if (ok) await _load();
  }

  Future<void> _unassign(PlatformDevice d) async {
    final state = AppScope.read(context);
    final sure = await confirmDialog(context,
        title: state.tr('adminDevices.unassign'),
        message: state.tr('adminDevices.unassignConfirm', {'device': d.name, 'home': d.homeName ?? '—'}),
        destructive: true,
        confirmLabel: state.tr('adminDevices.unassign'));
    if (!sure || !mounted) return;
    if (await state.run(() => state.backend.adminAssignDevice(d.externalId, null))) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final todo = items?.where((d) => !d.isAssigned).toList() ?? const [];
    final done = items?.where((d) => d.isAssigned).toList() ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('adminDevices.title')),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: context.tr('common.retry'))],
      ),
      body: _error != null
          ? ErrorState(message: _error!, onRetry: _load)
          : items == null
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? EmptyState(icon: Icons.devices_other_rounded, title: context.tr('adminDevices.empty'), message: context.tr('adminDevices.emptyHelp'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                        SectionHeader(context.tr('adminDevices.todo', {'n': todo.length})),
                        if (todo.isEmpty)
                          Padding(padding: const EdgeInsets.all(8), child: Text(context.tr('adminDevices.todoNone'), style: TextStyle(color: context.flow.inkSoft))),
                        for (final d in todo) _DeviceTile(device: d, onTap: () => _assign(d)),
                        if (done.isNotEmpty) ...[
                          SectionHeader(context.tr('adminDevices.done', {'n': done.length})),
                          for (final d in done) _DeviceTile(device: d, onTap: () => _assign(d), onRemove: () => _unassign(d)),
                        ],
                      ]),
                    ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.onTap, this.onRemove});

  final PlatformDevice device;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final d = device;
    final f = context.flow;
    final subtitle = d.isAssigned
        ? '${d.homeName ?? '—'} · ${context.tr(d.installed ? 'adminDevices.installed' : 'adminDevices.installing')}'
        : [if (d.vendor != null) d.vendor!, if (d.model != null) d.model!].join(' · ');
    return Card(
      child: ListTile(
        leading: TileIcon(d.isAssigned ? Icons.home_rounded : Icons.add_home_rounded, color: d.isAssigned ? f.brand : f.orange),
        title: Text(d.name),
        subtitle: subtitle.isEmpty ? null : Text(subtitle),
        trailing: onRemove == null
            ? FilledButton.tonal(onPressed: onTap, child: Text(context.tr('adminDevices.assign')))
            : PopupMenuButton<String>(
                onSelected: (v) => v == 'move' ? onTap() : onRemove!(),
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'move', child: Text(context.tr('adminDevices.move'))),
                  PopupMenuItem(value: 'remove', child: Text(context.tr('adminDevices.unassign'))),
                ],
              ),
        onTap: onRemove == null ? onTap : null,
      ),
    );
  }
}

/// Choix du logement : recherche par nom ou par e-mail du résident.
class _HomePicker extends StatefulWidget {
  const _HomePicker({required this.device});

  final PlatformDevice device;

  @override
  State<_HomePicker> createState() => _HomePickerState();
}

class _HomePickerState extends State<_HomePicker> {
  final _query = TextEditingController();
  List<HomeSummary>? _homes;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final state = AppScope.read(context);
    try {
      final homes = await state.backend.adminSearchHomes(_query.text);
      if (mounted) setState(() => _homes = homes);
    } on BackendException catch (e) {
      state.notify(e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final homes = _homes;
    final f = context.flow;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(context.tr('adminDevices.pickTitle', {'device': widget.device.name}), style: Theme.of(context).textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _query,
              autofocus: true,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: context.tr('adminDevices.search')),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), _search);
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: homes == null
                ? const Center(child: CircularProgressIndicator())
                : homes.isEmpty
                    ? Center(child: Text(context.tr('adminDevices.noHome'), style: TextStyle(color: f.inkSoft)))
                    : ListView(children: [
                        for (final h in homes)
                          ListTile(
                            leading: const TileIcon(Icons.apartment_rounded),
                            title: Text(h.name),
                            subtitle: Text([if (h.ownerEmail != null) h.ownerEmail!, context.tr('plan.count', {'n': h.deviceCount, 'limit': h.deviceLimit})].join(' · ')),
                            trailing: h.isFull ? Text(context.tr('adminDevices.full'), style: TextStyle(color: f.orange, fontWeight: FontWeight.w700)) : null,
                            enabled: !h.isFull,
                            onTap: () => Navigator.pop(context, h),
                          ),
                      ]),
          ),
        ]),
      ),
    );
  }
}
