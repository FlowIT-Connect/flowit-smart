import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/device_controls.dart';

enum _Filter { all, available, unavailable, hidden }

/// Inventaire des appareils avec recherche et filtres (§5.3).
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  _Filter _filter = _Filter.all;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final q = _query.toLowerCase();
    final source = _filter == _Filter.hidden ? state.devices.values.where((d) => d.isHidden).toList() : state.visibleDevices;
    final devices = source.where((d) {
      if (_filter == _Filter.available && !d.isOnline) return false;
      if (_filter == _Filter.unavailable && d.availability != Availability.unavailable) return false;
      if (q.isEmpty) return true;
      final room = state.roomById(d.roomId)?.name ?? '';
      return '${d.name} ${d.vendor ?? ''} ${d.model ?? ''} $room ${d.protocol}'.toLowerCase().contains(q);
    }).toList();

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: context.tr('device.search'),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            for (final f in _Filter.values)
              if (f != _Filter.hidden || state.role.canConfigureDevices)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: FilterChip(
                    label: Text(context.tr('device.filter.${f.name}')),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
          ]),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),
      if (devices.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: Icons.search_off_rounded,
            title: context.tr(state.devices.isEmpty ? 'device.emptyTitle' : 'device.noMatch'),
            message: state.devices.isEmpty ? context.tr('device.emptyHelp') : null,
          ),
        )
      else
        DeviceGrid(devices),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ]);
  }
}
