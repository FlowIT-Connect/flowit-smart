import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

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

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on AuthException catch (e) {
      // Messages non révélateurs (§5.1)
      final msg = e.message.toLowerCase();
      if (msg.contains('rate') || e.statusCode == '429') {
        throw const BackendException('rate', 'Trop de tentatives. Réessayez plus tard.');
      }
      if (msg.contains('password') && msg.contains('characters')) {
        throw BackendException('invalid', e.message);
      }
      throw const BackendException('auth', 'Identifiants invalides ou compte non vérifié.');
    } on PostgrestException catch (e) {
      if (e.code == '42501' || e.code == 'PGRST301') {
        throw const BackendException('denied', 'Accès refusé.');
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
        await _auth.signUp(email: email.trim(), password: password, data: {'display_name': displayName.trim()});
      });

  @override
  Future<void> resetPassword(String email) => _guard(() => _auth.resetPasswordForEmail(email.trim()));

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
      .update({'name': room.name, 'icon': room.icon, 'sort_order': room.sortOrder}).eq('id', room.id));

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
  Future<void> setDeviceSecurity(String deviceId, bool enabled) =>
      _guard(() => _client.rpc('set_device_security', params: {'p_device_id': deviceId, 'p_enabled': enabled}));

  @override
  Future<List<AccessCode>> listAccessCodes(String deviceId) => _guard(() async {
        final rows = await _client.from('access_codes').select().eq('device_id', deviceId).order('created_at', ascending: false).limit(50);
        return rows.map(AccessCode.fromJson).toList();
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
        final data = a.toJson();
        final Map<String, dynamic> row;
        if (isNew) {
          row = await _client.from('automations').insert({...data, 'id': a.id, 'created_by': _uid}).select().single();
        } else {
          row = await _client.from('automations').update(data).eq('id', a.id).select().single();
        }
        return Automation.fromJson(row);
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
            .order('created_at', ascending: false)
            .limit(limit);
        return rows.map(EventLog.fromJson).toList();
      });

  // ---------------------------------------------------------------- Caméras et photos
  /// Un seul canal temps réel « `camera:<maison>` » partagé par toutes les vues ouvertes
  /// (deux abonnements au même canal sur une connexion se couperaient l'un l'autre).
  final _cameraHubs = <String, _CameraHub>{};

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

  Future<void> _removePhoto(String? path) async {
    if (path == null) return;
    try {
      await _client.storage.from('device-photos').remove([path]);
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
    for (final table in ['devices', 'device_commands', 'scene_runs']) {
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
          for (final w in List.of(_watchers)) {
            if (w.deviceId == payload['device_id']) w.onFrame(payload['at']?.toString());
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
    if (_subscribed) _channel.sendBroadcastMessage(event: 'watch', payload: {'device_id': deviceId});
  }
}
