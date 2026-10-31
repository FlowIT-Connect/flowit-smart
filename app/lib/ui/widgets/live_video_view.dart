import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/backend.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import 'camera_view.dart';

/// Vidéo fluide d'une caméra ou d'un visiophone, en WebRTC, par le boîtier vidéo du logement.
///
/// L'application dépose son offre dans Solea, le boîtier la transmet au relais MediaMTX et
/// renvoie la réponse : aucune adresse RTSP ni aucun port n'est exposé. Si la vidéo fluide
/// n'est pas disponible, on bascule sur les images fixes (environ une par seconde).
class LiveVideoView extends StatefulWidget {
  const LiveVideoView({super.key, required this.device});

  final Device device;

  @override
  State<LiveVideoView> createState() => _LiveVideoViewState();
}

enum _Phase { connecting, playing, failed }

class _LiveVideoViewState extends State<LiveVideoView> {
  final _renderer = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _stream;
  String? _sessionId;
  _Phase _phase = _Phase.connecting;
  String? _error;
  bool _muted = true;
  bool _hd = true;
  bool _snapshots = false;
  bool _disposed = false;
  int _attempt = 0;
  late final Backend _backend;

  @override
  void initState() {
    super.initState();
    _backend = AppScope.read(context).backend;
    _start();
  }

  @override
  void dispose() {
    _disposed = true;
    _teardown();
    _renderer.dispose();
    super.dispose();
  }

  Future<void> _teardown() async {
    final id = _sessionId;
    _sessionId = null;
    if (id != null) unawaited(_backend.closeVideoSession(id).then((_) {}, onError: (_) {}));
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    _stream = null;
  }

  Future<void> _start() async {
    final attempt = ++_attempt;
    final state = AppScope.read(context);
    final d = widget.device;
    setState(() {
      _phase = _Phase.connecting;
      _error = null;
    });
    try {
      if (_renderer.textureId == null) await _renderer.initialize();
      final gateway = await state.backend.getMediaGateway(d.homeId);
      if (gateway == null || !gateway.online) throw BackendException('offline', state.tr('video.boxOffline'));
      if (!gateway.relayOk) throw BackendException('offline', state.tr('video.relayMissing'));

      final pc = await createPeerConnection({'iceServers': gateway.iceServers, 'sdpSemantics': 'unified-plan'});
      _pc = pc;
      await pc.addTransceiver(kind: RTCRtpMediaType.RTCRtpMediaTypeVideo, init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly));
      if (d.udi.microphone) {
        await pc.addTransceiver(kind: RTCRtpMediaType.RTCRtpMediaTypeAudio, init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly));
      }
      pc.onTrack = (event) {
        if (event.streams.isEmpty || _disposed) return;
        _stream = event.streams.first;
        _renderer.srcObject = _stream;
        _applyMute();
        if (mounted) setState(() => _phase = _Phase.playing);
      };
      pc.onConnectionState = (s) {
        if (_disposed || attempt != _attempt) return;
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed || s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          _fail(state.tr('video.connectionLost'));
        }
      };

      // Pas d'échange de candidats au fil de l'eau : on attend qu'ils soient tous dans l'offre.
      final gathered = Completer<void>();
      pc.onIceGatheringState = (s) {
        if (s == RTCIceGatheringState.RTCIceGatheringStateComplete && !gathered.isCompleted) gathered.complete();
      };
      await pc.setLocalDescription(await pc.createOffer({}));
      await gathered.future.timeout(const Duration(seconds: 4), onTimeout: () {});
      final offer = await pc.getLocalDescription();
      if (offer?.sdp == null) throw BackendException('unknown', state.tr('video.failed'));

      final sessionId = await state.backend.openVideoSession(d.homeId, d.id, offer!.sdp!, quality: _hd ? 'main' : 'sub');
      _sessionId = sessionId;
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      VideoSessionInfo? info;
      while (!_disposed && attempt == _attempt && DateTime.now().isBefore(deadline)) {
        info = await state.backend.getVideoSession(sessionId);
        if (info != null && info.status != 'offer') break;
        await Future.delayed(const Duration(milliseconds: 400));
      }
      if (_disposed || attempt != _attempt) return;
      if (info == null || info.status == 'offer') throw BackendException('timeout', state.tr('video.noAnswer'));
      if (info.status != 'answered' || info.answer == null) throw BackendException('failed', info.error ?? state.tr('video.failed'));
      await pc.setRemoteDescription(RTCSessionDescription(info.answer, 'answer'));
    } on BackendException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail(state.tr('video.failed'));
    }
  }

  void _fail(String message) {
    if (_disposed || !mounted) return;
    _teardown();
    setState(() {
      _phase = _Phase.failed;
      _error = message;
    });
  }

  void _applyMute() {
    final s = _stream;
    if (s == null) return;
    for (final t in s.getAudioTracks()) {
      t.enabled = !_muted;
    }
    _renderer.muted = _muted;
  }

  Future<void> _restart() async {
    await _teardown();
    if (!_disposed) await _start();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    if (_snapshots) {
      return Column(children: [
        CameraLiveView(key: ValueKey('camera-${d.id}'), device: d),
        TextButton.icon(
          onPressed: () {
            setState(() => _snapshots = false);
            _restart();
          },
          icon: const Icon(Icons.play_circle_outline_rounded),
          label: Text(context.tr('video.backToLive')),
        ),
      ]);
    }
    final theme = Theme.of(context);
    final f = context.flow;
    const white = Colors.white;
    final Widget body = switch (_phase) {
      _Phase.playing => RTCVideoView(_renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain),
      _Phase.connecting => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: white)),
            const SizedBox(height: 12),
            Text(context.tr('video.connecting'), style: theme.textTheme.bodyMedium?.copyWith(color: white.withValues(alpha: .85))),
          ]),
        ),
      _Phase.failed => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.videocam_off_rounded, color: white.withValues(alpha: .8), size: 34),
              const SizedBox(height: 10),
              Text(_error ?? context.tr('video.failed'),
                  textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: white.withValues(alpha: .9), height: 1.4)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                FilledButton.tonalIcon(onPressed: _restart, icon: const Icon(Icons.refresh_rounded), label: Text(context.tr('common.retry'))),
                if (d.udi.snapshot)
                  FilledButton.tonalIcon(
                    onPressed: () => setState(() => _snapshots = true),
                    icon: const Icon(Icons.photo_library_rounded),
                    label: Text(context.tr('video.useSnapshots')),
                  ),
              ]),
            ]),
          ),
        ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(fit: StackFit.expand, children: [
            const ColoredBox(color: Color(0xFF0E1116)),
            body,
            PositionedDirectional(
              top: 10,
              start: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (_phase == _Phase.playing ? f.danger : Colors.black).withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  context.tr(_phase == _Phase.playing ? 'video.liveBadge' : 'camera.waiting'),
                  style: theme.textTheme.labelSmall?.copyWith(color: white, fontWeight: FontWeight.w800, letterSpacing: .6),
                ),
              ),
            ),
            if (_phase == _Phase.playing)
              PositionedDirectional(
                bottom: 6,
                end: 6,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (d.udi.microphone)
                    IconButton(
                      tooltip: context.tr(_muted ? 'video.unmute' : 'video.mute'),
                      onPressed: () => setState(() {
                        _muted = !_muted;
                        _applyMute();
                      }),
                      icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: white),
                    ),
                  TextButton(
                    onPressed: () {
                      setState(() => _hd = !_hd);
                      _restart();
                    },
                    child: Text(_hd ? 'HD' : 'SD', style: const TextStyle(color: white, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: context.tr('camera.fullscreen'),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (_) => _FullscreenVideo(renderer: _renderer, title: d.name),
                    )),
                    icon: const Icon(Icons.fullscreen_rounded, color: white),
                  ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

class _FullscreenVideo extends StatelessWidget {
  const _FullscreenVideo({required this.renderer, required this.title});
  final RTCVideoRenderer renderer;
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(title)),
        body: InteractiveViewer(
          maxScale: 5,
          child: Center(child: RTCVideoView(renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain)),
        ),
      );
}
