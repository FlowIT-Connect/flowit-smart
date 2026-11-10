import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';

import '../core/climate.dart';
import '../core/home_modes.dart';
import '../core/notifications.dart';
import '../models/models.dart';
import 'backend.dart';

/// Backend de production : Supabase (Auth + PostgREST + Realtime).
///
/// Le client n'utilise que la clé publique (anon/publishable). Toutes les
/// autorisations sont vérifiées côté serveur par les politiques RLS et les
/// fonctions `security definer` des migrations.
class SupabaseBackend implements Backend {
  SupabaseBackend(this._client);

  final SupabaseClient _client;

  @override
  bool get isDemo => false;

  GoTrueClient get _auth => _client.auth;

  /// Où le lien de l'e-mail ramène : la page web actuelle (app.solea-dz.com…)
  /// ou l'app installée sur le téléphone (lien solea://).
  static String get authRedirect => kIsWeb ? '${Uri.base.origin}${Uri.base.path}' : AppConfig.authRedirectMobile;

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on AuthException catch (e) {
      // Messages non révélateurs (§5.1)
      final msg = e.message.toLowerCase();
      if (msg.contains('rate') || e.statusCode == '429') {
        throw const BackendException('rate', 'Trop de tentatives. Réessayez plus tard.');
      }
      if (msg.contains('not confirmed')) {
        throw const BackendException('unconfirmed', 'Adresse e-mail pas encore confirmée.');
      }
      if (msg.contains('password') && msg.contains('characters')) {
        throw BackendException('invalid', e.message);
      }
      throw const BackendException('auth', 'Identifiants invalides ou compte non vérifié.');
    } on PostgrestException catch (e) {
      if (e.code == '42501' || e.code == 'PGRST301') {
        throw const BackendException('denied', 'Accès refusé.');
      }
      if (e.message.contains('LIMITE_APPAREILS')) throw BackendException('limit', e.message);
      if (e.message.contains('IDENTIFIANTS_DANS_URL') || e.message.contains('TROP_DE_DEMANDES_VIDEO') || e.message.contains('CAMERA_DEJA_AJOUTEE')) {
        throw BackendException('invalid', e.message.replaceFirst(RegExp(r'^[A-Z_]+ : '), ''));
      }
      if (e.code == 'P0001') throw BackendException('invalid', e.message);
      if (e.code == '23505') throw const BackendException('invalid', 'Cet élément existe déjà.');
      throw BackendException('unknown', e.message);
    } on StorageException catch (e) {
      if (e.statusCode == '401' || e.statusCode == '403') throw const BackendException('denied', 'Accès refusé.');
      if (e.statusCode == '404' || (e.statusCode == '400' && e.message.toLowerCase().contains('not found'))) {
        throw const BackendException('notFound', 'Image introuvable.');
      }
      if (e.statusCode == '413') throw const BackendException('invalid', 'Image trop lourde.');
      throw BackendException('unknown', e.message);
    } on BackendException {
      rethrow;
    } catch (e) {
      final s = e.toString();
      if (s.contains('SocketException') || s.contains('ClientException') || s.contains('Failed host lookup') || s.contains('XMLHttpRequest')) {
        throw const BackendException('network', 'Connexion au serveur impossible.');
      }
      throw BackendException('unknown', s);
    }
  }

  String get _uid {
    final id = _auth.currentUser?.id;
    if (id == null) throw const BackendException('auth', 'Session expirée.');
    return id;
  }

  // ---------------------------------------------------------------- Comptes
  @override
  String? get currentUserId => _auth.currentUser?.id;

  @override
  String? get currentEmail => _auth.currentUser?.email;

  @override
  Stream<bool> get authChanges => _auth.onAuthStateChange.map((s) => s.session != null);

  @override
  Stream<void> get passwordRecovery =>
      _auth.onAuthStateChange.where((s) => s.event == AuthChangeEvent.passwordRecovery).map((_) {});

  @override
  Future<void> signIn(String email, String password) =>
      _guard(() => _auth.signInWithPassword(email: email.trim(), password: password));

  @override
  Future<void> signUp(String email, String password, String displayName) => _guard(() async {
        await _auth.signUp(
            email: email.trim(), password: password, data: {'display_name': displayName.trim()}, emailRedirectTo: authRedirect);
      });

  @override
  Future<void> resetPassword(String email) => _guard(() => _auth.resetPasswordForEmail(email.trim(), redirectTo: authRedirect));

  @override
  Future<void> resendConfirmation(String email) => _guard(() => _auth.resend(type: OtpType.signup, email: email.trim(), emailRedirectTo: authRedirect));

  @override
  Future<void> updatePassword(String newPassword) =>
      _guard(() => _auth.updateUser(UserAttributes(password: newPassword)));

  @override
  Future<void> signOut() => _guard(() => _auth.signOut());

  @override
  Future<void> deleteAccount() => _guard(() async {
        await _client.rpc('delete_my_account');
        await _auth.signOut(scope: SignOutScope.local);
      });

  @override
  Future<void> updateLocale(String locale) =>
      _guard(() => _client.from('profiles').update({'locale': locale}).eq('id', _uid));

  @override
  Future<Map<String, dynamic>?> getPreferences() => _guard(() async {
        final row = await _client.from('profiles').select('preferences').eq('id', _uid).maybeSingle();
        final p = row?['preferences'];
        return p is Map ? Map<String, dynamic>.from(p) : null;
      });

  @override
  Future<void> savePreferences(Map<String, dynamic> preferences) =>
      _guard(() => _client.from('profiles').update({'preferences': preferences}).eq('id', _uid));

  @override
  Future<String> uploadBackground(Uint8List bytes, String contentType) => _guard(() async {
        final ext = imageExtension(contentType);
        if (ext == null) throw const BackendException('invalid', 'Format d\'image non pris en charge (JPEG, PNG ou WebP).');
        final path = '$_uid/bg-${DateTime.now().millisecondsSinceEpoch}.$ext';
        await _client.storage.from('backgrounds').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: contentType, cacheControl: '31536000'),
            );
        return path;
      });

  @override
  Future<Uint8List> downloadBackground(String path) => _guard(() => _client.storage.from('backgrounds').download(path));

  @override
  Future<void> deleteBackground(String path) async {
    try {
      await _client.storage.from('backgrounds').remove([path]);
    } catch (_) {
      // Ancienne photo orpheline : sans conséquence.
    }
  }

  // ---------------------------------------------------------------- Maisons
  @override
  Future<List<Home>> listHomes() => _guard(() async {
        final rows = await _client.from('home_members').select('role, homes(*)').eq('user_id', _uid);
        return rows
            .where((r) => r['homes'] != null)
            .map((r) => Home.fromJson(Map<String, dynamic>.from(r['homes'] as Map), homeRoleFrom(r['role'] as String?)))
            .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      });

  @override
  Future<Home> createHome(String name, String timezone) => _guard(() async {
        final id = await _client.rpc('create_home', params: {'p_name': name, 'p_timezone': timezone}) as String;
        final row = await _client.from('homes').select().eq('id', id).single();
        return Home.fromJson(row, HomeRole.owner);
      });

  @override
  Future<void> renameHome(String homeId, String name) =>
      _guard(() => _client.from('homes').update({'name': name.trim()}).eq('id', homeId));

  @override
  Future<void> updateHomeLocation(String homeId, double latitude, double longitude, String? name) => _guard(() => _client
      .from('homes')
      .update({'latitude': double.parse(latitude.toStringAsFixed(5)), 'longitude': double.parse(longitude.toStringAsFixed(5)), 'location_name': name})
      .eq('id', homeId));

  @override
  Future<void> deleteHome(String homeId) => _guard(() => _client.from('homes').delete().eq('id', homeId));

  @override
  Future<List<Member>> listMembers(String homeId) => _guard(() async {
        final rows = await _client
            .from('home_members')
            .select('home_id, user_id, role, permissions, expires_at, profiles!home_members_user_id_fkey(display_name)')
            .eq('home_id', homeId)
            .order('created_at');
        return rows.map(Member.fromJson).toList();
      });

  @override
  Future<void> updateMember(String homeId, String userId,
          {HomeRole? role, List<String>? allowedDevices, bool clearRestriction = false}) =>
      _guard(() async {
        final patch = <String, dynamic>{};
        if (role != null) patch['role'] = role.name;
        if (clearRestriction) {
          patch['permissions'] = <String, dynamic>{};
        } else if (allowedDevices != null) {
          patch['permissions'] = {'devices': allowedDevices};
        }
        if (patch.isEmpty) return;
        await _client.from('home_members').update(patch).eq('home_id', homeId).eq('user_id', userId);
      });

  @override
  Future<void> removeMember(String homeId, String userId) =>
      _guard(() => _client.from('home_members').delete().eq('home_id', homeId).eq('user_id', userId));

  @override
  Future<void> transferOwnership(String homeId, String newOwnerId) => _guard(
      () => _client.rpc('transfer_home_ownership', params: {'p_home_id': homeId, 'p_new_owner': newOwnerId}));

  @override
  Future<Invitation> invite(String homeId, String email, HomeRole role) => _guard(() async {
        final row = await _client
            .from('home_invitations')
            .insert({'home_id': homeId, 'email': email.trim().toLowerCase(), 'role': role.name, 'invited_by': _uid})
            .select()
            .single();
        return Invitation.fromJson(row);
      });

  @override
  Future<List<Invitation>> listInvitations(String homeId) => _guard(() async {
        final rows = await _client
            .from('home_invitations')
            .select()
            .eq('home_id', homeId)
            .isFilter('accepted_at', null)
            .gt('expires_at', DateTime.now().toUtc().toIso8601String())
            .order('created_at', ascending: false);
        return rows.map(Invitation.fromJson).toList();
      });

  @override
  Future<void> revokeInvitation(String invitationId) =>
      _guard(() => _client.from('home_invitations').delete().eq('id', invitationId));

  @override
  Future<List<Invitation>> myInvitations() => _guard(() async {
        final rows = await _client.rpc('list_my_invitations') as List;
        return rows.map((r) => Invitation.fromJson(Map<String, dynamic>.from(r as Map))).toList();
      });

  @override
  Future<String> acceptInvitation(String token) =>
      _guard(() async => await _client.rpc('accept_home_invitation', params: {'p_token': token.trim()}) as String);

  // ---------------------------------------------------------------- Pièces
  @override
  Future<List<Room>> listRooms(String homeId) => _guard(() async {
        final rows = await _client.from('rooms').select().eq('home_id', homeId).order('sort_order').order('name');
        return rows.map(Room.fromJson).toList();
      });

  @override
  Future<Room> createRoom(String homeId, String name, String? icon, int sortOrder) => _guard(() async {
        final row = await _client
            .from('rooms')
            .insert({'home_id': homeId, 'name': name.trim(), 'icon': icon, 'sort_order': sortOrder})
            .select()
            .single();
        return Room.fromJson(row);
      });

  @override
  Future<void> updateRoom(Room room) => _guard(() => _client
      .from('rooms')
      .update({
        'name': room.name,
        'icon': room.icon,
        'sort_order': room.sortOrder,
        'image_key': room.imageKey,
        'image_fit': room.imageFit.toJson(),
      }).eq('id', room.id));

  @override
  Future<void> deleteRoom(String roomId) => _guard(() => _client.from('rooms').delete().eq('id', roomId));

  // ---------------------------------------------------------------- Appareils
  @override
  Future<List<Device>> listDevices(String homeId) => _guard(() async {
        final rows = await _client.from('devices').select('*, device_capabilities(*)').eq('home_id', homeId).order('name');
        return rows.map((r) => Device.fromJson(r)).toList();
      });

  @override
  Future<void> updateDevice(String deviceId,
          {String? name, String? roomId, bool clearRoom = false, bool? isPinned, bool? isHidden}) =>
      _guard(() async {
        final patch = <String, dynamic>{
          if (name != null) 'name': name.trim(),
          'room_id': ?roomId,
          if (clearRoom) 'room_id': null,
          'is_pinned': ?isPinned,
          'is_hidden': ?isHidden,
        };
        if (patch.isEmpty) return;
        await _client.from('devices').update(patch).eq('id', deviceId);
      });

  @override
  Future<Map<String, List<String>>> getLayouts(String homeId) => _guard(() async {
        final uid = _client.auth.currentUser?.id;
        if (uid == null) return <String, List<String>>{};
        final rows = await _client.from('device_layouts').select('section, item_ids').eq('home_id', homeId).eq('user_id', uid);
        return {for (final r in rows) r['section'] as String: [for (final id in (r['item_ids'] as List? ?? const [])) id.toString()]};
      });

  @override
  Future<void> saveLayout(String homeId, String section, List<String> ids) => _guard(() async {
        final uid = _client.auth.currentUser?.id;
        if (uid == null) return;
        await _client.from('device_layouts').upsert({'user_id': uid, 'home_id': homeId, 'section': section, 'item_ids': ids});
      });

  @override
  Future<DeviceRemoval> removeDevice(String deviceId, {required bool unlink}) => _guard(() async {
        final r = await _client.rpc('remove_device', params: {'p_device_id': deviceId, 'p_mode': unlink ? 'unlink' : 'home'});
        return DeviceRemoval.fromJson(r is Map ? Map<String, dynamic>.from(r) : null);
      });

  @override
  Future<List<RemovedDevice>> listRemovedDevices(String homeId) => _guard(() async {
        final rows = await _client.rpc('list_removed_devices', params: {'p_home_id': homeId});
        return [for (final r in (rows as List)) RemovedDevice.fromJson(Map<String, dynamic>.from(r as Map))];
      });

  @override
  Future<void> restoreDevice(String deviceId) => _guard(() => _client.rpc('restore_device', params: {'p_device_id': deviceId}));

  @override
  Future<List<ExcludedDevice>> listExcludedDevices(String homeId) => _guard(() async {
        final rows = await _client
            .from('device_exclusions')
            .select('id, home_id, device_name, vendor, model, created_at')
            .eq('home_id', homeId)
            .order('created_at', ascending: false);
        return rows.map(ExcludedDevice.fromJson).toList();
      });

  @override
  Future<void> allowExcludedDevice(String exclusionId) =>
      _guard(() => _client.rpc('allow_excluded_device', params: {'p_exclusion_id': exclusionId}));

  @override
  Future<void> setDeviceIdentity(String deviceId, {String? serialNumber, String? qrCodeType}) => _guard(() async {
        final patch = {'serial_number': ?serialNumber, 'qr_code_type': ?qrCodeType};
        if (patch.isEmpty) return;
        await _client.from('devices').update(patch).eq('id', deviceId);
      });

  @override
  Future<String?> recordQrScan(String homeId, QrScanRecord scan) => _guard(() async {
        final row = await _client
            .from('device_qr_scans')
            .insert({
              'home_id': homeId,
              'user_id': _client.auth.currentUser?.id,
              'raw_payload': scan.rawPayload,
              'qr_code_type': scan.qrCodeType,
              'parser_type': scan.parserType,
              'manufacturer': scan.manufacturer,
              'product_id': scan.productId,
              'model': scan.model,
              'serial_number': scan.serialNumber,
              'protocol': scan.protocol,
              'recognition_status': scan.recognitionStatus,
              if (scan.reported) 'reported_at': DateTime.now().toUtc().toIso8601String(),
              'device_id': scan.deviceId,
            })
            .select('id')
            .single();
        return row['id'] as String?;
      });

  @override
  Future<void> updateQrScan(String scanId, {String? status, bool reported = false, String? deviceId}) => _guard(() async {
        final patch = <String, dynamic>{
          'recognition_status': ?status,
          if (reported) 'reported_at': DateTime.now().toUtc().toIso8601String(),
          'device_id': ?deviceId,
        };
        if (patch.isEmpty) return;
        await _client.from('device_qr_scans').update(patch).eq('id', scanId);
      });

  @override
  Future<void> setDeviceSecurity(String deviceId, bool enabled) =>
      _guard(() => _client.rpc('set_device_security', params: {'p_device_id': deviceId, 'p_enabled': enabled}));

  @override
  Future<List<AccessCode>> listAccessCodes(String deviceId) => _guard(() async {
        final rows = await _client.from('access_codes').select().eq('device_id', deviceId).order('created_at', ascending: false).limit(50);
        return rows.map(AccessCode.fromJson).toList();
      });

  @override
  Future<String> bleKey(String deviceId) =>
      _guard(() async => await _client.rpc('get_ble_key', params: {'p_device_id': deviceId}) as String);

  @override
  Future<void> logBleAction(String deviceId, {required bool unlock, required bool ok, String? error}) => _guard(() => _client.rpc(
        'log_ble_action',
        params: {'p_device_id': deviceId, 'p_action': unlock ? 'unlock' : 'lock', 'p_ok': ok, 'p_error': error},
      ));

  // ---------------------------------------------------------------- Ajout d'appareils
  // ---------------------------------------------------------------- Offre du logement
  @override
  Future<HomePlan> getHomePlan(String homeId) => _guard(() async {
        final rows = await _client.rpc('get_home_plan', params: {'p_home_id': homeId}) as List;
        return HomePlan.fromJson(Map<String, dynamic>.from(rows.first as Map));
      });

  @override
  Future<void> requestUpgrade(String homeId, {String? note}) =>
      _guard(() => _client.rpc('request_upgrade', params: {'p_home_id': homeId, 'p_note': note}));

  @override
  Future<bool> isPlatformAdmin() => _guard(() async => await _client.rpc('is_platform_admin') as bool? ?? false);

  @override
  Future<List<UpgradeRequest>> adminListUpgrades() => _guard(() async {
        final rows = await _client.rpc('admin_list_upgrades') as List;
        return rows.map((r) => UpgradeRequest.fromJson(Map<String, dynamic>.from(r as Map))).toList();
      });

  @override
  Future<void> adminDecideUpgrade(String requestId, {required bool approve, int? deviceLimit, int? months}) =>
      _guard(() => _client.rpc('admin_decide_upgrade', params: {
            'p_request_id': requestId,
            'p_approve': approve,
            'p_device_limit': deviceLimit,
            'p_months': months,
          }));

  @override
  Future<List<PlatformDevice>> adminListPlatformDevices() => _guard(() async {
        final rows = await _client.rpc('admin_list_platform_devices') as List;
        return rows.map((r) => PlatformDevice.fromJson(Map<String, dynamic>.from(r as Map))).toList();
      });

  @override
  Future<List<HomeSummary>> adminSearchHomes(String query) => _guard(() async {
        final rows = await _client.rpc('admin_search_homes', params: {'p_query': query}) as List;
        return rows.map((r) => HomeSummary.fromJson(Map<String, dynamic>.from(r as Map))).toList();
      });

  @override
  Future<void> adminAssignDevice(String externalId, String? homeId) =>
      _guard(() => _client.rpc('admin_assign_device', params: {'p_external_id': externalId, 'p_home_id': homeId}));

  @override
  Future<String> requestPairing(String homeId, {required String kind, String? name, String? roomId, String? lockData}) =>
      _guard(() async => await _client.rpc('request_pairing', params: {
            'p_home_id': homeId,
            'p_kind': kind,
            'p_name': name,
            'p_room_id': roomId,
            'p_lock_data': lockData,
          }) as String);

  @override
  Future<PairingRequest?> getPairing(String requestId) => _guard(() async {
        final row = await _client.from('pairing_requests').select('id, kind, status, error, device_id').eq('id', requestId).maybeSingle();
        return row == null ? null : PairingRequest.fromJson(row);
      });

  // ---------------------------------------------------------------- Commandes
  @override
  Future<DeviceCommand> sendCommand({
    required String homeId,
    required String deviceId,
    required String capabilityKey,
    required dynamic value,
    required String idempotencyKey,
  }) =>
      _guard(() async {
        final row = await _client
            .from('device_commands')
            .insert({
              'home_id': homeId,
              'device_id': deviceId,
              'capability_key': capabilityKey,
              'value': value,
              'idempotency_key': idempotencyKey,
            })
            .select()
            .single();
        return DeviceCommand.fromJson(row);
      });

  @override
  Future<DeviceCommand?> getCommand(String commandId) => _guard(() async {
        final row = await _client.from('device_commands').select().eq('id', commandId).maybeSingle();
        return row == null ? null : DeviceCommand.fromJson(row);
      });

  // ---------------------------------------------------------------- Scènes
  @override
  Future<List<Scene>> listScenes(String homeId) => _guard(() async {
        final rows = await _client.from('scenes').select('*, scene_actions(*)').eq('home_id', homeId).order('name');
        return rows.map(Scene.fromJson).toList();
      });

  @override
  Future<Scene> saveScene(Scene scene, {bool isNew = false}) => _guard(() async {
        final data = {
          'id': scene.id,
          'home_id': scene.homeId,
          'name': scene.name.trim(),
          'icon': scene.icon,
          'enabled': scene.enabled,
          'failure_policy': scene.failurePolicy == FailurePolicy.stop ? 'stop' : 'continue',
          if (isNew) 'created_by': _uid,
        };
        if (isNew) {
          await _client.from('scenes').insert(data);
        } else {
          await _client.from('scenes').update(data).eq('id', scene.id);
          await _client.from('scene_actions').delete().eq('scene_id', scene.id);
        }
        if (scene.actions.isNotEmpty) {
          await _client.from('scene_actions').insert([
            for (var i = 0; i < scene.actions.length; i++) scene.actions[i].toJson(scene.id, i),
          ]);
        }
        final row = await _client.from('scenes').select('*, scene_actions(*)').eq('id', scene.id).single();
        return Scene.fromJson(row);
      });

  @override
  Future<void> deleteScene(String sceneId) => _guard(() => _client.from('scenes').delete().eq('id', sceneId));

  @override
  Future<String> executeScene(String sceneId) =>
      _guard(() async => await _client.rpc('execute_scene', params: {'p_scene_id': sceneId}) as String);

  @override
  Future<List<SceneRun>> listSceneRuns(String homeId, {int limit = 30}) => _guard(() async {
        final rows = await _client
            .from('scene_runs')
            .select()
            .eq('home_id', homeId)
            .order('started_at', ascending: false)
            .limit(limit);
        return rows.map(SceneRun.fromJson).toList();
      });

  // ---------------------------------------------------------------- Automatisations
  @override
  Future<List<Automation>> listAutomations(String homeId) => _guard(() async {
        final rows = await _client.from('automations').select().eq('home_id', homeId).order('name');
        return rows.map(Automation.fromJson).toList();
      });

  @override
  Future<Automation> saveAutomation(Automation a, {bool isNew = false}) => _guard(() async {
        Future<Map<String, dynamic>> write(Map<String, dynamic> data) => isNew
            ? _client.from('automations').insert({...data, 'id': a.id, 'created_by': _uid}).select().single()
            : _client.from('automations').update(data).eq('id', a.id).select().single();
        Map<String, dynamic> row;
        try {
          row = await write(a.toJson(includeAdvanced: true));
        } on PostgrestException catch (e) {
          // Base pas encore à jour (colonnes SAUF SI / PUIS absentes) : automatisation simple.
          if (e.code != 'PGRST204' && e.code != '42703') rethrow;
          row = await write(a.toJson());
        }
        return Automation.fromJson(row);
      });

  @override
  Future<ClimateData> getClimate(String homeId) => _guard(() async {
        final settings = await _client.from('climate_settings').select().eq('home_id', homeId).maybeSingle();
        final zones = await _client.from('climate_zones').select().eq('home_id', homeId);
        return ClimateData(
          settings == null ? ClimateSettings.initial : ClimateSettings.fromJson(settings),
          [for (final z in zones) ClimateZone.fromJson(z)],
        );
      });

  @override
  Future<void> saveClimateSettings(String homeId, ClimateSettings settings) =>
      _guard(() => _client.from('climate_settings').upsert({'home_id': homeId, ...settings.toJson()}));

  @override
  Future<void> saveClimateZone(String homeId, ClimateZone zone) =>
      _guard(() => _client.from('climate_zones').upsert({'home_id': homeId, ...zone.toJson()}, onConflict: 'room_id'));

  @override
  Future<void> deleteClimateZone(String zoneId) => _guard(() => _client.from('climate_zones').delete().eq('id', zoneId));

  @override
  Future<bool> reportPresence(String homeId, double latitude, double longitude) => _guard(() async =>
      await _client.rpc('report_presence', params: {'p_home_id': homeId, 'p_lat': latitude, 'p_lon': longitude}) == true);

  @override
  Future<void> clearPresence(String homeId) =>
      _guard(() => _client.from('member_presence').delete().eq('home_id', homeId).eq('user_id', _client.auth.currentUser!.id));

  @override
  Future<void> setClimatePreset(String homeId, String? roomId, String? preset, DateTime? until) => _guard(() => _client.rpc('set_climate_preset', params: {
        'p_home_id': homeId,
        'p_room_id': roomId,
        'p_preset': preset,
        'p_until': until?.toUtc().toIso8601String(),
      }));

  @override
  Future<HomeModes?> getHomeModes(String homeId) => _guard(() async {
        final row = await _client.from('home_modes').select().eq('home_id', homeId).maybeSingle();
        return row == null ? null : HomeModes.fromJson(row);
      });

  @override
  Future<void> saveHomeModes(String homeId, HomeModes modes) =>
      _guard(() => _client.from('home_modes').upsert({'home_id': homeId, ...modes.toJson()}));

  @override
  Future<List<AutomationRun>> listAutomationRuns(String homeId, {String? automationId, int limit = 50}) => _guard(() async {
        var q = _client.from('automation_runs').select().eq('home_id', homeId);
        if (automationId != null) q = q.eq('automation_id', automationId);
        final rows = await q.order('created_at', ascending: false).limit(limit);
        return rows.map(AutomationRun.fromJson).toList();
      });

  @override
  Future<void> deleteAutomation(String automationId) =>
      _guard(() => _client.from('automations').delete().eq('id', automationId));

  // ---------------------------------------------------------------- Intégrations
  @override
  Future<List<Integration>> listIntegrations(String homeId) => _guard(() async {
        final rows = await _client.from('integrations').select().eq('home_id', homeId).order('created_at');
        return rows.map(Integration.fromJson).toList();
      });

  @override
  Future<String> createIntegration(String homeId, String provider, String? label) => _guard(() async =>
      await _client.rpc('create_integration', params: {'p_home_id': homeId, 'p_provider': provider, 'p_label': label})
          as String);

  @override
  Future<void> setIntegrationEnabled(String integrationId, bool enabled) => _guard(() =>
      _client.rpc('set_integration_enabled', params: {'p_integration_id': integrationId, 'p_enabled': enabled}));

  // ---------------------------------------------------------------- Journal
  @override
  Future<List<EventLog>> listEvents(String homeId, {int limit = 100}) => _guard(() async {
        final rows = await _client
            .from('event_logs')
            .select()
            .eq('home_id', homeId)
            // Historique des détecteurs et diagnostics : affichés ailleurs, pas dans le journal.
            .not('event_type', 'in', '(presence,device_diagnostic)')
            .order('created_at', ascending: false)
            .limit(limit);
        return rows.map(EventLog.fromJson).toList();
      });

  @override
  Future<List<EventLog>> listPresence(String deviceId, DateTime since) => _guard(() async {
        final rows = await _client
            .from('event_logs')
            .select()
            .eq('device_id', deviceId)
            .eq('event_type', 'presence')
            .gte('created_at', since.toUtc().toIso8601String())
            .order('created_at', ascending: true)
            .limit(1000);
        return rows.map(EventLog.fromJson).toList();
      });

  // ---------------------------------------------------------------- Notifications
  @override
  Future<List<AppNotification>> listNotifications(String homeId, {int limit = 200}) => _guard(() async {
        final rows = await _client
            .from('notifications')
            .select()
            .eq('home_id', homeId)
            .order('created_at', ascending: false)
            .limit(limit);
        return rows.map(AppNotification.fromJson).toList();
      });

  @override
  Future<void> markNotificationRead(int id) => _guard(() =>
      _client.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id).isFilter('read_at', null));

  @override
  Future<void> markAllNotificationsRead(String homeId) =>
      _guard(() => _client.rpc('mark_notifications_read', params: {'p_home_id': homeId}));

  @override
  Future<void> deleteNotification(int id) => _guard(() => _client.from('notifications').delete().eq('id', id));

  @override
  Future<void> savePushToken(String token, String platform, String locale) => _guard(() => _client.from('push_tokens').upsert({
        'token': token,
        'user_id': currentUserId,
        'platform': platform,
        'locale': locale,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }));

  @override
  Future<void> deletePushToken(String token) => _guard(() => _client.from('push_tokens').delete().eq('token', token));

  // ---------------------------------------------------------------- Caméras et photos
  /// Un seul canal temps réel « `camera:<maison>` » partagé par toutes les vues ouvertes
  /// (deux abonnements au même canal sur une connexion se couperaient l'un l'autre).
  final _cameraHubs = <String, _CameraHub>{};

  // ------------------------------------------------------------------ Sécurité et vidéo
  @override
  Future<List<VideoSource>> listVideoSources(String homeId) => _guard(() async {
        final rows = await _client.from('video_sources').select().eq('home_id', homeId).order('name');
        return rows.map((r) => VideoSource.fromJson(r)).toList();
      });

  @override
  Future<String> addVideoSource(String homeId, VideoSourceDraft d) => _guard(() async {
        String? opt(String v) => v.trim().isEmpty ? null : v.trim();
        final onvif = d.driver == 'onvif';
        final dahua = d.driver == 'dahua';
        return await _client.rpc('add_video_source', params: {
          'p_home_id': homeId,
          'p_name': d.name.trim(),
          'p_driver': d.driver,
          'p_category': d.category,
          'p_host': onvif || dahua ? opt(d.host) : null,
          'p_port': onvif ? d.port : null,
          'p_rtsp_url': d.driver == 'rtsp' ? opt(d.rtspUrl) : null,
          'p_snapshot_url': d.driver == 'rtsp' ? opt(d.snapshotUrl) : null,
          // QR code seulement : numéro de série, modèle et marque lus sur l'étiquette.
          if (dahua) 'p_serial': opt(d.serial),
          if (dahua) 'p_model': opt(d.model),
          if (dahua) 'p_manufacturer': opt(d.manufacturer),
          'p_username': opt(d.username),
          'p_password': d.password.isEmpty ? null : d.password,
          'p_location': opt(d.location),
        }) as String;
      });

  @override
  Future<void> setVideoSourceCredentials(String sourceId, String username, String password) => _guard(() async {
        await _client.rpc('set_video_source_credentials', params: {'p_source_id': sourceId, 'p_username': username.trim(), 'p_password': password});
      });

  @override
  Future<void> requestVideoSourceTest(String sourceId) => _guard(() async {
        await _client.rpc('request_video_source_test', params: {'p_source_id': sourceId});
      });

  @override
  Future<void> deleteVideoSource(String sourceId) => _guard(() async {
        await _client.rpc('delete_video_source', params: {'p_source_id': sourceId});
      });

  @override
  Future<String> requestVideoScan(String homeId) =>
      _guard(() async => await _client.rpc('request_video_scan', params: {'p_home_id': homeId}) as String);

  @override
  Future<VideoScan?> getVideoScan(String scanId) => _guard(() async {
        final row = await _client.from('video_scans').select('id, status, results, error').eq('id', scanId).maybeSingle();
        return row == null ? null : VideoScan.fromJson(row);
      });

  @override
  Future<MediaGateway?> getMediaGateway(String homeId) => _guard(() async {
        final row = await _client.from('media_gateways').select().eq('home_id', homeId).maybeSingle();
        return row == null ? null : MediaGateway.fromJson(row);
      });

  @override
  Future<String> openVideoSession(String homeId, String deviceId, String offerSdp, {String quality = 'main', DateTime? playbackStart}) => _guard(() async {
        final row = await _client
            .from('video_sessions')
            .insert({
              'home_id': homeId,
              'device_id': deviceId,
              'offer': offerSdp,
              'quality': playbackStart != null ? 'playback' : quality,
              if (playbackStart != null) 'playback_start': playbackStart.toUtc().toIso8601String(),
              if (playbackStart != null) 'playback_end': playbackStart.add(const Duration(hours: 1)).toUtc().toIso8601String(),
              'user_id': _uid,
            })
            .select('id')
            .single();
        return row['id'] as String;
      });

  @override
  Future<VideoSessionInfo?> getVideoSession(String sessionId) => _guard(() async {
        final row = await _client.from('video_sessions').select('id, status, answer, error').eq('id', sessionId).maybeSingle();
        return row == null ? null : VideoSessionInfo.fromJson(row);
      });

  @override
  Future<void> closeVideoSession(String sessionId) => _guard(() async {
        await _client.from('video_sessions').update({'status': 'closed'}).eq('id', sessionId);
      });

  @override
  Future<String> requestVideoRecordings(String deviceId, DateTime day) => _guard(() async {
        final d = '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
        return await _client.rpc('request_video_recordings', params: {'p_device_id': deviceId, 'p_day': d}) as String;
      });

  @override
  Future<RecordingQuery?> getVideoRecordings(String queryId) => _guard(() async {
        final row = await _client.from('video_recording_queries').select('id, status, slots, error').eq('id', queryId).maybeSingle();
        return row == null ? null : RecordingQuery.fromJson(row);
      });

  @override
  Stream<CameraFrame> watchCamera(String homeId, String deviceId) {
    final path = '$homeId/$deviceId.jpg';
    late final StreamController<CameraFrame> controller;
    late final _CameraWatcher watcher;
    Timer? ping;
    Timer? poll;
    DateTime? lastNotice;
    var busy = false;

    Future<void> fetch({String? at}) async {
      if (busy || controller.isClosed) return;
      busy = true;
      try {
        final bytes = await _client.storage.from('camera-frames').download(path, cacheNonce: at ?? '${DateTime.now().millisecondsSinceEpoch}');
        final live = lastNotice != null && DateTime.now().difference(lastNotice!) < const Duration(seconds: 6);
        if (!controller.isClosed) {
          controller.add(CameraFrame(bytes, at == null ? DateTime.now() : (DateTime.tryParse(at)?.toLocal() ?? DateTime.now()), live: live));
        }
      } catch (_) {
        // Pas encore d'image (passerelle arrêtée ou caméra injoignable) : l'écran l'indique.
      } finally {
        busy = false;
      }
    }

    controller = StreamController<CameraFrame>(
      onListen: () {
        watcher = _CameraWatcher(deviceId, (at) {
          lastNotice = DateTime.now();
          fetch(at: at);
        });
        final hub = _cameraHubs.putIfAbsent(homeId, () => _CameraHub(_client, homeId));
        hub.add(watcher);
        // La passerelle arrête d'envoyer 15 s après le dernier signal : on le renouvelle.
        ping = Timer.periodic(const Duration(seconds: 5), (_) => hub.watch(deviceId));
        // Filet de sécurité si un message temps réel se perd.
        poll = Timer.periodic(const Duration(seconds: 4), (_) => fetch());
        fetch();
      },
      onCancel: () async {
        ping?.cancel();
        poll?.cancel();
        final hub = _cameraHubs[homeId];
        if (hub != null && hub.remove(watcher)) {
          _cameraHubs.remove(homeId); // retiré avant la fermeture : une nouvelle vue repart d'un canal neuf
          await hub.close();
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<Uint8List> downloadDevicePhoto(String path) => _guard(() => _client.storage.from('device-photos').download(path));

  @override
  Future<String> setDevicePhoto(Device device, Uint8List bytes, String contentType) => _guard(() async {
        final ext = imageExtension(contentType);
        if (ext == null) throw const BackendException('invalid', 'Format d\'image non pris en charge (JPEG, PNG ou WebP).');
        final path = '${device.homeId}/${device.id}-${DateTime.now().millisecondsSinceEpoch}.$ext';
        await _client.storage.from('device-photos').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: contentType, cacheControl: '31536000'),
            );
        await _client.from('devices').update({'photo_path': path}).eq('id', device.id);
        await _removePhoto(device.photoPath);
        return path;
      });

  @override
  Future<void> clearDevicePhoto(Device device) => _guard(() async {
        await _client.from('devices').update({'photo_path': null}).eq('id', device.id);
        await _removePhoto(device.photoPath);
      });

  @override
  Future<Uint8List> downloadRoomPhoto(String path) => _guard(() => _client.storage.from('room-photos').download(path));

  @override
  Future<String> setRoomPhoto(Room room, Uint8List bytes, String contentType) => _guard(() async {
        final ext = imageExtension(contentType);
        if (ext == null) throw const BackendException('invalid', 'Format d\'image non pris en charge (JPEG, PNG ou WebP).');
        final path = '${room.homeId}/${room.id}-${DateTime.now().millisecondsSinceEpoch}.$ext';
        await _client.storage.from('room-photos').uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(contentType: contentType, cacheControl: '31536000'),
            );
        await _client.from('rooms').update({'photo_path': path}).eq('id', room.id);
        await _removePhoto(room.photoPath, bucket: 'room-photos');
        return path;
      });

  @override
  Future<void> clearRoomPhoto(Room room) => _guard(() async {
        await _client.from('rooms').update({'photo_path': null}).eq('id', room.id);
        await _removePhoto(room.photoPath, bucket: 'room-photos');
      });

  Future<void> _removePhoto(String? path, {String bucket = 'device-photos'}) async {
    if (path == null) return;
    try {
      await _client.storage.from(bucket).remove([path]);
    } catch (_) {
      // Ancienne photo orpheline : sans conséquence pour l'affichage.
    }
  }

  // ---------------------------------------------------------------- Temps réel
  @override
  Stream<RealtimeEvent> watchHome(String homeId, {void Function(bool connected)? onStatus}) {
    late final RealtimeChannel channel;
    final controller = StreamController<RealtimeEvent>(onCancel: () => _client.removeChannel(channel));

    void forward(String table, PostgresChangePayload p) {
      final record = p.eventType == PostgresChangeEvent.delete ? p.oldRecord : p.newRecord;
      controller.add(RealtimeEvent(table, p.eventType.name.toUpperCase(), Map<String, dynamic>.from(record)));
    }

    final byHome = PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'home_id', value: homeId);
    channel = _client.channel('home:$homeId');
    // notifications : la RLS ne transmet que celles de l'utilisateur connecté.
    for (final table in ['devices', 'device_commands', 'scene_runs', 'notifications', 'home_modes', 'climate_settings', 'climate_zones']) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: byHome,
        callback: (p) => forward(table, p),
      );
    }
    // Pas de colonne home_id : la RLS limite déjà aux appareils autorisés.
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'device_capabilities',
      callback: (p) => forward('device_capabilities', p),
    );
    channel.subscribe((status, error) {
      onStatus?.call(status == RealtimeSubscribeStatus.subscribed);
    });
    return controller.stream;
  }
}

class _CameraWatcher {
  _CameraWatcher(this.deviceId, this.onFrame);

  final String deviceId;
  final void Function(String? at) onFrame;
}

/// Canal « `camera:<maison>` » : envoie les signaux « watch », reçoit les avis « frame ».
class _CameraHub {
  _CameraHub(this._client, String homeId) {
    _channel = _client.channel('camera:$homeId')
      ..onBroadcast(
        event: 'frame',
        callback: (payload) {
          // La passerelle (supabase-js) range ses champs sous « payload ».
          final inner = payload['payload'];
          final data = inner is Map ? inner : payload;
          for (final w in List.of(_watchers)) {
            if (w.deviceId == data['device_id']) w.onFrame(data['at']?.toString());
          }
        },
      )
      ..subscribe((status, _) {
        _subscribed = status == RealtimeSubscribeStatus.subscribed;
        if (_subscribed) {
          for (final id in _watchers.map((w) => w.deviceId).toSet()) {
            watch(id);
          }
        }
      });
  }

  final SupabaseClient _client;
  late final RealtimeChannel _channel;
  final _watchers = <_CameraWatcher>[];
  var _subscribed = false;

  void add(_CameraWatcher w) {
    _watchers.add(w);
    if (_subscribed) watch(w.deviceId);
  }

  /// Retire une vue ; true quand plus aucune vue n'utilise le canal.
  bool remove(_CameraWatcher w) {
    _watchers.remove(w);
    return _watchers.isEmpty;
  }

  Future<void> close() => _client.removeChannel(_channel);

  void watch(String deviceId) {
    // Champs sous « payload » et à plat : lus par toutes les versions de la passerelle.
    if (_subscribed) {
      _channel.sendBroadcastMessage(event: 'watch', payload: {
        'device_id': deviceId,
        'payload': {'device_id': deviceId},
      });
    }
  }
}
