// Modèles du module « Sécurité et vidéo » (interphonie, caméras ONVIF / RTSP).

/// Capacités UDI réellement utilisables (§3.4 du cahier des charges) : une capacité
/// absente ou fausse n'est jamais proposée dans l'interface.
class UdiCapabilities {
  const UdiCapabilities(this.flags);

  final Map<String, bool> flags;

  factory UdiCapabilities.fromJson(Object? j) {
    final m = (j is Map) ? j : const {};
    return UdiCapabilities({for (final e in m.entries) e.key.toString(): e.value == true});
  }

  bool has(String key) => flags[key] == true;
  bool get video => has('video_stream');
  bool get snapshot => has('snapshot');
  bool get microphone => has('audio_input');
  bool get motion => has('motion_detection');

  /// Clés vraies, dans l'ordre d'affichage.
  List<String> get enabled => [
        for (final k in const ['video_stream', 'snapshot', 'audio_input', 'audio_output', 'motion_detection', 'human_detection', 'ptz_control', 'door_relay', 'sip_call'])
          if (has(k)) k,
      ];
}

class DiagnosticStep {
  const DiagnosticStep(this.step, this.ok, this.detail);
  final String step;
  final bool ok;
  final String? detail;

  factory DiagnosticStep.fromJson(Map j) => DiagnosticStep(j['step']?.toString() ?? '?', j['ok'] == true, j['detail']?.toString());
}

enum VideoSourceStatus { pending, connecting, online, offline, authError, error }

VideoSourceStatus videoStatusFrom(String? s) => switch (s) {
      'connecting' => VideoSourceStatus.connecting,
      'online' => VideoSourceStatus.online,
      'offline' => VideoSourceStatus.offline,
      'auth_error' => VideoSourceStatus.authError,
      'error' => VideoSourceStatus.error,
      _ => VideoSourceStatus.pending,
    };

/// Équipement vidéo déclaré (visible des gestionnaires du logement seulement).
class VideoSource {
  final String id;
  final String homeId;
  final String? deviceId;
  final String name;
  final String category; // camera | intercom | access | monitor | sensor
  final String driver; // onvif | rtsp
  final String? host;
  final int? port;
  final String? rtspUrl;
  final String? snapshotUrl;
  final String? manufacturer;
  final String? model;
  final String? firmware;
  final String? location;
  final VideoSourceStatus status;
  final String? lastError;
  final UdiCapabilities capabilities;
  final List<DiagnosticStep> steps;
  final Map<String, dynamic> detected;
  final DateTime? diagnosedAt;
  final DateTime? testRequestedAt;
  final DateTime? lastSeenAt;

  const VideoSource({
    required this.id,
    required this.homeId,
    this.deviceId,
    required this.name,
    this.category = 'camera',
    this.driver = 'onvif',
    this.host,
    this.port,
    this.rtspUrl,
    this.snapshotUrl,
    this.manufacturer,
    this.model,
    this.firmware,
    this.location,
    this.status = VideoSourceStatus.pending,
    this.lastError,
    this.capabilities = const UdiCapabilities({}),
    this.steps = const [],
    this.detected = const {},
    this.diagnosedAt,
    this.testRequestedAt,
    this.lastSeenAt,
  });

  factory VideoSource.fromJson(Map<String, dynamic> j) {
    final diag = (j['diagnostic'] as Map?) ?? const {};
    DateTime? ts(String k) => j[k] == null ? null : DateTime.tryParse(j[k] as String)?.toLocal();
    return VideoSource(
      id: j['id'] as String,
      homeId: j['home_id'] as String,
      deviceId: j['device_id'] as String?,
      name: j['name'] as String,
      category: (j['category'] as String?) ?? 'camera',
      driver: (j['driver'] as String?) ?? 'onvif',
      host: j['host'] as String?,
      port: (j['port'] as num?)?.toInt(),
      rtspUrl: j['rtsp_url'] as String?,
      snapshotUrl: j['snapshot_url'] as String?,
      manufacturer: j['manufacturer'] as String?,
      model: j['model'] as String?,
      firmware: j['firmware'] as String?,
      location: j['location'] as String?,
      status: videoStatusFrom(j['status'] as String?),
      lastError: j['last_error'] as String?,
      capabilities: UdiCapabilities.fromJson(j['capabilities']),
      steps: ((diag['steps'] as List?) ?? const []).whereType<Map>().map(DiagnosticStep.fromJson).toList(),
      detected: Map<String, dynamic>.from((diag['detected'] as Map?) ?? const {}),
      diagnosedAt: ts('diagnosed_at'),
      testRequestedAt: ts('test_requested_at'),
      lastSeenAt: ts('last_seen_at'),
    );
  }

  bool get isIntercom => category == 'intercom';

  /// Un diagnostic a été demandé et le boîtier n'a pas encore répondu.
  bool get testing =>
      status == VideoSourceStatus.pending ||
      status == VideoSourceStatus.connecting ||
      (testRequestedAt != null && (diagnosedAt == null || diagnosedAt!.isBefore(testRequestedAt!)));

  String get address => driver == 'onvif' ? '${host ?? '?'}:${port ?? 80}' : (rtspUrl ?? '—');
}

/// Saisie d'un nouvel équipement (les identifiants ne sont jamais relus ensuite).
class VideoSourceDraft {
  VideoSourceDraft({
    this.name = '',
    this.category = 'camera',
    this.driver = 'onvif',
    this.host = '',
    this.port = 80,
    this.rtspUrl = '',
    this.snapshotUrl = '',
    this.username = '',
    this.password = '',
    this.location = '',
  });

  String name;
  String category;
  String driver;
  String host;
  int port;
  String rtspUrl;
  String snapshotUrl;
  String username;
  String password;
  String location;
}

class ScanResult {
  const ScanResult({required this.host, required this.port, this.name, this.hardware, this.alreadyAdded = false});
  final String host;
  final int port;
  final String? name;
  final String? hardware;
  final bool alreadyAdded;

  factory ScanResult.fromJson(Map j) => ScanResult(
        host: j['host']?.toString() ?? '?',
        port: (j['port'] as num?)?.toInt() ?? 80,
        name: j['name']?.toString(),
        hardware: j['hardware']?.toString(),
        alreadyAdded: j['already_added'] == true,
      );
}

class VideoScan {
  const VideoScan({required this.id, required this.status, this.results = const [], this.error});
  final String id;
  final String status; // pending | running | done | failed
  final List<ScanResult> results;
  final String? error;

  bool get finished => status == 'done' || status == 'failed';

  factory VideoScan.fromJson(Map<String, dynamic> j) => VideoScan(
        id: j['id'] as String,
        status: j['status'] as String,
        results: ((j['results'] as List?) ?? const []).whereType<Map>().map(ScanResult.fromJson).toList(),
        error: j['error'] as String?,
      );
}

/// Boîtier vidéo installé dans le logement (passerelle + relais MediaMTX).
class MediaGateway {
  const MediaGateway({this.iceServers = const [], this.relayOk = false, this.discovery = false, this.lastSeenAt});
  final List<Map<String, dynamic>> iceServers;
  final bool relayOk;
  final bool discovery;
  final DateTime? lastSeenAt;

  factory MediaGateway.fromJson(Map<String, dynamic> j) => MediaGateway(
        iceServers: ((j['ice_servers'] as List?) ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList(),
        relayOk: j['relay_ok'] == true,
        discovery: j['discovery'] == true,
        lastSeenAt: j['last_seen_at'] == null ? null : DateTime.tryParse(j['last_seen_at'] as String)?.toLocal(),
      );

  /// Le boîtier se signale chaque minute.
  bool get online => lastSeenAt != null && DateTime.now().difference(lastSeenAt!) < const Duration(minutes: 3);
  bool get liveReady => online && relayOk;
}

class VideoSessionInfo {
  const VideoSessionInfo({required this.id, required this.status, this.answer, this.error});
  final String id;
  final String status; // offer | answered | failed | closed
  final String? answer;
  final String? error;

  factory VideoSessionInfo.fromJson(Map<String, dynamic> j) =>
      VideoSessionInfo(id: j['id'] as String, status: j['status'] as String, answer: j['answer'] as String?, error: j['error'] as String?);
}
