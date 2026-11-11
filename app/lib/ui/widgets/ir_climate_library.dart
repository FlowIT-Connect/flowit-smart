import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import 'common.dart';
import 'device_controls.dart' show optionLabel;
import 'ir_remote.dart' show irDeviceLabel;

/// Télécommandes de clim prêtes à l'emploi (comme la bibliothèque de l'app Broadlink) :
/// on choisit la marque, on essaie les télécommandes, et la clim a tous ses modes, ses
/// températures et ses vitesses sans rien apprendre. Codes : bibliothèque libre SmartIR,
/// téléchargés par la passerelle de la box.

class IrClimateProfile {
  const IrClimateProfile({required this.id, required this.brand, required this.models, required this.modes, required this.fans, required this.min, required this.max});

  factory IrClimateProfile.fromJson(Map<String, dynamic> j) => IrClimateProfile(
    id: j['id'] as int,
    brand: j['brand'] as String,
    models: [for (final m in (j['models'] as List? ?? const [])) m.toString()],
    modes: [for (final m in (j['modes'] as List? ?? const [])) m.toString()],
    fans: [for (final m in (j['fans'] as List? ?? const [])) m.toString()],
    min: j['min'] as num? ?? 16,
    max: j['max'] as num? ?? 30,
  );

  final int id;
  final String brand;
  final List<String> models;
  final List<String> modes;
  final List<String> fans;
  final num min;
  final num max;

  String get model => models.isEmpty ? '#$id' : models.join(', ');
}

List<IrClimateProfile>? _cache;

Future<List<IrClimateProfile>> loadIrClimateProfiles([AssetBundle? bundle]) async {
  if (_cache != null) return _cache!;
  final raw = jsonDecode(await (bundle ?? rootBundle).loadString('assets/ir/climate_index.json')) as List;
  return _cache = [for (final j in raw) IrClimateProfile.fromJson(j as Map<String, dynamic>)];
}

/// Télécommandes de la bibliothèque déjà choisies : { appareil : id }.
Map<String, int> chosenProfiles(Capability cap) {
  final raw = cap.metadata['profiles'];
  if (raw is! Map) return {};
  return {for (final e in raw.entries) if (e.value is num) e.key.toString(): (e.value as num).toInt()};
}

/// Carte de la fiche du Broadlink.
class IrClimateLibraryCard extends StatelessWidget {
  const IrClimateLibraryCard({super.key, required this.device, required this.cap, required this.enabled});

  final Device device;
  final Capability cap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final chosen = chosenProfiles(cap);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const TileIcon(Icons.ac_unit_rounded),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('irlib.title'), style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    if (chosen.isEmpty)
                      Text(context.tr('irlib.subtitle'), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.flow.inkSoft))
                    else
                      FutureBuilder<List<IrClimateProfile>>(
                        future: loadIrClimateProfiles(DefaultAssetBundle.of(context)),
                        builder: (context, snap) {
                          final byId = {for (final p in snap.data ?? const <IrClimateProfile>[]) p.id: p};
                          final text = chosen.entries.map((e) {
                            final p = byId[e.value];
                            return context.tr('irlib.current', {'name': irDeviceLabel(context, e.key), 'model': p == null ? '#${e.value}' : '${p.brand} ${p.model}'});
                          }).join(' · ');
                          return Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.flow.inkSoft));
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: enabled
                ? () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => IrClimateLibrarySheet(device: device, cap: cap),
                  )
                : null,
            icon: const Icon(Icons.search_rounded),
            label: Text(context.tr(chosen.isEmpty ? 'irlib.choose' : 'irlib.change')),
          ),
        ],
      ),
    );
  }
}

/// Choix guidé : marque → télécommandes de la marque → essai (froid 24°) → « Oui, garder ».
class IrClimateLibrarySheet extends StatefulWidget {
  const IrClimateLibrarySheet({super.key, required this.device, required this.cap, this.target = 'clim'});

  final Device device;
  final Capability cap;

  /// Appareil Solea créé ou complété (« clim » : la fiche Clim existante).
  final String target;

  @override
  State<IrClimateLibrarySheet> createState() => _IrClimateLibrarySheetState();
}

class _IrClimateLibrarySheetState extends State<IrClimateLibrarySheet> {
  List<IrClimateProfile>? _all = _cache;
  String _query = '';
  String? _brand;
  int? _tested; // télécommande essayée, réponse attendue
  bool _busy = false;
  String? _message;
  bool _error = false;
  late Map<String, int> _chosen = chosenProfiles(widget.cap);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_all != null) return;
    loadIrClimateProfiles(DefaultAssetBundle.of(context)).then((v) {
      if (mounted) setState(() => _all = v);
    });
  }

  Future<bool> _send(Map<String, dynamic> value, String busyText) async {
    setState(() {
      _busy = true;
      _error = false;
      _message = busyText;
    });
    final r = await AppScope.of(context).sendCommandAndWait(widget.device, 'ir_learn', value);
    if (!mounted) return false;
    final ok = r?.status == CommandStatus.confirmed;
    setState(() {
      _busy = false;
      _error = !ok;
      _message = ok ? null : (r?.error ?? context.tr('irlib.failed'));
    });
    return ok;
  }

  Future<void> _try(IrClimateProfile p) async {
    if (await _send({'action': 'profile_test', 'profile': p.id}, context.tr('irlib.trying'))) setState(() => _tested = p.id);
  }

  Future<void> _keep(IrClimateProfile p) async {
    final ok = await _send({'action': 'profile_set', 'device': widget.target, 'profile': p.id}, context.tr('irlib.saving'));
    if (!ok || !mounted) return;
    setState(() {
      _chosen = {..._chosen, widget.target: p.id};
      _tested = null;
      _message = context.tr('irlib.saved');
    });
  }

  Future<void> _remove() async {
    final ok = await _send({'action': 'profile_clear', 'device': widget.target}, context.tr('irlib.saving'));
    if (!ok || !mounted) return;
    setState(() {
      _chosen = {..._chosen}..remove(widget.target);
      _message = context.tr('irlib.removed');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final all = _all;
    final current = _chosen[widget.target];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        maxChildSize: .95,
        builder: (context, scroll) => Column(
          children: [
            Expanded(
              child: all == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      children: [
                        Row(
                          children: [
                            if (_brand != null)
                              IconButton(
                                tooltip: context.tr('irlib.brands'),
                                onPressed: _busy ? null : () => setState(() => _brand = null),
                                icon: const Icon(Icons.arrow_back_rounded),
                              ),
                            Expanded(child: Text(_brand ?? context.tr('irlib.title'), style: theme.textTheme.titleLarge)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(context.tr(_brand == null ? 'irlib.help' : 'irlib.unknown'), style: theme.textTheme.bodyMedium?.copyWith(color: context.flow.inkSoft)),
                        const SizedBox(height: 12),
                        if (_brand == null) ..._brands(context, all) else ..._profiles(context, all.where((p) => p.brand == _brand), current),
                        const SizedBox(height: 12),
                        Text(context.tr('irlib.source'), style: theme.textTheme.bodySmall?.copyWith(color: context.flow.inkSoft)),
                      ],
                    ),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (_error ? theme.colorScheme.error : context.flow.brand).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      if (_busy)
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                      else
                        Icon(_error ? Icons.error_outline_rounded : Icons.check_circle_rounded, color: _error ? theme.colorScheme.error : context.flow.brand),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_message!)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _brands(BuildContext context, List<IrClimateProfile> all) {
    final counts = <String, int>{};
    for (final p in all) {
      counts[p.brand] = (counts[p.brand] ?? 0) + 1;
    }
    final q = _query.trim().toLowerCase();
    final brands = counts.keys.where((b) => q.isEmpty || b.toLowerCase().contains(q)).toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return [
      TextField(
        decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: context.tr('irlib.search'), isDense: true),
        onChanged: (v) => setState(() => _query = v),
      ),
      const SizedBox(height: 8),
      for (final b in brands)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(b),
          subtitle: Text(context.tr('irlib.count', {'n': '${counts[b]}'})),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => setState(() {
            _brand = b;
            _tested = null;
            _message = null;
          }),
        ),
    ];
  }

  List<Widget> _profiles(BuildContext context, Iterable<IrClimateProfile> list, int? current) {
    final theme = Theme.of(context);
    final items = list.toList();
    return [
      for (final (i, p) in items.indexed)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(p.model, style: theme.textTheme.titleSmall)),
                    if (current == p.id) Icon(Icons.check_circle_rounded, color: context.flow.brand),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    p.modes.map((m) => optionLabel(context, m)).join(', '),
                    '${p.min.round()}–${p.max.round()}°',
                    if (p.fans.isNotEmpty) context.tr('irlib.fans', {'n': '${p.fans.length}'}),
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(color: context.flow.inkSoft),
                ),
                const SizedBox(height: 10),
                if (_tested == p.id) ...[
                  Text(context.tr('irlib.question'), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  FilledButton.icon(onPressed: _busy ? null : () => _keep(p), icon: const Icon(Icons.check_rounded), label: Text(context.tr('irlib.yes'))),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  // On éteint la clim avant de passer à la télécommande suivante.
                                  await _send({'action': 'profile_test', 'profile': p.id, 'mode': 'off'}, context.tr('irlib.off'));
                                  if (!mounted) return;
                                  setState(() => _tested = null);
                                  if (i + 1 < items.length) await _try(items[i + 1]);
                                },
                          child: Text(context.tr('irlib.no')),
                        ),
                      ),
                    ],
                  ),
                ] else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(onPressed: _busy ? null : () => _try(p), icon: const Icon(Icons.play_arrow_rounded), label: Text(context.tr('irlib.try'))),
                      ),
                      if (current == p.id) ...[
                        const SizedBox(width: 8),
                        TextButton(onPressed: _busy ? null : _remove, child: Text(context.tr('irlib.remove'))),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ),
    ];
  }
}
