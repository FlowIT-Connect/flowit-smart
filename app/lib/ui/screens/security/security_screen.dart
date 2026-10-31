import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n.dart';
import '../../../core/theme.dart';
import '../../../data/backend.dart';
import '../../../models/models.dart';
import '../../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/device_visual.dart';
import '../device_detail.dart';
import 'add_video_device_screen.dart';
import 'video_source_screen.dart';

/// « Sécurité et vidéo » : vue générale des caméras et visiophones du logement.
///
/// Les membres voient les caméras auxquelles ils ont droit. Le propriétaire,
/// l'administrateur et l'installateur voient aussi l'état technique et peuvent ajouter
/// un équipement.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  MediaGateway? _gateway;
  bool _gatewayLoaded = false;
  List<VideoSource> _sources = const [];
  String? _error;
  Timer? _refresh;

  bool get _canConfigure => AppScope.read(context).role.canConfigureDevices;

  @override
  void initState() {
    super.initState();
    _load();
    _refresh = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final state = AppScope.read(context);
    final home = state.home;
    if (home == null) return;
    try {
      final gateway = await state.backend.getMediaGateway(home.id);
      final sources = _canConfigure ? await state.backend.listVideoSources(home.id) : const <VideoSource>[];
      if (!mounted) return;
      setState(() {
        _gateway = gateway;
        _gatewayLoaded = true;
        _sources = sources;
        _error = null;
      });
    } on BackendException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _openAdd() async {
    final added = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const AddVideoDeviceScreen()));
    if (added != null && mounted) {
      await _load();
      if (!mounted) return;
      final src = _sources.where((s) => s.id == added).firstOrNull;
      if (src != null) await _openSource(src);
    }
  }

  Future<void> _openSource(VideoSource s) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoSourceScreen(sourceId: s.id, initial: s)));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final f = context.flow;
    final theme = Theme.of(context);
    final cameras = state.visibleDevices.where((d) => d.isCamera).toList();
    final intercoms = cameras.where((d) => d.isIntercom).length;
    final online = cameras.where((d) => d.availability == Availability.available).length;
    final offline = cameras.where((d) => d.availability == Availability.unavailable).length;
    final sourceByDevice = {for (final s in _sources) if (s.deviceId != null) s.deviceId!: s};
    final pendingSources = _sources.where((s) => s.deviceId == null || !state.devices.containsKey(s.deviceId)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('security.title')),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: context.tr('common.retry'))],
      ),
      floatingActionButton: _canConfigure
          ? FloatingActionButton.extended(onPressed: _openAdd, icon: const Icon(Icons.add_rounded), label: Text(context.tr('security.add')))
          : null,
      body: ContentWidth(
        maxWidth: 900,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
          if (_error != null)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: TextStyle(color: f.danger))),
          // ------------------------------------------------ Vue générale
          LayoutBuilder(builder: (context, box) {
            final cols = box.maxWidth > 560 ? 4 : 2;
            final w = (box.maxWidth - 10 * (cols - 1)) / cols;
            Widget stat(IconData icon, Color color, String label, int value) => SizedBox(
                  width: w,
                  child: GlassPanel(
                    radius: 20,
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      IconBubble(icon: icon, color: color, size: 36),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('$value', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                    ]),
                  ),
                );
            return Wrap(spacing: 10, runSpacing: 10, children: [
              stat(Icons.videocam_rounded, f.blue, context.tr('security.cameras'), cameras.length - intercoms),
              stat(Icons.doorbell_rounded, f.orange, context.tr('security.intercoms'), intercoms),
              stat(Icons.wifi_tethering_rounded, f.success, context.tr('security.online'), online),
              stat(Icons.link_off_rounded, f.danger, context.tr('security.offline'), offline),
            ]);
          }),
          const SizedBox(height: 14),
          _GatewayCard(gateway: _gateway, loaded: _gatewayLoaded),
          // ------------------------------------------------ Mes caméras
          SectionHeader(context.tr('security.myCameras')),
          if (cameras.isEmpty && pendingSources.isEmpty)
            EmptyState(
              icon: Icons.videocam_outlined,
              title: context.tr('security.empty'),
              message: context.tr(_canConfigure ? 'security.emptyHelp' : 'security.emptyMember'),
            ),
          for (final d in cameras)
            _CameraCard(
              device: d,
              source: sourceByDevice[d.id],
              onOpen: () => showDeviceDetail(context, d.id),
              onDiagnose: sourceByDevice[d.id] == null ? null : () => _openSource(sourceByDevice[d.id]!),
            ),
          for (final s in pendingSources) _PendingSourceCard(source: s, onOpen: () => _openSource(s)),
          const SizedBox(height: 12),
          Text(context.tr('security.privacy'), style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft, height: 1.4)),
        ]),
      ),
    );
  }
}

class _GatewayCard extends StatelessWidget {
  const _GatewayCard({required this.gateway, required this.loaded});
  final MediaGateway? gateway;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final g = gateway;
    final (color, icon, title, help) = !loaded
        ? (f.inkFaint, Icons.hourglass_empty_rounded, 'security.box', 'security.boxChecking')
        : g == null
            ? (f.warning, Icons.router_outlined, 'security.boxNone', 'security.boxNoneHelp')
            : !g.online
                ? (f.danger, Icons.portable_wifi_off_rounded, 'security.boxOffline', 'security.boxOfflineHelp')
                : g.relayOk
                    ? (f.success, Icons.router_rounded, 'security.boxOnline', 'security.boxOnlineHelp')
                    : (f.warning, Icons.router_rounded, 'security.boxNoRelay', 'security.boxNoRelayHelp');
    return GlassPanel(
      radius: 20,
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        IconBubble(icon: icon, color: color, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr(title), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(context.tr(help), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: f.inkSoft, height: 1.35)),
          ]),
        ),
      ]),
    );
  }
}

/// Libellé court d'une capacité UDI.
String capabilityLabel(BuildContext context, String key) => context.tr('udi.$key');

IconData capabilityIcon(String key) => switch (key) {
      'video_stream' => Icons.videocam_rounded,
      'snapshot' => Icons.photo_camera_rounded,
      'audio_input' => Icons.mic_rounded,
      'audio_output' => Icons.campaign_rounded,
      'motion_detection' => Icons.directions_run_rounded,
      'human_detection' => Icons.person_search_rounded,
      'ptz_control' => Icons.open_with_rounded,
      'door_relay' => Icons.door_front_door_rounded,
      'sip_call' => Icons.call_rounded,
      _ => Icons.check_rounded,
    };

class _CameraCard extends StatelessWidget {
  const _CameraCard({required this.device, required this.source, required this.onOpen, this.onDiagnose});
  final Device device;
  final VideoSource? source;
  final VoidCallback onOpen;
  final VoidCallback? onDiagnose;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    final theme = Theme.of(context);
    final d = device;
    final caps = d.udi.enabled;
    final subtitle = [d.vendor, d.model].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
    final motion = d.state['motion'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        radius: 22,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DeviceVisual(d, size: 52, photoSize: 64),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(d.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
                    AvailabilityBadge(d.availability, compact: true),
                  ]),
                  if (subtitle.isNotEmpty) Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft)),
                  if (source?.location != null) Text(source!.location!, style: theme.textTheme.bodySmall?.copyWith(color: f.inkSoft)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    InfoChip(
                      icon: d.hasLiveVideo ? Icons.play_circle_rounded : Icons.photo_library_rounded,
                      label: context.tr(d.hasLiveVideo ? 'security.fluid' : 'security.stills'),
                    ),
                    for (final c in caps.where((c) => c != 'video_stream')) InfoChip(icon: capabilityIcon(c), label: capabilityLabel(context, c)),
                    if (motion) InfoChip(icon: Icons.directions_run_rounded, label: context.tr('security.motionNow')),
                  ]),
                ]),
              ),
              if (onDiagnose != null)
                IconButton(onPressed: onDiagnose, tooltip: context.tr('security.diagnostic'), icon: Icon(Icons.troubleshoot_rounded, color: f.inkSoft)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PendingSourceCard extends StatelessWidget {
  const _PendingSourceCard({required this.source, required this.onOpen});
  final VideoSource source;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final f = context.flow;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassPanel(
        radius: 22,
        child: ListTile(
          onTap: onOpen,
          leading: IconBubble(icon: source.isIntercom ? Icons.doorbell_rounded : Icons.videocam_rounded, color: f.inkFaint, size: 40),
          title: Text(source.name),
          subtitle: Text(context.tr(source.testing ? 'security.waitingBox' : 'vsrc.status.${source.status.name}')),
          trailing: const ForwardChevron(),
        ),
      ),
    );
  }
}
