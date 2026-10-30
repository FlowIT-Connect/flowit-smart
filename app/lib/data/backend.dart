import 'dart:math';
import 'dart:typed_data';

import '../models/models.dart';

/// Erreur métier présentée à l'utilisateur (message non révélateur, §5.1).
class BackendException implements Exception {
  final String code; // auth, denied, network, invalid, unknown
  final String message;

  const BackendException(this.code, this.message);

  @override
  String toString() => message;
}

/// Contrat entre l'interface et le backend FlowIT.
///
/// Deux implémentations : [SupabaseBackend] (production, RLS côté serveur) et
/// [DemoBackend] (données simulées en mémoire, sans serveur).
abstract class Backend {
  bool get isDemo;

  // --- Comptes (§5.1)
  String? get currentUserId;
  String? get currentEmail;
  Stream<bool> get authChanges;
  Future<void> signIn(String email, String password);
  Future<void> signUp(String email, String password, String displayName);
  Future<void> resetPassword(String email);
  Future<void> updatePassword(String newPassword);

  /// Émet quand l'utilisateur revient d'un lien de réinitialisation de mot de passe.
  Stream<void> get passwordRecovery;
  Future<void> signOut();
  Future<void> deleteAccount();
  Future<void> updateLocale(String locale);

  // --- Maisons et membres (§5.2)
  Future<List<Home>> listHomes();
  Future<Home> createHome(String name, String timezone);
  Future<void> renameHome(String homeId, String name);
  Future<void> deleteHome(String homeId);
  Future<List<Member>> listMembers(String homeId);
  Future<void> updateMember(String homeId, String userId, {HomeRole? role, List<String>? allowedDevices, bool clearRestriction = false});
  Future<void> removeMember(String homeId, String userId);
  Future<void> transferOwnership(String homeId, String newOwnerId);
  Future<Invitation> invite(String homeId, String email, HomeRole role);
  Future<List<Invitation>> listInvitations(String homeId);
  Future<void> revokeInvitation(String invitationId);
  Future<List<Invitation>> myInvitations();
  Future<String> acceptInvitation(String token);

  // --- Pièces
  Future<List<Room>> listRooms(String homeId);
  Future<Room> createRoom(String homeId, String name, String? icon, int sortOrder);
  Future<void> updateRoom(Room room);
  Future<void> deleteRoom(String roomId);

  // --- Appareils (§5.3)
  Future<List<Device>> listDevices(String homeId);
  Future<void> updateDevice(String deviceId, {String? name, String? roomId, bool clearRoom = false, bool? isPinned, bool? isHidden});

  /// Active (ou bloque) un appareil de sécurité : propriétaire uniquement, journalisé.
  Future<void> setDeviceSecurity(String deviceId, bool enabled);

  /// Codes d'accès créés pour une serrure, du plus récent au plus ancien.
  Future<List<AccessCode>> listAccessCodes(String deviceId);

  // --- Commandes (§5.4)
  Future<DeviceCommand> sendCommand({
    required String homeId,
    required String deviceId,
    required String capabilityKey,
    required dynamic value,
    required String idempotencyKey,
  });
  Future<DeviceCommand?> getCommand(String commandId);

  // --- Scènes (§5.9)
  Future<List<Scene>> listScenes(String homeId);
  Future<Scene> saveScene(Scene scene, {bool isNew = false});
  Future<void> deleteScene(String sceneId);
  Future<String> executeScene(String sceneId);
  Future<List<SceneRun>> listSceneRuns(String homeId, {int limit = 30});

  // --- Automatisations (§5.9)
  Future<List<Automation>> listAutomations(String homeId);
  Future<Automation> saveAutomation(Automation automation, {bool isNew = false});
  Future<void> deleteAutomation(String automationId);

  // --- Intégrations
  Future<List<Integration>> listIntegrations(String homeId);
  Future<String> createIntegration(String homeId, String provider, String? label);
  Future<void> setIntegrationEnabled(String integrationId, bool enabled);

  // --- Journal (§5.10)
  Future<List<EventLog>> listEvents(String homeId, {int limit = 100});

  // --- Caméras et photos d'appareils
  /// Images d'une caméra tant que le flux est écouté (la passerelle n'envoie rien sinon).
  Stream<CameraFrame> watchCamera(String homeId, String deviceId);

  /// Photo prise par l'utilisateur (bucket privé, accès vérifié côté serveur).
  Future<Uint8List> downloadDevicePhoto(String path);

  /// Enregistre la photo d'un appareil et renvoie son chemin (photo_path).
  Future<String> setDevicePhoto(Device device, Uint8List bytes, String contentType);

  /// Revient à la photo automatique (produit ou type d'appareil).
  Future<void> clearDevicePhoto(Device device);

  // --- Temps réel (§10)
  /// Flux des changements de la maison : devices, device_commands, scene_runs…
  /// [onStatus] reçoit `true` quand la connexion temps réel est active.
  Stream<RealtimeEvent> watchHome(String homeId, {void Function(bool connected)? onStatus});
}

/// Identifiant aléatoire RFC 4122 v4 (clé d'idempotence, ids démo).
/// Extension de fichier d'une image acceptée par les buckets (null si refusée).
String? imageExtension(String contentType) => switch (contentType.toLowerCase()) {
      'image/jpeg' || 'image/jpg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => null,
    };

String newUuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
