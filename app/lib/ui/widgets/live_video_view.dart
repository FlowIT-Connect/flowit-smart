import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/camera_talk.dart';
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
  const LiveVideoView({super.key, required this.device, this.playbackStart, this.onBackToLive, this.onFirstFrame});

  final Device device;

  /// Relecture de la carte mémoire à partir de cette heure (null : direct).
  final DateTime? playbackStart;

  /// Relecture : bouton « Revenir au direct ».
  final VoidCallback? onBackToLive;

  /// Première image affichée (la relecture fait avancer la barre du temps à partir d'ici).
  final VoidCallback? onFirstFrame;

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
  bool _muted = false; // son actif d'emblée, comme dans l'application de la caméra
  CameraTalk? _talk; // voix du téléphone vers la caméra, pendant qu'on parle
  bool _talking = false;
  bool _hd = true;
  bool _snapshots = false;
  bool _disposed = false;
  int _attempt = 0;
  bool _gotFrame = false;
  bool _attaching = false;
  Timer? _watchdog;
  late final Backend _backend;

  @override
  void initState() {
    super.initState();
    _backend = AppScope.read(context).backend;
    _start();
  }

  @override
  void didUpdateWidget(LiveVideoView old) {
    super.didUpdateWidget(old);
    if (old.playbackStart != widget.playbackStart) _restart();
  }

  bool get _playback => widget.playbackStart != null;

  @override
  void dispose() {
    _disposed = true;
    unawaited(_talk?.stop());
    _talk = null;
    _teardown();
    _renderer.dispose();
    super.dispose();
  }

  Future<void> _teardown() async {
    _watchdog?.cancel();
    _watchdog = null;
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
      _gotFrame = false;
    });
    try {
      if (_renderer.textureId == null) await _renderer.initialize();
      void shown() {
        if (_gotFrame) return;
        _watchdog?.cancel();
        if (mounted) setState(() => _gotFrame = true);
        widget.onFirstFrame?.call();
      }

      _renderer.onFirstFrameRendered = shown;
      _renderer.onResize = () {
        if (_renderer.videoWidth > 0) shown();
      };
      final gateway = await state.backend.getMediaGateway(d.homeId);
      if (gateway == null || !gateway.online) throw BackendException('offline', state.tr('video.boxOffline'));
      if (!gateway.relayOk) throw BackendException('offline', state.tr('video.relayMissing'));

      if (_disposed || attempt != _attempt) return;
      final pc = await createPeerConnection({'iceServers': gateway.iceServers, 'sdpSemantics': 'unified-plan'});
      if (_disposed || attempt != _attempt) {
        unawaited(pc.close().then((_) {}, onError: (_) {}));
        return;
      }
      _pc = pc;
      await pc.addTransceiver(kind: RTCRtpMediaType.RTCRtpMediaTypeVideo, init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly));
      if (d.udi.microphone) {
        await pc.addTransceiver(kind: RTCRtpMediaType.RTCRtpMediaTypeAudio, init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly));
      }
      // Son et image arrivent en deux pistes, parfois dans deux flux distincts et dans n'importe
      // quel ordre : on n'accroche au lecteur qu'un flux qui contient bien la piste vidéo.
      pc.onTrack = (event) {
        if (_disposed || attempt != _attempt) return;
        if (event.track.kind == 'video') _attachReceivers(pc, attempt);
      };
      pc.onConnectionState = (s) {
        if (_disposed || attempt != _attempt) return;
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) _fail(state.tr('video.connectionLost'));
        // « Disconnected » est souvent passager (Wi-Fi qui hésite) : on laisse 6 s pour revenir.
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          Future.delayed(const Duration(seconds: 6), () {
            if (!_disposed && attempt == _attempt && pc.connectionState == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
              _fail(state.tr('video.connectionLost'));
            }
          });
        }
        // Certains téléphones ne signalent jamais la piste (onTrack) : on la prend chez le récepteur.
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          Future.delayed(const Duration(milliseconds: 1500), () => _attachReceivers(pc, attempt));
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

      // Une seule session à la fois : une demande dépassée (changement d'heure, nouvel essai)
      // est abandonnée tout de suite, sans laisser une seconde vidéo s'ouvrir sur le boîtier.
      if (_disposed || attempt != _attempt) {
        unawaited(pc.close().then((_) {}, onError: (_) {}));
        return;
      }
      final sessionId = await state.backend.openVideoSession(d.homeId, d.id, offer!.sdp!,
          quality: _hd ? 'main' : 'sub', playbackStart: widget.playbackStart);
      if (_disposed || attempt != _attempt) {
        unawaited(_backend.closeVideoSession(sessionId).then((_) {}, onError: (_) {}));
        unawaited(pc.close().then((_) {}, onError: (_) {}));
        return;
      }
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
      // Images reçues mais jamais affichées (format ou taille que ce téléphone ne décode pas) :
      // on le dit au lieu de laisser tourner sans fin, avec la qualité SD ou les images fixes.
      _watchdog?.cancel();
      _watchdog = Timer(const Duration(seconds: 10), () {
        if (!_disposed && attempt == _attempt && !_gotFrame && _renderer.videoWidth == 0) _failNoPicture(pc, attempt, state.tr('video.noPicture'));
      });
    } on BackendException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail(state.tr('video.failed'));
    }
  }

  Future<void> _attachReceivers(RTCPeerConnection pc, int attempt) async {
    if (_disposed || attempt != _attempt || _phase != _Phase.connecting || _attaching) return;
    _attaching = true;
    try {
      final tracks = [for (final r in await pc.getReceivers()) if (r.track != null) r.track!];
      if (!tracks.any((t) => t.kind == 'video')) return;
      final stream = await createLocalMediaStream('solea-live');
      for (final t in tracks) {
        await stream.addTrack(t);
      }
      if (_disposed || attempt != _attempt || _phase != _Phase.connecting) return;
      _stream = stream;
      _renderer.srcObject = stream;
      _applyMute();
      if (mounted) setState(() => _phase = _Phase.playing);
    } catch (_) {
    } finally {
      _attaching = false;
    }
  }

  /// Pas d'image affichée : on ajoute ce que le téléphone a reçu et décodé, pour savoir
  /// si c'est le réseau, le décodeur vidéo du téléphone ou l'affichage qui bloque.
  Future<void> _failNoPicture(RTCPeerConnection pc, int attempt, String message) async {
    var detail = '';
    try {
      for (final r in await pc.getStats()) {
        final v = r.values;
        if (r.type != 'inbound-rtp' || (v['kind'] ?? v['mediaType']) != 'video') continue;
        int n(String k) => (v[k] is num) ? (v[k] as num).toInt() : 0;
        final kb = n('bytesReceived') ~/ 1024;
        final dec = v['decoderImplementation'];
        detail = '\n[$kb Ko · ${n('framesReceived')} reçues · ${n('framesDecoded')} décodées · '
            '${n('keyFramesDecoded')} clés · ${n('frameWidth')}x${n('frameHeight')}'
            '${dec is String && dec.isNotEmpty ? ' · $dec' : ''}]';
      }
    } catch (_) {}
    if (_disposed || attempt != _attempt || _gotFrame) return;
    _fail('$message$detail');
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

  /// Micro : un appui pour parler, un autre pour arrêter (la caméra coupe son propre micro
  /// pendant qu'on parle, comme un talkie-walkie).
  Future<void> _toggleTalk(void Function(String) toast) async {
    final current = _talk;
    if (current != null) {
      _talk = null;
      setState(() => _talking = false);
      await current.stop();
      return;
    }
    final state = AppScope.read(context);
    final talk = CameraTalk(_backend, widget.device);
    _talk = talk;
    setState(() => _talking = true);
    try {
      await talk.start(tr: state.tr);
      if (mounted && _talk == talk) toast(state.tr('video.talkOn'));
    } on BackendException catch (e) {
      await talk.stop();
      if (_talk == talk) _talk = null;
      if (mounted) {
        setState(() => _talking = false);
        toast(e.message);
      }
    } catch (e) {
      await talk.stop();
      if (_talk == talk) _talk = null;
      if (mounted) {
        setState(() => _talking = false);
        // Détail technique affiché : il permet de comprendre l'échec sur un téléphone précis.
        toast('${state.tr('video.talkFailed')} ($e)');
      }
    }
  }

  Future<void> _restart() async {
    _attempt++; // la tentative en cours s'arrête d'elle-même
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
    // Images fixes proposées dès l'ouverture, sans attendre que la vidéo échoue.
    final canStills = d.udi.snapshot && !_playback;
    void useStills() {
      _teardown(); // ne pas laisser la vidéo couler pour rien
      setState(() => _snapshots = true);
    }

    Widget stillsButton() => FilledButton.tonalIcon(
          onPressed: useStills,
          icon: const Icon(Icons.photo_library_rounded),
          label: Text(context.tr('video.useSnapshots')),
        );
    final Widget body = switch (_phase) {
      _Phase.playing => Stack(fit: StackFit.expand, children: [
          RTCVideoView(_renderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain),
          if (!_gotFrame)
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: white)),
                if (canStills) ...[const SizedBox(height: 14), stillsButton()],
              ]),
            ),
        ]),
      _Phase.connecting => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: white)),
            const SizedBox(height: 12),
            Text(context.tr('video.connecting'), style: theme.textTheme.bodyMedium?.copyWith(color: white.withValues(alpha: .85))),
            if (canStills) ...[const SizedBox(height: 14), stillsButton()],
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
                if (_playback && widget.onBackToLive != null)
                  FilledButton.tonalIcon(
                    onPressed: widget.onBackToLive,
                    icon: const Icon(Icons.live_tv_rounded),
                    label: Text(context.tr('history.backToLive')),
                  ),
                if (_hd && !_playback)
                  FilledButton.tonalIcon(
                    onPressed: () {
                      setState(() => _hd = false);
                      _restart();
                    },
                    icon: const Icon(Icons.sd_rounded),
                    label: Text(context.tr('video.trySd')),
                  ),
                if (canStills) stillsButton(),
              ]),
            ]),
          ),
        ),
    };
    final playing = _phase == _Phase.playing;
    void toast(String text) => ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
    // Rangée de boutons sous la vidéo, comme dans l'application de la caméra.
    final toolbar = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _ToolButton(
          key: const ValueKey('video-sound'),
          icon: _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          label: context.tr(_muted ? 'video.unmute' : 'video.mute'),
          onPressed: playing && d.udi.microphone
              ? () => setState(() {
                    _muted = !_muted;
                    _applyMute();
                  })
              : null,
        ),
        _ToolButton(
          key: const ValueKey('video-talk'),
          icon: _talking ? Icons.mic_rounded : Icons.mic_none_rounded,
          label: context.tr(_talking ? 'video.talkStop' : 'video.talk'),
          active: _talking,
          onPressed: () {
            if (!d.udi.speaker) return toast(context.tr('video.talkUnsupported'));
            _toggleTalk(toast);
          },
        ),
        _ToolButton(
          key: const ValueKey('video-quality'),
          icon: _hd ? Icons.hd_rounded : Icons.sd_rounded,
          label: context.tr(_hd ? 'video.qualityHd' : 'video.qualitySd'),
          onPressed: _playback
              ? null
              : () {
                  setState(() => _hd = !_hd);
                  _restart();
                },
        ),
        _ToolButton(
          key: const ValueKey('video-fullscreen'),
          icon: Icons.fullscreen_rounded,
          label: context.tr('camera.fullscreen'),
          onPressed: playing
              ? () => Navigator.of(context).push(MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => _FullscreenVideo(renderer: _renderer, title: d.name),
                  ))
              : null,
        ),
      ]),
    );
    final view = Padding(
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
                  color: (_phase != _Phase.playing ? Colors.black : _playback ? f.brand : f.danger).withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _playback && _phase == _Phase.playing
                      ? context.tr('history.badge', {'time': _hhmm(widget.playbackStart!)})
                      : context.tr(_phase == _Phase.playing ? 'video.liveBadge' : 'camera.waiting'),
                  style: theme.textTheme.labelSmall?.copyWith(color: white, fontWeight: FontWeight.w800, letterSpacing: .6),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [view, toolbar]);
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({super.key, required this.icon, required this.label, this.onPressed, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: label,
        child: IconButton.filledTonal(
          isSelected: active,
          style: active ? IconButton.styleFrom(backgroundColor: context.flow.danger, foregroundColor: Colors.white) : null,
          onPressed: onPressed,
          iconSize: 26,
          padding: const EdgeInsets.all(12),
          icon: Icon(icon),
        ),
      );
}

String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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
