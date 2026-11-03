import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/qr/brand_catalog.dart';
import '../../core/qr/qr_recognition.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import 'add_device_screen.dart';
import 'device_detail.dart';
import 'hvac_connect_screen.dart';
import 'rooms_screen.dart';
import 'security/add_video_device_screen.dart';

enum _Phase { review, connecting, added }

/// Parcours après la lecture d'un QR code :
/// 1 QR lu → 2 marque et modèle → 3 fiche → 4 compatibilité → 5 méthode de connexion →
/// 6 logement et pièce → 7 nom → 8 test de connexion → 9 confirmation.
///
/// « Connecté » n'est affiché que si la passerelle a réellement joint l'appareil.
class QrDeviceFlowScreen extends StatefulWidget {
  const QrDeviceFlowScreen({super.key, required this.recognition});

  final QrRecognition recognition;

  @override
  State<QrDeviceFlowScreen> createState() => _QrDeviceFlowScreenState();
}

class _QrDeviceFlowScreenState extends State<QrDeviceFlowScreen> {
  final _name = TextEditingController();
  String? _roomId;
  String? _scanId;
  _Phase _phase = _Phase.review;
  String? _deviceId;
  bool _pendingBox = false;
  bool _reported = false;

  QrRecognition get r => widget.recognition;
  Brand? get brand => r.brand;
  BrandSupport get support => brand?.support ?? BrandSupport.unsupported;
  BrandRoute get route => brand?.route ?? BrandRoute.none;

  QrScanRecord _record(String status) => QrScanRecord(
        rawPayload: r.redactedPayload,
        qrCodeType: r.type.name,
        parserType: r.parser,
        recognitionStatus: status,
        manufacturer: r.manufacturer,
        productId: r.productId,
        model: r.model,
        serialNumber: r.serial,
        protocol: r.protocol,
      );

  @override
  void initState() {
    super.initState();
    final state = AppScope.read(context);
    final duplicate = state.deviceBySerial(r.serial);
    _name.text = [r.manufacturer, r.model].whereType<String>().join(' ').trim();
    if (state.role.canConfigureDevices) {
      state.recordQrScan(_record(duplicate != null ? 'duplicate' : r.recognitionStatus)).then((id) => _scanId = id);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? get _nameOrNull => _name.text.trim().isEmpty ? null : _name.text.trim();

  Future<void> _connect(AppState state) async {
    setState(() => _phase = _Phase.connecting);
    final nav = Navigator.of(context);
    Object? result;
    switch (route) {
      case BrandRoute.smartLife:
        result = await nav.push<String>(MaterialPageRoute(builder: (_) => AddDeviceScreen(initialKind: 'tuya', initialName: _nameOrNull, initialRoomId: _roomId)));
      case BrandRoute.ttlockBle:
        result = await nav.push<String>(MaterialPageRoute(builder: (_) => AddDeviceScreen(initialKind: 'lock', initialName: _nameOrNull, initialRoomId: _roomId)));
      case BrandRoute.videoBox:
        result = await nav.push<String>(MaterialPageRoute(builder: (_) => AddVideoDeviceScreen(initialQr: r.dahua, initialName: _nameOrNull)));
      case BrandRoute.hvac:
        result = await nav.push<bool>(MaterialPageRoute(builder: (_) => const HvacConnectScreen()));
      case BrandRoute.none:
        result = null;
    }
    if (!mounted) return;
    if (result == null || result == false) {
      setState(() => _phase = _Phase.review); // abandon : on peut recommencer
      return;
    }
    if (result is String && route != BrandRoute.videoBox) {
      _deviceId = result;
      await state.setDeviceIdentity(result, serialNumber: r.serial, qrCodeType: r.type.name);
      await state.updateQrScan(_scanId, status: 'added', deviceId: result);
    } else {
      // Boîtier vidéo ou assistant clim : l'appareil apparaît quand la passerelle l'a joint.
      _pendingBox = true;
      await state.updateQrScan(_scanId, status: 'added');
    }
    if (mounted) setState(() => _phase = _Phase.added);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final duplicate = state.deviceBySerial(r.serial);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('qrflow.title'))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
            _Step(n: 1, title: context.tr('qrflow.step1'), done: true, child: Text(context.tr('qr.kind.${r.type.name}'))),
            _Step(
              n: 2,
              title: context.tr('qrflow.step2'),
              done: r.manufacturer != null,
              child: Text(
                r.manufacturer == null ? context.tr('qrflow.unknownMaker') : [r.manufacturer, r.model].whereType<String>().join(' · '),
                key: const ValueKey('qrflow-maker'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            _Step(n: 3, title: context.tr('qrflow.step3'), done: r.recognized, child: _Sheet(r)),
            _Step(n: 4, title: context.tr('qrflow.step4'), done: support == BrandSupport.supported, child: _Compatibility(r)),
            if (duplicate != null)
              _Banner(
                key: const ValueKey('qrflow-duplicate'),
                icon: Icons.content_copy_rounded,
                color: context.flow.warning,
                title: context.tr('qrflow.duplicate'),
                message: context.tr('qrflow.duplicateHelp', {'name': duplicate.name}),
                action: OutlinedButton(onPressed: () => showDeviceDetail(context, duplicate.id), child: Text(context.tr('qrflow.openDevice'))),
              )
            else if (!state.role.canManage)
              _Banner(icon: Icons.lock_outline_rounded, color: context.flow.inkSoft, message: context.tr('qrflow.managerOnly'))
            else if (route == BrandRoute.none)
              ..._unsupported(context, state)
            else if (_phase == _Phase.added)
              ..._added(context, state)
            else
              ..._connectSteps(context, state),
          ]),
        ),
      ),
    );
  }

  List<Widget> _unsupported(BuildContext context, AppState state) {
    final f = context.flow;
    final viaHa = support == BrandSupport.homeAssistant;
    return [
      _Banner(
        key: const ValueKey('qrflow-unsupported'),
        icon: viaHa ? Icons.hub_outlined : Icons.extension_off_outlined,
        color: viaHa ? f.blue : f.warning,
        title: context.tr(r.recognized ? (viaHa ? 'qrflow.viaHa' : 'qrflow.unsupported') : 'qrflow.unknown'),
        message: context.tr(viaHa ? 'qrflow.viaHaHelp' : 'qrflow.unsupportedHelp'),
      ),
      const SizedBox(height: 12),
      FilledButton.tonalIcon(
        key: const ValueKey('qrflow-manual'),
        onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AddDeviceScreen())),
        icon: const Icon(Icons.edit_note_rounded),
        label: Text(context.tr('add.menu.manual')),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const ValueKey('qrflow-report'),
        onPressed: _reported
            ? null
            : () async {
                if (await state.reportQrScan(_scanId, _record(r.recognitionStatus)) && mounted) setState(() => _reported = true);
              },
        icon: Icon(_reported ? Icons.check_rounded : Icons.send_rounded),
        label: Text(context.tr(_reported ? 'qrflow.reportedShort' : 'qrflow.report')),
      ),
    ];
  }

  List<Widget> _connectSteps(BuildContext context, AppState state) {
    final busy = _phase == _Phase.connecting;
    return [
      _Step(n: 5, title: context.tr('qrflow.step5'), done: true, child: Text(context.tr('qrflow.route.${route.name}'))),
      _Step(
        n: 6,
        title: context.tr('qrflow.step6'),
        done: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (state.homes.length > 1)
            DropdownButtonFormField<String>(
              initialValue: state.home?.id,
              isExpanded: true,
              decoration: InputDecoration(labelText: context.tr('qrflow.home')),
              items: [for (final h in state.homes) DropdownMenuItem(value: h.id, child: Text(h.name, overflow: TextOverflow.ellipsis))],
              onChanged: busy
                  ? null
                  : (id) async {
                      final h = state.homes.where((x) => x.id == id).firstOrNull;
                      if (h != null) {
                        await state.selectHome(h);
                        if (mounted) setState(() => _roomId = null);
                      }
                    },
            )
          else
            Text(state.home?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
          if (route != BrandRoute.videoBox && route != BrandRoute.hvac)
            DropdownButtonFormField<String?>(
              key: ValueKey('qrflow-room-${state.home?.id}'),
              initialValue: _roomId,
              isExpanded: true,
              decoration: InputDecoration(labelText: context.tr('pair.room')),
              items: [
                DropdownMenuItem(value: null, child: Text(context.tr('room.none'))),
                for (final room in state.rooms) DropdownMenuItem(value: room.id, child: Text(room.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: busy ? null : (v) => setState(() => _roomId = v),
            ),
        ]),
      ),
      if (route != BrandRoute.hvac)
        _Step(
          n: 7,
          title: context.tr('qrflow.step7'),
          done: _name.text.trim().isNotEmpty,
          child: TextField(
            key: const ValueKey('qrflow-name'),
            controller: _name,
            enabled: !busy,
            maxLength: 60,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: context.tr('pair.name')),
          ),
        ),
      _Step(
        n: 8,
        title: context.tr('qrflow.step8'),
        done: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(context.tr('qrflow.testHelp'), style: TextStyle(color: context.flow.inkSoft)),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const ValueKey('qrflow-connect'),
            onPressed: busy || (state.plan?.isFull ?? false) ? null : () => _connect(state),
            icon: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link_rounded),
            label: Text(context.tr('qrflow.connect')),
          ),
          if (state.plan?.isFull ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(context.tr('plan.limitReached', {'limit': state.plan?.deviceLimit ?? HomePlan.freeLimit}), style: TextStyle(color: context.flow.danger)),
            ),
        ]),
      ),
    ];
  }

  List<Widget> _added(BuildContext context, AppState state) {
    final device = state.devices[_deviceId];
    final connected = device != null && device.isOnline;
    final room = state.roomById(device?.roomId);
    final f = context.flow;
    return [
      _Step(
        n: 8,
        title: context.tr('qrflow.step8'),
        done: connected,
        child: Text(
          context.tr(connected ? 'qrflow.connected' : (_pendingBox ? 'qrflow.pendingBox' : 'qrflow.waitingFirst')),
          key: const ValueKey('qrflow-result'),
          style: TextStyle(fontWeight: FontWeight.w700, color: connected ? f.success : f.warning),
        ),
      ),
      _Step(
        n: 9,
        title: context.tr('qrflow.step9'),
        done: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(device == null ? context.tr('qrflow.addedGeneric') : context.tr('qrflow.addedIn', {'name': device.name, 'room': room?.name ?? context.tr('room.none')})),
          const SizedBox(height: 12),
          if (device != null)
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                openRoom(context, device.roomId);
              },
              child: Text(context.tr('qrflow.showRoom')),
            )
          else
            FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.tr('pair.finish'))),
        ]),
      ),
    ];
  }
}

/// Fiche de l'appareil reconnu (jamais de secret affiché).
class _Sheet extends StatelessWidget {
  const _Sheet(this.r);

  final QrRecognition r;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final rows = <(String, String)>[
      if (r.manufacturer != null) (context.tr('qrflow.maker'), r.manufacturer!),
      if (r.model != null) (context.tr('qrflow.model'), r.model!),
      if (r.deviceType != null) (context.tr('qrflow.type'), context.tryTr('qr.type.${r.deviceType}') ?? r.deviceType!),
      if (r.protocol != null) (context.tr('qrflow.protocol'), context.tryTr('qr.protocol.${r.protocol}') ?? r.protocol!),
      if (r.productId != null) (context.tr('qrflow.product'), r.productId!),
      if (r.serial != null) (context.tr('qrflow.serial'), r.serial!),
      for (final e in r.details.entries)
        if (e.value.isNotEmpty) (context.tryTr('qrflow.detail.${e.key}') ?? e.key, e.value),
      if (r.hasCredentials) (context.tr('qrflow.credentials'), context.tr('qrflow.credentialsHidden')),
    ];
    if (rows.isEmpty) return Text(context.tr('qrflow.nothingRead'), style: TextStyle(color: f.inkSoft));
    return Column(children: [
      for (final (label, value) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 130, child: Text(label, style: TextStyle(color: f.inkSoft))),
            Expanded(child: SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        ),
    ]);
  }
}

/// Identification, authentification, appairage, contrôle : ce que Solea sait faire.
class _Compatibility extends StatelessWidget {
  const _Compatibility(this.r);

  final QrRecognition r;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final support = r.brand?.support ?? BrandSupport.unsupported;
    final (label, color) = switch (support) {
      BrandSupport.supported => ('brand.support.supported', f.success),
      BrandSupport.homeAssistant => ('brand.support.homeAssistant', f.blue),
      BrandSupport.unsupported => ('brand.support.unsupported', f.warning),
    };
    Widget line(String key, bool ok) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 18, color: ok ? f.success : f.inkFaint),
            const SizedBox(width: 8),
            Expanded(child: Text(context.tr(key))),
          ]),
        );
    final supported = support == BrandSupport.supported;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        key: ValueKey('qrflow-support-${support.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(999)),
        child: Text(context.tr(label), style: TextStyle(color: color, fontWeight: FontWeight.w800)),
      ),
      const SizedBox(height: 8),
      line('qrflow.check.identification', r.recognized),
      line('qrflow.check.authentication', supported),
      line('qrflow.check.pairing', supported),
      line('qrflow.check.control', supported),
    ]);
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title, required this.done, required this.child});

  final int n;
  final String title;
  final bool done;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: done ? f.brand : f.chip),
            child: done
                ? Icon(Icons.check_rounded, size: 16, color: f.onBrand)
                : Text('$n', style: TextStyle(fontWeight: FontWeight.w800, color: f.inkSoft)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              child,
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({super.key, required this.icon, required this.color, this.title, this.message, this.action});

  final IconData icon;
  final Color color;
  final String? title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (title != null) Text(title!, style: theme.textTheme.titleMedium),
              if (title != null && (message ?? '').isNotEmpty) const SizedBox(height: 4),
              if ((message ?? '').isNotEmpty) Text(message!, style: theme.textTheme.bodyMedium),
              if (action != null) ...[const SizedBox(height: 10), action!],
            ]),
          ),
        ]),
      ),
    );
  }
}

