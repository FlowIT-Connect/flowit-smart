import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/hvac_catalog.dart';
import '../../core/icons.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import '../widgets/device_controls.dart';

/// Solea HVAC Connect : type d'équipement → marque → modèle → voie de connexion → test.
///
/// Le test demande à la passerelle de repérer le nouvel appareil (comme un ajout Smart Life),
/// puis affiche les commandes qu'il expose réellement.
class HvacConnectScreen extends StatefulWidget {
  const HvacConnectScreen({super.key});

  @override
  State<HvacConnectScreen> createState() => _HvacConnectScreenState();
}

enum _Test { idle, waiting, done, failed }

class _HvacConnectScreenState extends State<HvacConnectScreen> {
  final _search = TextEditingController();
  final _model = TextEditingController();
  final _name = TextEditingController();
  HvacType? _type;
  HvacBrand? _brand;
  bool _otherBrand = false;
  bool? _hasWifi;
  HvacRoute? _route;
  String? _roomId;
  _Test _test = _Test.idle;
  String? _error;
  String? _deviceId;
  int _attempt = 0;

  @override
  void dispose() {
    _search.dispose();
    _model.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _brandChosen => _brand != null || _otherBrand;

  void _reset({bool type = false, bool brand = false, bool wifi = false}) {
    _attempt++;
    setState(() {
      if (type) _type = null;
      if (type || brand) {
        _brand = null;
        _otherBrand = false;
        _search.clear();
      }
      if (type || brand || wifi) _hasWifi = null;
      _route = null;
      _test = _Test.idle;
      _error = null;
      _deviceId = null;
    });
  }

  String _defaultName(BuildContext context) {
    final kind = context.tr('hvac.type.${_type!.name}');
    final brand = _brand?.name;
    return [kind, ?brand].join(' ');
  }

  Future<void> _runTest(AppState state) async {
    final attempt = ++_attempt;
    final name = _name.text.trim().isEmpty ? _defaultName(context) : _name.text.trim();
    final id = await state.requestPairing(kind: 'scan', name: name, roomId: _roomId);
    if (id == null || !mounted) return;
    setState(() {
      _test = _Test.waiting;
      _error = null;
    });
    if (routeUsesSmartLife(_route!) && state.launcher.available) {
      unawaited(state.launcher.openTuyaApp().then((app) {
        if (app == null) state.notify(state.tr('pair.tuya.noApp'), error: true);
      }));
    }
    final result = await state.waitPairing(id, timeout: const Duration(minutes: 6));
    if (!mounted || attempt != _attempt) return;
    setState(() {
      if (result?.status == 'done') {
        _test = _Test.done;
        _deviceId = result!.deviceId;
      } else {
        _test = _Test.failed;
        _error = result?.status == 'failed' ? result!.error : state.tr('pair.bridgeSlow');
      }
    });
  }

  Map<String, Object> _params(BuildContext context) => {
        'brand': _brand?.name ?? context.tr('hvac.brand.yours'),
        'app': _brand?.app ?? context.tr('hvac.brand.app'),
        'ha': _brand?.haIntegration ?? _brand?.app ?? '—',
        'source': context.tr((_brand?.officialHa ?? false) ? 'hvac.ha.official' : 'hvac.ha.community'),
        'bus': _brand?.bus ?? 'eBUS / EMS',
      };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('hvac.title'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            ..._typeStep(context),
            if (_type != null) ..._brandStep(context),
            if (_brandChosen) ..._modelStep(context),
            if (_hasWifi != null) ..._routeStep(context),
            if (_route != null) ..._testStep(context, state),
          ]),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 1. Type
  List<Widget> _typeStep(BuildContext context) {
    final f = context.flow;
    if (_type != null) {
      return [_Chosen(step: 1, label: context.tr('hvac.type.${_type!.name}'), icon: _typeIcon(_type!), onEdit: _test == _Test.waiting ? null : () => _reset(type: true))];
    }
    return [
      Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(context.tr('hvac.intro'))),
      SectionHeader(context.tr('hvac.step.type')),
      for (final t in HvacType.values)
        Card(
          child: ListTile(
            leading: TileIcon(_typeIcon(t), color: t == HvacType.airConditioner ? f.blue : f.orange),
            title: Text(context.tr('hvac.type.${t.name}')),
            subtitle: Text(context.tr('hvac.type.${t.name}.help')),
            trailing: const ForwardChevron(),
            onTap: () => setState(() => _type = t),
          ),
        ),
    ];
  }

  // ---------------------------------------------------------------- 2. Marque
  List<Widget> _brandStep(BuildContext context) {
    if (_brandChosen) {
      return [
        _Chosen(
          step: 2,
          label: _brand?.name ?? context.tr('hvac.brand.other'),
          sub: _brand?.origin,
          icon: Icons.factory_rounded,
          onEdit: _test == _Test.waiting ? null : () => _reset(brand: true),
        ),
      ];
    }
    final brands = brandsFor(_type!, query: _search.text);
    return [
      SectionHeader(context.tr('hvac.step.brand')),
      TextField(
        controller: _search,
        decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: context.tr('hvac.brand.search')),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 8),
      for (final b in brands)
        ListTile(
          title: Text(b.name),
          subtitle: Text([?b.origin, if (b.algeria) context.tr('hvac.brand.algeria')].join(' · ')),
          trailing: const ForwardChevron(),
          onTap: () => setState(() => _brand = b),
        ),
      ListTile(
        leading: const Icon(Icons.add_circle_outline_rounded),
        title: Text(context.tr('hvac.brand.other')),
        subtitle: Text(context.tr('hvac.brand.otherHelp')),
        onTap: () => setState(() => _otherBrand = true),
      ),
    ];
  }

  // ---------------------------------------------------------------- 3. Modèle et Wi-Fi
  List<Widget> _modelStep(BuildContext context) {
    final app = _brand?.app;
    if (_hasWifi != null) {
      return [
        _Chosen(
          step: 3,
          label: context.tr(_hasWifi! ? 'hvac.wifi.yes' : 'hvac.wifi.no'),
          sub: _model.text.trim().isEmpty ? null : _model.text.trim(),
          icon: _hasWifi! ? Icons.wifi_rounded : Icons.settings_remote_rounded,
          onEdit: _test == _Test.waiting ? null : () => _reset(wifi: true),
        ),
      ];
    }
    return [
      SectionHeader(context.tr('hvac.step.model')),
      TextField(
        controller: _model,
        maxLength: 60,
        decoration: InputDecoration(labelText: context.tr('hvac.model'), helperText: context.tr('hvac.model.help')),
      ),
      const SizedBox(height: 8),
      Text(context.tr(_type == HvacType.thermostat ? 'hvac.wifi.questionThermostat' : 'hvac.wifi.question'), style: Theme.of(context).textTheme.titleSmall),
      if (app != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(context.tr('hvac.wifi.app', {'app': app}))),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.tonalIcon(onPressed: () => setState(() => _hasWifi = true), icon: const Icon(Icons.wifi_rounded), label: Text(context.tr('hvac.wifi.yes'))),
        FilledButton.tonalIcon(onPressed: () => setState(() => _hasWifi = false), icon: const Icon(Icons.wifi_off_rounded), label: Text(context.tr('hvac.wifi.no'))),
      ]),
    ];
  }

  // ---------------------------------------------------------------- 4. Voie de connexion
  List<Widget> _routeStep(BuildContext context) {
    final routes = routesFor(_type!, _brand, hasWifi: _hasWifi!);
    if (_route != null) {
      return [
        _Chosen(step: 4, label: context.tr('hvac.route.${_route!.name}', _params(context)), icon: _routeIcon(_route!), onEdit: _test == _Test.waiting ? null : () => _reset()),
      ];
    }
    return [
      SectionHeader(context.tr('hvac.step.route')),
      for (final (i, r) in routes.indexed)
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: TileIcon(_routeIcon(r), color: i == 0 ? context.flow.brand : context.flow.inkSoft),
            title: Text(context.tr('hvac.route.${r.name}', _params(context))),
            subtitle: Text([
              if (i == 0) context.tr('hvac.recommended'),
              context.tr('hvac.route.${r.name}.does', _params(context)),
              if (routeNeedsInstaller(r)) context.tr('hvac.installer'),
            ].join('\n')),
            isThreeLine: true,
            trailing: const ForwardChevron(),
            onTap: () => setState(() => _route = r),
          ),
        ),
      if (_type == HvacType.boiler) _Note(icon: Icons.health_and_safety_rounded, text: context.tr('hvac.boilerSafety')),
      _Note(icon: Icons.info_outline_rounded, text: context.tr('hvac.modelVaries')),
    ];
  }

  // ---------------------------------------------------------------- 5. Mise en place et test
  List<Widget> _testStep(BuildContext context, AppState state) {
    final r = _route!;
    final params = _params(context);
    if (_test == _Test.done) return _result(context, state);
    final f = context.flow;
    return [
      SectionHeader(context.tr('hvac.step.setup')),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(context.tr('hvac.route.${r.name}.steps', params), style: const TextStyle(height: 1.5)),
        ),
      ),
      const SizedBox(height: 12),
      TextField(controller: _name, enabled: _test != _Test.waiting, maxLength: 60, decoration: InputDecoration(labelText: context.tr('pair.name'), hintText: _defaultName(context))),
      DropdownButtonFormField<String?>(
        initialValue: _roomId,
        isExpanded: true,
        decoration: InputDecoration(labelText: context.tr('pair.room')),
        items: [
          DropdownMenuItem(value: null, child: Text(context.tr('room.none'))),
          for (final room in state.rooms) DropdownMenuItem(value: room.id, child: Text(room.name, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: _test == _Test.waiting ? null : (v) => setState(() => _roomId = v),
      ),
      const SizedBox(height: 16),
      if (_test == _Test.idle || _test == _Test.failed)
        FilledButton.icon(
          onPressed: (state.plan?.isFull ?? false) ? null : () => _runTest(state),
          icon: const Icon(Icons.wifi_tethering_rounded),
          label: Text(context.tr('hvac.test')),
        ),
      if (_test == _Test.waiting) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 14),
            Expanded(child: Text(context.tr('hvac.testing'))),
          ]),
        ),
        TextButton(onPressed: () => _reset(), child: Text(context.tr('common.cancel'))),
      ],
      if (_test == _Test.failed) ...[
        const SizedBox(height: 12),
        _Note(icon: Icons.error_outline_rounded, color: f.danger, text: [context.tr('pair.failed'), ?_error].join('\n')),
      ],
    ];
  }

  List<Widget> _result(BuildContext context, AppState state) {
    final device = state.devices[_deviceId];
    final caps = device?.capabilities ?? const [];
    return [
      const SizedBox(height: 16),
      _Note(
        icon: Icons.check_circle_rounded,
        color: context.flow.success,
        text: context.tr('pair.done', {'name': device?.name ?? _defaultName(context)}),
      ),
      SectionHeader(context.tr('hvac.commands')),
      if (caps.isEmpty) Text(context.tr('hvac.commands.none')),
      for (final c in caps)
        ListTile(
          dense: true,
          leading: Icon(capabilityIcon(c.key)),
          title: Text(capabilityLabel(context, c.key)),
          subtitle: c.options.isEmpty ? null : Text(c.options.map((o) => optionLabel(context, o)).join(' · ')),
          trailing: Icon(c.writable ? Icons.tune_rounded : Icons.visibility_rounded, size: 18),
        ),
      const SizedBox(height: 16),
      FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(context.tr('pair.finish'))),
    ];
  }
}

IconData _typeIcon(HvacType t) => switch (t) {
      HvacType.airConditioner => Icons.ac_unit_rounded,
      HvacType.boiler => Icons.local_fire_department_rounded,
      HvacType.thermostat => Icons.thermostat_rounded,
    };

IconData _routeIcon(HvacRoute r) => switch (r) {
      HvacRoute.tuyaWifi => Icons.wifi_rounded,
      HvacRoute.infrared => Icons.settings_remote_rounded,
      HvacRoute.homeAssistant => Icons.home_work_rounded,
      HvacRoute.roomThermostat => Icons.thermostat_auto_rounded,
      HvacRoute.openTherm => Icons.cable_rounded,
      HvacRoute.boilerBus => Icons.settings_input_component_rounded,
      HvacRoute.modbus => Icons.lan_rounded,
    };

/// Étape déjà choisie : rappel compact avec « Modifier ».
class _Chosen extends StatelessWidget {
  const _Chosen({required this.step, required this.label, required this.icon, this.sub, this.onEdit});

  final int step;
  final String label;
  final String? sub;
  final IconData icon;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: TileIcon(icon),
        title: Text(label),
        subtitle: sub == null ? null : Text(sub!),
        trailing: TextButton(onPressed: onEdit, child: Text(context.tr('common.edit'))),
      );
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color ?? context.flow.blue),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ]),
        ),
      );
}
