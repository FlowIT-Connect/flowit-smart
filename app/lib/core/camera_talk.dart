import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../data/backend.dart';
import '../models/models.dart';

/// « Parler à travers la caméra » : le micro du téléphone part en WebRTC vers le boîtier vidéo
/// de la maison, qui le renvoie au haut-parleur de la caméra (G.711, voie de retour ONVIF).
/// Le micro n'est ouvert que pendant que l'on parle.
class CameraTalk {
  CameraTalk(this.backend, this.device);

  final Backend backend;
  final Device device;
  RTCPeerConnection? _pc;
  MediaStream? _mic;
  String? _sessionId;
  bool _stopped = false;

  /// Démarre la voix ; lève une [BackendException] avec un message clair en cas d'échec.
  Future<void> start({required String Function(String key) tr}) async {
    final gateway = await backend.getMediaGateway(device.homeId);
    if (gateway == null || !gateway.online) throw BackendException('offline', tr('video.boxOffline'));
    if (!gateway.relayOk) throw BackendException('offline', tr('video.relayMissing'));
    try {
      _mic = await navigator.mediaDevices.getUserMedia({
        'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
        'video': false,
      });
    } catch (_) {
      throw BackendException('permission', tr('video.talkNoMic'));
    }
    if (_stopped) return stop();
    final pc = await createPeerConnection({'iceServers': gateway.iceServers, 'sdpSemantics': 'unified-plan'});
    _pc = pc;
    final track = _mic!.getAudioTracks().first;
    await pc.addTransceiver(track: track, kind: RTCRtpMediaType.RTCRtpMediaTypeAudio, init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendOnly, streams: [_mic!]));
    final gathered = Completer<void>();
    pc.onIceGatheringState = (s) {
      if (s == RTCIceGatheringState.RTCIceGatheringStateComplete && !gathered.isCompleted) gathered.complete();
    };
    final offer = await pc.createOffer({});
    // La caméra ne comprend que le G.711 : on n'offre que lui (A-law d'abord, comme la Hero A1).
    await pc.setLocalDescription(RTCSessionDescription(onlyG711(offer.sdp ?? ''), offer.type));
    await gathered.future.timeout(const Duration(seconds: 4), onTimeout: () {});
    final local = await pc.getLocalDescription();
    if (local?.sdp == null || _stopped) return stop();
    final id = await backend.openVideoSession(device.homeId, device.id, local!.sdp!, quality: 'talk');
    _sessionId = id;
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    VideoSessionInfo? info;
    while (!_stopped && DateTime.now().isBefore(deadline)) {
      info = await backend.getVideoSession(id);
      if (info != null && info.status != 'offer') break;
      await Future.delayed(const Duration(milliseconds: 400));
    }
    if (_stopped) return stop();
    if (info == null || info.status == 'offer') throw BackendException('timeout', tr('video.noAnswer'));
    if (info.status != 'answered' || info.answer == null) throw BackendException('failed', info.error ?? tr('video.talkFailed'));
    await pc.setRemoteDescription(RTCSessionDescription(info.answer, 'answer'));
  }

  Future<void> stop() async {
    _stopped = true;
    final id = _sessionId;
    _sessionId = null;
    if (id != null) unawaited(backend.closeVideoSession(id).then((_) {}, onError: (_) {}));
    for (final t in _mic?.getTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop().catchError((_) {});
    }
    await _mic?.dispose().catchError((_) {});
    _mic = null;
    await _pc?.close().catchError((_) {});
    _pc = null;
  }
}

/// Ne garde que le G.711 (PCMA 8, PCMU 0) sur la ligne audio de l'offre SDP.
String onlyG711(String sdp) {
  final lines = sdp.split(RegExp(r'\r?\n'));
  final out = <String>[];
  var inAudio = false;
  for (final line in lines) {
    if (line.startsWith('m=')) {
      inAudio = line.startsWith('m=audio');
      if (inAudio) {
        final parts = line.split(' ');
        final pts = parts.sublist(3).where((p) => p == '8' || p == '0').toList()..sort((a, b) => b.compareTo(a));
        out.add([...parts.sublist(0, 3), ...(pts.isEmpty ? ['8', '0'] : pts)].join(' '));
        continue;
      }
    }
    if (inAudio) {
      final m = RegExp(r'^a=(rtpmap|fmtp|rtcp-fb):(\d+)').firstMatch(line);
      if (m != null && m.group(2) != '8' && m.group(2) != '0') continue;
    }
    out.add(line);
  }
  var text = out.join('\r\n');
  // Types statiques : décrits quand même, pour les relais qui l'exigent.
  for (final (pt, name) in const [('0', 'PCMU'), ('8', 'PCMA')]) {
    if (!text.contains('a=rtpmap:$pt ')) {
      text = text.replaceFirstMapped(RegExp(r'(m=audio[^\r\n]*)'), (m) => '${m[1]}\r\na=rtpmap:$pt $name/8000');
    }
  }
  return text;
}
