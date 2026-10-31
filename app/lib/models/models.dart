// Modèles applicatifs alignés sur le schéma Supabase (supabase/migrations).

import 'dart:typed_data';

import 'video.dart';

export 'video.dart';

enum HomeRole { owner, admin, member, installer }

enum Availability { available, unavailable, unknown }

enum CommandStatus { pending, sent, confirmed, failed, timeout, rejected }

enum FailurePolicy { continueOnError, stop }

T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

HomeRole homeRoleFrom(String? s) => _enumByName(HomeRole.values, s, HomeRole.member);

extension HomeRoleX on HomeRole {
  bool get canManage => this == HomeRole.owner || this == HomeRole.admin;
  bool get canConfigureDevices => canManage || this == HomeRole.installer;
}

class Home {
  final String id;
  final String ownerId;
  final String name;
  final String timezone;
  final HomeRole myRole;

  const Home({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.timezone,
    required this.myRole,
  });

  factory Home.fromJson(Map<String, dynamic> j, HomeRole role) => Home(
        id: j['id'] as String,
        ownerId: j['owner_id'] as String,
        name: j['name'] as String,
        timezone: (j['timezone'] as String?) ?? 'Africa/Algiers',
        myRole: role,
      );

  Home copyWith({String? name, HomeRole? myRole, String? ownerId}) => Home(
        id: id,
        ownerId: ownerId ?? this.ownerId,
        name: name ?? this.name,
        timezone: timezone,
        myRole: myRole ?? this.myRole,
      );
}

class Member {
  final String homeId;
  final String userId;
  final String displayName;
  final HomeRole role;

  /// Appareils autorisés (null = tous les appareils de la maison).
  final List<String>? allowedDevices;
  final DateTime? expiresAt;

  const Member({
    required this.homeId,
    required this.userId,
    required this.displayName,
    required this.role,
    this.allowedDevices,
    this.expiresAt,
  });

  factory Member.fromJson(Map<String, dynamic> j) {
    final perms = (j['permissions'] as Map?) ?? const {};
    final devices = perms['devices'];
    final profile = j['profiles'] as Map?;
    return Member(
      homeId: j['home_id'] as String,
      userId: j['user_id'] as String,
      displayName: (profile?['display_name'] as String?) ?? '—',
      role: homeRoleFrom(j['role'] as String?),
      allowedDevices: devices is List ? devices.cast<String>() : null,
      expiresAt: _date(j['expires_at']),
    );
  }
}

class Invitation {
  final String id;
  final String homeId;
  final String? homeName;
  final String? email;
  final HomeRole role;
  final String token;
  final DateTime expiresAt;
  final DateTime? acceptedAt;

  const Invitation({
    required this.id,
    required this.homeId,
    this.homeName,
    this.email,
    required this.role,
    required this.token,
    required this.expiresAt,
    this.acceptedAt,
  });

  factory Invitation.fromJson(Map<String, dynamic> j) => Invitation(
        id: j['id'] as String,
        homeId: j['home_id'] as String,
        homeName: j['home_name'] as String?,
        email: j['email'] as String?,
        role: homeRoleFrom(j['role'] as String?),
        token: j['token'] as String,
        expiresAt: _date(j['expires_at'])!,
        acceptedAt: _date(j['accepted_at']),
      );
}

class Room {
  final String id;
  final String homeId;
  final String name;
  final String? icon;
  final int sortOrder;

  const Room({required this.id, required this.homeId, required this.name, this.icon, this.sortOrder = 0});

  factory Room.fromJson(Map<String, dynamic> j) => Room(
        id: j['id'] as String,
        homeId: j['home_id'] as String,
        name: j['name'] as String,
        icon: j['icon'] as String?,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );

  Room copyWith({String? name, String? icon, int? sortOrder}) => Room(
        id: id,
        homeId: homeId,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}

/// Types de capacité (contrainte SQL device_capabilities.type).
enum CapabilityType { boolean, number, enumeration, color, string, sensor }

CapabilityType capabilityTypeFrom(String? s) => switch (s) {
      'boolean' => CapabilityType.boolean,
      'number' => CapabilityType.number,
      'enum' => CapabilityType.enumeration,
      'color' => CapabilityType.color,
      'sensor' => CapabilityType.sensor,
      _ => CapabilityType.string,
    };

class Capability {
  final String deviceId;
  final String key;
  final CapabilityType type;
  final bool writable;
  final Map<String, dynamic> metadata;

  const Capability({
    required this.deviceId,
    required this.key,
    required this.type,
    this.writable = true,
    this.metadata = const {},
  });

  factory Capability.fromJson(Map<String, dynamic> j) => Capability(
        deviceId: j['device_id'] as String,
        key: j['capability_key'] as String,
        type: capabilityTypeFrom(j['type'] as String?),
        writable: (j['writable'] as bool?) ?? true,
        metadata: Map<String, dynamic>.from((j['metadata'] as Map?) ?? const {}),
      );

  num get min => (metadata['min'] as num?) ?? 0;
  num get max => (metadata['max'] as num?) ?? 100;
  num get step => (metadata['step'] as num?) ?? 1;
  String? get unit => metadata['unit'] as String?;
  List<String> get options => ((metadata['options'] as List?) ?? const []).map((e) => e.toString()).toList();

  /// Capacité réellement pilotable depuis l'interface.
  bool get isControl => writable && type != CapabilityType.sensor;

  /// Flux d'images d'une caméra (lu par la passerelle, jamais une mesure à afficher).
  bool get isCamera => metadata['kind'] == 'camera';

  /// Affiché par le panneau de contrôle d'accès, pas comme une mesure.
  bool get isAccessDetail => metadata['kind'] == 'access_log' || metadata['kind'] == 'lock_state';
}

class Device {
  final String id;
  final String homeId;
  final String? roomId;
  final String name;
  final String? vendor;
  final String? model;
  final String protocol;
  final String connectionSource;
  final Availability availability;
  final Map<String, dynamic> state;
  final DateTime? lastSeenAt;
  final DateTime? updatedAt;
  final bool isPinned;
  final bool isHidden;
  final bool isSensitive;
  final List<Capability> capabilities;

  /// Photo officielle du produit fournie par la passerelle (ex. Tuya / Smart Life).
  final String? imageUrl;

  /// Photo prise par l'utilisateur (chemin dans le bucket privé device-photos).
  final String? photoPath;

  /// Activation par le propriétaire d'un appareil de sécurité (serrure) ; null = bloqué.
  final DateTime? securityValidatedAt;

  const Device({
    required this.id,
    required this.homeId,
    this.roomId,
    required this.name,
    this.vendor,
    this.model,
    required this.protocol,
    required this.connectionSource,
    required this.availability,
    this.state = const {},
    this.lastSeenAt,
    this.updatedAt,
    this.isPinned = false,
    this.isHidden = false,
    this.isSensitive = false,
    this.capabilities = const [],
    this.imageUrl,
    this.photoPath,
    this.securityValidatedAt,
  });

  factory Device.fromJson(Map<String, dynamic> j, {List<Capability>? capabilities}) => Device(
        id: j['id'] as String,
        homeId: j['home_id'] as String,
        roomId: j['room_id'] as String?,
        name: j['name'] as String,
        vendor: j['vendor'] as String?,
        model: j['model'] as String?,
        protocol: (j['protocol'] as String?) ?? 'other',
        connectionSource: (j['connection_source'] as String?) ?? 'gateway',
        availability: _enumByName(Availability.values, j['availability'] as String?, Availability.unknown),
        state: Map<String, dynamic>.from((j['state'] as Map?) ?? const {}),
        lastSeenAt: _date(j['last_seen_at']),
        updatedAt: _date(j['updated_at']),
        isPinned: (j['is_pinned'] as bool?) ?? false,
        isHidden: (j['is_hidden'] as bool?) ?? false,
        isSensitive: (j['is_sensitive'] as bool?) ?? false,
        imageUrl: j['image_url'] as String?,
        photoPath: j['photo_path'] as String?,
        securityValidatedAt: _date(j['security_validated_at']),
        capabilities: capabilities ??
            ((j['device_capabilities'] as List?) ?? const [])
                .map((c) => Capability.fromJson(Map<String, dynamic>.from(c as Map)))
                .toList(),
      );

  /// Fusionne une mise à jour temps réel (ligne devices sans capacités).
  Device mergeRow(Map<String, dynamic> row) => Device.fromJson(row, capabilities: capabilities);

  Device copyWith({
    String? name,
    String? roomId,
    bool clearRoom = false,
    bool? isPinned,
    bool? isHidden,
    Map<String, dynamic>? state,
    Availability? availability,
    DateTime? lastSeenAt,
    List<Capability>? capabilities,
    String? photoPath,
    bool clearPhoto = false,
    DateTime? securityValidatedAt,
    bool clearSecurity = false,
  }) =>
      Device(
        id: id,
        homeId: homeId,
        roomId: clearRoom ? null : (roomId ?? this.roomId),
        name: name ?? this.name,
        vendor: vendor,
        model: model,
        protocol: protocol,
        connectionSource: connectionSource,
        availability: availability ?? this.availability,
        state: state ?? this.state,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        updatedAt: DateTime.now(),
        isPinned: isPinned ?? this.isPinned,
        isHidden: isHidden ?? this.isHidden,
        isSensitive: isSensitive,
        capabilities: capabilities ?? this.capabilities,
        imageUrl: imageUrl,
        photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
        securityValidatedAt: clearSecurity ? null : (securityValidatedAt ?? this.securityValidatedAt),
      );

  Capability? capability(String key) {
    for (final c in capabilities) {
      if (c.key == key) return c;
    }
    return null;
  }

  bool get isOnline => availability == Availability.available;
  List<Capability> get controls => capabilities.where((c) => c.isControl).toList();
  List<Capability> get readings => capabilities.where((c) => !c.isControl && !c.isCamera && !c.isAccessDetail).toList();

  /// Caméra IP : image en direct dans la fiche.
  bool get isCamera => capabilities.any((c) => c.isCamera);

  /// Capacité « camera » (null si l'appareil n'est pas une caméra).
  Capability? get cameraCapability {
    for (final c in capabilities) {
      if (c.isCamera) return c;
    }
    return null;
  }

  /// Vidéo fluide WebRTC par le boîtier vidéo (sinon : images fixes).
  bool get hasLiveVideo => cameraCapability?.metadata['live'] == 'webrtc';

  /// Capacités déclarées par le boîtier vidéo (UDI).
  UdiCapabilities get udi => UdiCapabilities.fromJson(cameraCapability?.metadata['udi']);

  /// Caméra ou visiophone (métadonnée « category » posée par le boîtier).
  bool get isIntercom => cameraCapability?.metadata['category'] == 'intercom';

  /// Interrupteur principal (tuile : appui = bascule).
  Capability? get primarySwitch => capability('switch');
  bool? get isOn => state['switch'] is bool ? state['switch'] as bool : null;

  /// Serrure ou contrôle d'accès (TTLock) : codes d'accès, historique, ouverture.
  bool get isAccessControl => capability('access_code') != null;

  /// Appareil de sécurité activé par le propriétaire : commandes manuelles permises.
  bool get isSecurityEnabled => isSensitive && securityValidatedAt != null;

  /// Commandes refusées par le serveur (appareil de sécurité non activé).
  bool get isBlocked => isSensitive && securityValidatedAt == null;

  /// L'appareil n'expose aucune commande prise en charge.
  bool get isUnsupported => controls.isEmpty && readings.isEmpty && !isCamera;
}

/// Code au clavier d'une serrure, créé par la passerelle (propriétaire et administrateurs).
/// Demande d'ajout d'un appareil, traitée par la passerelle (table pairing_requests).
class PairingRequest {
  final String id;
  final String kind; // ttlock_lock, scan
  final String status; // pending, working, done, failed
  final String? error;
  final String? deviceId;

  const PairingRequest({required this.id, required this.kind, required this.status, this.error, this.deviceId});

  bool get isFinished => status == 'done' || status == 'failed';

  factory PairingRequest.fromJson(Map<String, dynamic> j) => PairingRequest(
        id: j['id'] as String,
        kind: j['kind'] as String,
        status: j['status'] as String,
        error: j['error'] as String?,
        deviceId: j['device_id'] as String?,
      );
}

class AccessCode {
  final String id;
  final String deviceId;
  final String? commandId;
  final String kind; // one_time, period, permanent
  final String? name;
  final String code;
  final DateTime startsAt;
  final DateTime? endsAt;
  final DateTime? createdAt;

  const AccessCode({
    required this.id,
    required this.deviceId,
    this.commandId,
    required this.kind,
    this.name,
    required this.code,
    required this.startsAt,
    this.endsAt,
    this.createdAt,
  });

  factory AccessCode.fromJson(Map<String, dynamic> j) => AccessCode(
        id: j['id'] as String,
        deviceId: j['device_id'] as String,
        commandId: j['command_id'] as String?,
        kind: j['kind'] as String,
        name: j['name'] as String?,
        code: j['code'] as String,
        startsAt: _date(j['starts_at']) ?? DateTime.now(),
        endsAt: _date(j['ends_at']),
        createdAt: _date(j['created_at']),
      );

  /// Code encore utilisable (un code unique peut déjà avoir servi : la serrure seule le sait).
  bool get isActive => endsAt == null || endsAt!.isAfter(DateTime.now());
}

/// Passage enregistré par une serrure (état « access_log » écrit par la passerelle).
class AccessRecord {
  final DateTime at;
  final String method; // app, code, card, fingerprint, key, remote, other
  final bool ok;
  final String? who;

  const AccessRecord({required this.at, required this.method, required this.ok, this.who});

  static List<AccessRecord> fromState(dynamic v) => v is! List
      ? const []
      : [
          for (final r in v.whereType<Map>())
            if (_date(r['at']) case final at?) AccessRecord(at: at, method: '${r['method'] ?? 'other'}', ok: r['ok'] != false, who: r['who'] as String?),
        ];
}

/// Accès partagé : clé électronique TTLock d'une autre personne (état « ekeys » écrit par la passerelle).
class SharedKey {
  final int id;
  final String? name;
  final String receiver;
  final String status; // active, frozen, pending, unknown
  final DateTime? start;
  final DateTime? end;

  const SharedKey({required this.id, this.name, required this.receiver, required this.status, this.start, this.end});

  bool get isFrozen => status == 'frozen';

  /// Programmé entre deux dates (sinon permanent).
  bool get isScheduled => start != null && end != null;

  bool get isExpired => end != null && end!.isBefore(DateTime.now());

  static List<SharedKey> fromState(dynamic v) => v is! List
      ? const []
      : [
          for (final k in v.whereType<Map>())
            if (k['id'] case final int id)
              SharedKey(
                id: id,
                name: k['name'] as String?,
                receiver: '${k['receiver'] ?? ''}',
                status: '${k['status'] ?? 'unknown'}',
                start: _date(k['start']),
                end: _date(k['end']),
              ),
        ];
}

class DeviceCommand {
  final String id;
  final String homeId;
  final String deviceId;
  final String capabilityKey;
  final dynamic value;
  final CommandStatus status;
  final String? error;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? sceneRunId;

  const DeviceCommand({
    required this.id,
    required this.homeId,
    required this.deviceId,
    required this.capabilityKey,
    required this.value,
    required this.status,
    this.error,
    required this.createdAt,
    this.completedAt,
    this.sceneRunId,
  });

  factory DeviceCommand.fromJson(Map<String, dynamic> j) => DeviceCommand(
        id: j['id'] as String,
        homeId: j['home_id'] as String,
        deviceId: j['device_id'] as String,
        capabilityKey: j['capability_key'] as String,
        value: j['value'],
        status: _enumByName(CommandStatus.values, j['status'] as String?, CommandStatus.pending),
        error: j['error'] as String?,
        createdAt: _date(j['created_at']) ?? DateTime.now(),
        completedAt: _date(j['completed_at']),
        sceneRunId: j['scene_run_id'] as String?,
      );

  DeviceCommand copyWith({CommandStatus? status, String? error}) => DeviceCommand(
        id: id,
        homeId: homeId,
        deviceId: deviceId,
        capabilityKey: capabilityKey,
        value: value,
        status: status ?? this.status,
        error: error ?? this.error,
        createdAt: createdAt,
        completedAt: DateTime.now(),
        sceneRunId: sceneRunId,
      );

  bool get isWaiting => status == CommandStatus.pending || status == CommandStatus.sent;
}

class SceneAction {
  final String? id;
  final String deviceId;
  final String capabilityKey;
  final dynamic value;
  final int position;
  final int delayMs;

  const SceneAction({
    this.id,
    required this.deviceId,
    required this.capabilityKey,
    required this.value,
    this.position = 0,
    this.delayMs = 0,
  });

  factory SceneAction.fromJson(Map<String, dynamic> j) => SceneAction(
        id: j['id'] as String?,
        deviceId: j['device_id'] as String,
        capabilityKey: j['capability_key'] as String,
        value: j['value'],
        position: (j['position'] as num?)?.toInt() ?? 0,
        delayMs: (j['delay_ms'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson(String sceneId, int index) => {
        'scene_id': sceneId,
        'device_id': deviceId,
        'capability_key': capabilityKey,
        'value': value,
        'position': index,
        'delay_ms': delayMs,
      };
}

class Scene {
  final String id;
  final String homeId;
  final String name;
  final String? icon;
  final bool enabled;
  final FailurePolicy failurePolicy;
  final List<SceneAction> actions;

  const Scene({
    required this.id,
    required this.homeId,
    required this.name,
    this.icon,
    this.enabled = true,
    this.failurePolicy = FailurePolicy.continueOnError,
    this.actions = const [],
  });

  factory Scene.fromJson(Map<String, dynamic> j) {
    final actions = ((j['scene_actions'] as List?) ?? const [])
        .map((a) => SceneAction.fromJson(Map<String, dynamic>.from(a as Map)))
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    return Scene(
      id: j['id'] as String,
      homeId: j['home_id'] as String,
      name: j['name'] as String,
      icon: j['icon'] as String?,
      enabled: (j['enabled'] as bool?) ?? true,
      failurePolicy: j['failure_policy'] == 'stop' ? FailurePolicy.stop : FailurePolicy.continueOnError,
      actions: actions,
    );
  }

  Scene copyWith({String? name, String? icon, bool? enabled, FailurePolicy? failurePolicy, List<SceneAction>? actions}) =>
      Scene(
        id: id,
        homeId: homeId,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        enabled: enabled ?? this.enabled,
        failurePolicy: failurePolicy ?? this.failurePolicy,
        actions: actions ?? this.actions,
      );
}

class SceneRun {
  final String id;
  final String sceneId;
  final String status; // running, success, partial, failed
  final List<Map<String, dynamic>> results;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String? automationId;

  const SceneRun({
    required this.id,
    required this.sceneId,
    required this.status,
    this.results = const [],
    required this.startedAt,
    this.finishedAt,
    this.automationId,
  });

  factory SceneRun.fromJson(Map<String, dynamic> j) => SceneRun(
        id: j['id'] as String,
        sceneId: j['scene_id'] as String,
        status: (j['status'] as String?) ?? 'running',
        results: ((j['results'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        startedAt: _date(j['started_at']) ?? DateTime.now(),
        finishedAt: _date(j['finished_at']),
        automationId: j['automation_id'] as String?,
      );
}

/// Automatisation : JSON identique au contrat SQL (voir migration init, §5.9).
class Automation {
  final String id;
  final String homeId;
  final String name;
  final bool enabled;
  final Map<String, dynamic> trigger;
  final List<Map<String, dynamic>> conditions;
  final List<Map<String, dynamic>> actions;
  final bool runLocally;
  final DateTime? lastRunAt;

  const Automation({
    required this.id,
    required this.homeId,
    required this.name,
    this.enabled = true,
    required this.trigger,
    this.conditions = const [],
    required this.actions,
    this.runLocally = true,
    this.lastRunAt,
  });

  factory Automation.fromJson(Map<String, dynamic> j) => Automation(
        id: j['id'] as String,
        homeId: j['home_id'] as String,
        name: j['name'] as String,
        enabled: (j['enabled'] as bool?) ?? true,
        trigger: Map<String, dynamic>.from(j['trigger'] as Map),
        conditions: ((j['conditions'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        actions: ((j['actions'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        runLocally: (j['run_locally'] as bool?) ?? true,
        lastRunAt: _date(j['last_run_at']),
      );

  Map<String, dynamic> toJson() => {
        'home_id': homeId,
        'name': name,
        'enabled': enabled,
        'trigger': trigger,
        'conditions': conditions,
        'actions': actions,
        'run_locally': runLocally,
      };

  Automation copyWith({bool? enabled}) => Automation(
        id: id,
        homeId: homeId,
        name: name,
        enabled: enabled ?? this.enabled,
        trigger: trigger,
        conditions: conditions,
        actions: actions,
        runLocally: runLocally,
        lastRunAt: lastRunAt,
      );
}

class EventLog {
  final int id;
  final String eventType;
  final String? deviceId;
  final String? result;
  final Map<String, dynamic> details;
  final DateTime createdAt;

  const EventLog({
    required this.id,
    required this.eventType,
    this.deviceId,
    this.result,
    this.details = const {},
    required this.createdAt,
  });

  factory EventLog.fromJson(Map<String, dynamic> j) => EventLog(
        id: (j['id'] as num).toInt(),
        eventType: j['event_type'] as String,
        deviceId: j['device_id'] as String?,
        result: j['result'] as String?,
        details: Map<String, dynamic>.from((j['details'] as Map?) ?? const {}),
        createdAt: _date(j['created_at']) ?? DateTime.now(),
      );
}

class Integration {
  final String id;
  final String homeId;
  final String provider;
  final String status;
  final String? label;
  final DateTime? lastSyncAt;
  final String? lastError;

  const Integration({
    required this.id,
    required this.homeId,
    required this.provider,
    required this.status,
    this.label,
    this.lastSyncAt,
    this.lastError,
  });

  factory Integration.fromJson(Map<String, dynamic> j) => Integration(
        id: j['id'] as String,
        homeId: j['home_id'] as String,
        provider: j['provider'] as String,
        status: j['status'] as String,
        label: j['label'] as String?,
        lastSyncAt: _date(j['last_sync_at']),
        lastError: j['last_error'] as String?,
      );
}

/// Image d'une caméra reçue de la passerelle.
class CameraFrame {
  final Uint8List bytes;
  final DateTime at;

  /// false : dernière image connue, en attendant que la passerelle envoie la suivante.
  final bool live;

  const CameraFrame(this.bytes, this.at, {this.live = true});
}

/// Évènement temps réel transmis par le backend (Supabase Realtime ou démo).
class RealtimeEvent {
  final String table;
  final String type; // INSERT, UPDATE, DELETE
  final Map<String, dynamic> record;

  const RealtimeEvent(this.table, this.type, this.record);
}

/// Offre d'un logement : 5 appareils gratuits, davantage après paiement.
class HomePlan {
  final int deviceCount;
  final int deviceLimit;
  final DateTime? paidUntil; // null : offre gratuite, ou déblocage sans date de fin
  final int waitingDevices; // appareils vus par la passerelle mais refusés faute de place
  final bool pendingRequest;
  final bool managed; // appareils posés et attribués par l'installateur Solea

  const HomePlan({required this.deviceCount, required this.deviceLimit, this.paidUntil, this.waitingDevices = 0, this.pendingRequest = false, this.managed = false});

  static const freeLimit = 5;

  bool get isFull => deviceCount >= deviceLimit;
  bool get isPaid => deviceLimit > freeLimit;

  factory HomePlan.fromJson(Map<String, dynamic> j) => HomePlan(
        deviceCount: (j['device_count'] as num).toInt(),
        deviceLimit: (j['device_limit'] as num).toInt(),
        paidUntil: j['paid_until'] == null ? null : DateTime.parse(j['paid_until'] as String),
        waitingDevices: (j['waiting_devices'] as num?)?.toInt() ?? 0,
        pendingRequest: j['pending_request'] as bool? ?? false,
        managed: j['managed'] as bool? ?? false,
      );
}

/// Demande de déblocage, vue par l'exploitant Solea (page « Paiements »).
class UpgradeRequest {
  final String id;
  final String homeId;
  final String homeName;
  final String? ownerEmail;
  final String? ownerName;
  final String status; // pending, approved, rejected
  final String? note;
  final int deviceCount;
  final int deviceLimit;
  final DateTime? paidUntil;
  final int waitingDevices;
  final DateTime createdAt;

  const UpgradeRequest({
    required this.id,
    required this.homeId,
    required this.homeName,
    this.ownerEmail,
    this.ownerName,
    required this.status,
    this.note,
    required this.deviceCount,
    required this.deviceLimit,
    this.paidUntil,
    this.waitingDevices = 0,
    required this.createdAt,
  });

  bool get isPending => status == 'pending';

  factory UpgradeRequest.fromJson(Map<String, dynamic> j) => UpgradeRequest(
        id: j['request_id'] as String,
        homeId: j['home_id'] as String,
        homeName: j['home_name'] as String? ?? '—',
        ownerEmail: j['owner_email'] as String?,
        ownerName: j['owner_name'] as String?,
        status: j['status'] as String,
        note: j['note'] as String?,
        deviceCount: (j['device_count'] as num).toInt(),
        deviceLimit: (j['device_limit'] as num).toInt(),
        paidUntil: j['paid_until'] == null ? null : DateTime.parse(j['paid_until'] as String),
        waitingDevices: (j['waiting_devices'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

/// Appareil du compte installateur (passerelle de la plateforme), vu par l'exploitant.
class PlatformDevice {
  final String externalId;
  final String name;
  final String? vendor;
  final String? model;
  final String? imageUrl;
  final String? homeId;
  final String? homeName;
  final bool installed; // créé dans le logement par la passerelle
  final DateTime lastSeenAt;

  const PlatformDevice({
    required this.externalId,
    required this.name,
    this.vendor,
    this.model,
    this.imageUrl,
    this.homeId,
    this.homeName,
    this.installed = false,
    required this.lastSeenAt,
  });

  bool get isAssigned => homeId != null;

  factory PlatformDevice.fromJson(Map<String, dynamic> j) => PlatformDevice(
        externalId: j['external_id'] as String,
        name: j['name'] as String,
        vendor: j['vendor'] as String?,
        model: j['model'] as String?,
        imageUrl: j['image_url'] as String?,
        homeId: j['home_id'] as String?,
        homeName: j['home_name'] as String?,
        installed: j['installed'] as bool? ?? false,
        lastSeenAt: DateTime.parse(j['last_seen_at'] as String),
      );
}

/// Logement trouvé par l'exploitant (nom ou e-mail du propriétaire).
class HomeSummary {
  final String id;
  final String name;
  final String? ownerEmail;
  final int deviceCount;
  final int deviceLimit;

  const HomeSummary({required this.id, required this.name, this.ownerEmail, required this.deviceCount, required this.deviceLimit});

  bool get isFull => deviceCount >= deviceLimit;

  factory HomeSummary.fromJson(Map<String, dynamic> j) => HomeSummary(
        id: j['home_id'] as String,
        name: j['home_name'] as String,
        ownerEmail: j['owner_email'] as String?,
        deviceCount: (j['device_count'] as num).toInt(),
        deviceLimit: (j['device_limit'] as num).toInt(),
      );
}
