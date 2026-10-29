import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../models/models.dart';
import 'backend.dart';
import 'demo_camera.dart';

/// Backend de démonstration en mémoire.
///
/// Reproduit le contrat du serveur (commande "pending" puis confirmation ou
/// échec, appareils hors ligne, scènes avec délais et politique d'échec,
/// journal) pour présenter l'application sans Supabase ni matériel.
class DemoBackend implements Backend {
  DemoBackend({
    this.latency = const Duration(milliseconds: 250),
    this.confirmDelay = const Duration(milliseconds: 1100),
    this.liveSensors = true,
  }) {
    _seed();
  }

  final Duration latency;
  final Duration confirmDelay;

  /// Fait varier les capteurs toutes les 8 s (désactivé dans les tests).
  final bool liveSensors;

  static const _me = '00000000-0000-4000-8000-000000000001';
  static const _amina = '00000000-0000-4000-8000-000000000002';

  final _auth = StreamController<bool>.broadcast();
  final _events = StreamController<RealtimeEvent>.broadcast();
  final _rand = Random();
  Timer? _sensorTimer;
  bool _signedIn = false;
  String? _email;
  int _eventSeq = 0;

  final _homes = <String, Map<String, dynamic>>{};
  final _members = <Map<String, dynamic>>[];
  final _invitations = <Map<String, dynamic>>[];
  final _rooms = <String, Map<String, dynamic>>{};
  final _devices = <String, Map<String, dynamic>>{};
  final _caps = <Map<String, dynamic>>[];
  final _commands = <String, Map<String, dynamic>>{};
  final _scenes = <String, Map<String, dynamic>>{};
  final _runs = <Map<String, dynamic>>[];
  final _automations = <String, Map<String, dynamic>>{};
  final _integrations = <Map<String, dynamic>>[];
  final _logs = <Map<String, dynamic>>[];
  final _photos = <String, Uint8List>{};

  @override
  bool get isDemo => true;

  Future<void> _wait() => Future.delayed(latency);
  String _now() => DateTime.now().toUtc().toIso8601String();

  // ------------------------------------------------------------------ Données
  void _seed() {
    const homeId = '10000000-0000-4000-8000-000000000001';
    _homes[homeId] = {'id': homeId, 'owner_id': _me, 'name': 'Maison démo', 'timezone': 'Africa/Algiers'};
    _members.addAll([
      {'home_id': homeId, 'user_id': _me, 'role': 'owner', 'permissions': {}, 'profiles': {'display_name': 'Vous'}},
      {
        'home_id': homeId,
        'user_id': _amina,
        'role': 'member',
        'permissions': {'devices': <String>[]},
        'profiles': {'display_name': 'Amina'},
      },
    ]);

    String room(String name, String icon, int order) {
      final id = newUuid();
      _rooms[id] = {'id': id, 'home_id': homeId, 'name': name, 'icon': icon, 'sort_order': order};
      return id;
    }

    final salon = room('Salon', 'sofa', 0);
    final chambre = room('Chambre', 'bed', 1);
    final cuisine = room('Cuisine', 'kitchen', 2);
    final entree = room('Entrée', 'door', 3);

    String device(String name, String? roomId, String protocol, String source,
        {String vendor = '', String model = '', String availability = 'available', Map<String, dynamic>? state, bool pinned = false, bool sensitive = false, List<List<dynamic>> caps = const []}) {
      final id = newUuid();
      _devices[id] = {
        'id': id,
        'home_id': homeId,
        'room_id': roomId,
        'name': name,
        'vendor': vendor,
        'model': model,
        'protocol': protocol,
        'connection_source': source,
        'availability': availability,
        'state': state ?? {},
        'last_seen_at': availability == 'unknown' ? null : DateTime.now().toUtc().subtract(Duration(minutes: _rand.nextInt(50))).toIso8601String(),
        'updated_at': _now(),
        'is_pinned': pinned,
        'is_hidden': false,
        'is_sensitive': sensitive,
      };
      for (final c in caps) {
        _caps.add({'device_id': id, 'capability_key': c[0], 'type': c[1], 'writable': c[2], 'metadata': c.length > 3 ? c[3] : {}});
      }
      return id;
    }

    final plafonnier = device('Plafonnier', salon, 'zigbee', 'gateway',
        vendor: 'IKEA', model: 'LED1836G9', pinned: true,
        state: {'switch': true, 'brightness': 70, 'color_temp': 3000},
        caps: [
          ['switch', 'boolean', true],
          ['brightness', 'number', true, {'min': 1, 'max': 100, 'step': 1, 'unit': '%'}],
          ['color_temp', 'number', true, {'min': 2200, 'max': 4000, 'step': 100, 'unit': 'K'}],
        ]);
    final ruban = device('Ruban LED TV', salon, 'tuya', 'cloud',
        vendor: 'Tuya', model: 'LED strip RGB', state: {'switch': false, 'brightness': 50, 'color': '#3F51B5'},
        caps: [
          ['switch', 'boolean', true],
          ['brightness', 'number', true, {'min': 1, 'max': 100, 'step': 1, 'unit': '%'}],
          ['color', 'color', true],
        ]);
    final volet = device('Volet salon', salon, 'zigbee', 'gateway',
        vendor: 'Moes', model: 'ZigBee curtain switch', pinned: true, state: {'cover_position': 100},
        caps: [
          ['cover_position', 'number', true, {'min': 0, 'max': 100, 'step': 5, 'unit': '%'}],
        ]);
    final cafe = device('Prise café', cuisine, 'wifi', 'local',
        vendor: 'Shelly', model: 'Plug S', pinned: true, state: {'switch': false, 'power': 0.0},
        caps: [
          ['switch', 'boolean', true],
          ['power', 'sensor', false, {'unit': 'W'}],
        ]);
    device('Thermostat', salon, 'wifi', 'cloud',
        vendor: 'Netatmo', model: 'Smart Thermostat', state: {'target_temperature': 21.0, 'hvac_mode': 'heat', 'current_temperature': 20.4},
        caps: [
          ['target_temperature', 'number', true, {'min': 7, 'max': 30, 'step': 0.5, 'unit': '°C'}],
          ['hvac_mode', 'enum', true, {'options': ['off', 'heat', 'auto']}],
          ['current_temperature', 'sensor', false, {'unit': '°C'}],
        ]);
    device('Capteur chambre', chambre, 'zigbee', 'gateway',
        vendor: 'Aqara', model: 'WSDCGQ11LM', state: {'temperature': 19.8, 'humidity': 48, 'battery': 87},
        caps: [
          ['temperature', 'sensor', false, {'unit': '°C'}],
          ['humidity', 'sensor', false, {'unit': '%'}],
          ['battery', 'sensor', false, {'unit': '%'}],
        ]);
    final ampoule = device('Ampoule chevet', chambre, 'tuya', 'cloud',
        vendor: 'Tuya', model: 'Smart bulb E27', availability: 'unavailable', state: {'switch': false, 'brightness': 40},
        caps: [
          ['switch', 'boolean', true],
          ['brightness', 'number', true, {'min': 1, 'max': 100, 'step': 1, 'unit': '%'}],
        ]);
    device('Porte d\'entrée', entree, 'zigbee', 'gateway',
        vendor: 'Aqara', model: 'MCCGQ11LM', state: {'contact': true, 'battery': 92},
        caps: [
          ['contact', 'sensor', false, {'kind': 'binary'}],
          ['battery', 'sensor', false, {'unit': '%'}],
        ]);
    device('Serrure', entree, 'ble', 'ble_direct',
        vendor: '—', model: 'Serrure BLE', sensitive: true, state: {'lock': true},
        caps: [
          ['lock', 'boolean', true],
        ]);
    device('Détecteur couloir', entree, 'zigbee', 'gateway',
        vendor: 'Sonoff', model: 'SNZB-03', availability: 'unknown', state: {},
        caps: [
          ['motion', 'sensor', false, {'kind': 'binary'}],
          ['battery', 'sensor', false, {'unit': '%'}],
        ]);
    device('Télécommande IR', salon, 'other', 'cloud', vendor: 'Générique', model: 'IR blaster');
    device('Climatiseur salon', salon, 'tuya', 'cloud',
        vendor: 'Tuya', model: 'Split 12000 BTU', state: {'target_temperature': 24.0, 'hvac_mode': 'cool', 'current_temperature': 27.5},
        caps: [
          ['target_temperature', 'number', true, {'min': 16, 'max': 30, 'step': 1, 'unit': '°C'}],
          ['hvac_mode', 'enum', true, {'options': ['off', 'cool', 'heat', 'dry', 'fan_only']}],
          ['current_temperature', 'sensor', false, {'unit': '°C'}],
        ]);
    device('Caméra entrée', entree, 'wifi', 'local',
        vendor: 'TP-Link', model: 'Tapo C200', state: {'camera': 'idle', 'motion': false},
        caps: [
          ['camera', 'string', false, {'kind': 'camera'}],
          ['motion', 'sensor', false, {'kind': 'binary'}],
        ]);

    // Amina ne voit que le salon (exemple de droits limités)
    _members[1]['permissions'] = {'devices': [plafonnier, ruban, volet]};

    final soiree = newUuid();
    _scenes[soiree] = {
      'id': soiree,
      'home_id': homeId,
      'name': 'Soirée film',
      'icon': 'movie',
      'enabled': true,
      'failure_policy': 'continue',
      'scene_actions': [
        {'id': newUuid(), 'device_id': plafonnier, 'capability_key': 'brightness', 'value': 20, 'position': 0, 'delay_ms': 0},
        {'id': newUuid(), 'device_id': ruban, 'capability_key': 'switch', 'value': true, 'position': 1, 'delay_ms': 0},
        {'id': newUuid(), 'device_id': volet, 'capability_key': 'cover_position', 'value': 0, 'position': 2, 'delay_ms': 1000},
      ],
    };
    final depart = newUuid();
    _scenes[depart] = {
      'id': depart,
      'home_id': homeId,
      'name': 'Je pars',
      'icon': 'logout',
      'enabled': true,
      'failure_policy': 'continue',
      'scene_actions': [
        {'id': newUuid(), 'device_id': plafonnier, 'capability_key': 'switch', 'value': false, 'position': 0, 'delay_ms': 0},
        {'id': newUuid(), 'device_id': ruban, 'capability_key': 'switch', 'value': false, 'position': 1, 'delay_ms': 0},
        {'id': newUuid(), 'device_id': cafe, 'capability_key': 'switch', 'value': false, 'position': 2, 'delay_ms': 0},
        {'id': newUuid(), 'device_id': ampoule, 'capability_key': 'switch', 'value': false, 'position': 3, 'delay_ms': 0},
      ],
    };

    final auto1 = newUuid();
    _automations[auto1] = {
      'id': auto1,
      'home_id': homeId,
      'name': 'Café du matin',
      'enabled': true,
      'trigger': {'type': 'time', 'at': '06:45', 'days': [1, 2, 3, 4, 5]},
      'conditions': [],
      'actions': [
        {'device_id': cafe, 'capability_key': 'switch', 'value': true},
      ],
      'run_locally': true,
    };
    final auto2 = newUuid();
    _automations[auto2] = {
      'id': auto2,
      'home_id': homeId,
      'name': 'Porte ouverte la nuit',
      'enabled': false,
      'trigger': {'type': 'device_state', 'device_id': _devices.keys.elementAt(7), 'capability_key': 'contact', 'op': 'eq', 'value': false},
      'conditions': [
        {'type': 'time_range', 'from': '22:00', 'to': '06:00'},
      ],
      'actions': [
        {'device_id': plafonnier, 'capability_key': 'switch', 'value': true},
      ],
      'run_locally': true,
    };

    _integrations.addAll([
      {'id': newUuid(), 'home_id': homeId, 'provider': 'home_assistant', 'status': 'connected', 'label': 'Home Assistant (démo)', 'last_sync_at': _now()},
      {'id': newUuid(), 'home_id': homeId, 'provider': 'zigbee2mqtt', 'status': 'connected', 'label': 'Zigbee2MQTT', 'last_sync_at': _now()},
      {'id': newUuid(), 'home_id': homeId, 'provider': 'tuya', 'status': 'error', 'label': 'Tuya (via Home Assistant)', 'last_error': 'Quota cloud atteint'},
    ]);

    _log(homeId, 'device_unavailable', deviceId: ampoule, result: 'unavailable');
    _log(homeId, 'member_changed', result: 'insert', details: {'user_id': _amina, 'role': 'member'});
  }

  void _log(String homeId, String type, {String? deviceId, String? requestId, String? result, Map<String, dynamic>? details}) {
    _logs.insert(0, {
      'id': ++_eventSeq,
      'home_id': homeId,
      'actor_id': _me,
      'event_type': type,
      'device_id': deviceId,
      'request_id': requestId,
      'result': result,
      'details': details ?? {},
      'created_at': _now(),
    });
  }

  Map<String, dynamic> _deviceRow(String id) => {
        ..._devices[id]!,
        'device_capabilities': _caps.where((c) => c['device_id'] == id).toList(),
      };

  Map<String, dynamic>? _member(String homeId) {
    for (final m in _members) {
      if (m['home_id'] == homeId && m['user_id'] == _me) return m;
    }
    return null;
  }

  void _requireManager(String homeId) {
    final role = _member(homeId)?['role'];
    if (role != 'owner' && role != 'admin') throw const BackendException('denied', 'Accès refusé.');
  }

  // ------------------------------------------------------------------ Comptes
  @override
  String? get currentUserId => _signedIn ? _me : null;

  @override
  String? get currentEmail => _signedIn ? _email : null;

  @override
  Stream<bool> get authChanges => _auth.stream;

  @override
  Stream<void> get passwordRecovery => const Stream.empty();

  @override
  Future<void> signIn(String email, String password) async {
    await _wait();
    if (!email.contains('@') || password.isEmpty) {
      throw const BackendException('auth', 'Identifiants invalides ou compte non vérifié.');
    }
    _signedIn = true;
    _email = email.trim();
    if (liveSensors) _startSensors();
    _auth.add(true);
  }

  @override
  Future<void> signUp(String email, String password, String displayName) => signIn(email, password);

  @override
  Future<void> resetPassword(String email) => _wait();

  @override
  Future<void> updatePassword(String newPassword) => _wait();

  @override
  Future<void> signOut() async {
    _signedIn = false;
    _sensorTimer?.cancel();
    _auth.add(false);
  }

  @override
  Future<void> deleteAccount() async {
    await _wait();
    _homes.clear();
    await signOut();
  }

  @override
  Future<void> updateLocale(String locale) async {}

  // ------------------------------------------------------------------ Maisons
  @override
  Future<List<Home>> listHomes() async {
    await _wait();
    return _members
        .where((m) => m['user_id'] == _me && _homes.containsKey(m['home_id']))
        .map((m) => Home.fromJson(_homes[m['home_id']]!, homeRoleFrom(m['role'] as String)))
        .toList();
  }

  @override
  Future<Home> createHome(String name, String timezone) async {
    await _wait();
    final id = newUuid();
    _homes[id] = {'id': id, 'owner_id': _me, 'name': name.trim(), 'timezone': timezone};
    _members.add({'home_id': id, 'user_id': _me, 'role': 'owner', 'permissions': {}, 'profiles': {'display_name': 'Vous'}});
    return Home.fromJson(_homes[id]!, HomeRole.owner);
  }

  @override
  Future<void> renameHome(String homeId, String name) async {
    await _wait();
    _requireManager(homeId);
    _homes[homeId]!['name'] = name.trim();
    _log(homeId, 'config_changed', result: 'homes_update', details: {'name': name});
  }

  @override
  Future<void> deleteHome(String homeId) async {
    await _wait();
    if (_homes[homeId]?['owner_id'] != _me) throw const BackendException('denied', 'Accès refusé.');
    _homes.remove(homeId);
    _members.removeWhere((m) => m['home_id'] == homeId);
  }

  @override
  Future<List<Member>> listMembers(String homeId) async {
    await _wait();
    return _members.where((m) => m['home_id'] == homeId).map(Member.fromJson).toList();
  }

  @override
  Future<void> updateMember(String homeId, String userId, {HomeRole? role, List<String>? allowedDevices, bool clearRestriction = false}) async {
    await _wait();
    _requireManager(homeId);
    final m = _members.firstWhere((m) => m['home_id'] == homeId && m['user_id'] == userId);
    if (m['role'] == 'owner') throw const BackendException('denied', 'Accès refusé.');
    if (role != null) m['role'] = role.name;
    if (clearRestriction) m['permissions'] = {};
    if (allowedDevices != null) m['permissions'] = {'devices': allowedDevices};
    _log(homeId, 'member_changed', result: 'update', details: {'user_id': userId, 'role': m['role']});
  }

  @override
  Future<void> removeMember(String homeId, String userId) async {
    await _wait();
    _requireManager(homeId);
    _members.removeWhere((m) => m['home_id'] == homeId && m['user_id'] == userId && m['role'] != 'owner');
    _log(homeId, 'member_changed', result: 'delete', details: {'user_id': userId});
  }

  @override
  Future<void> transferOwnership(String homeId, String newOwnerId) async {
    await _wait();
    if (_member(homeId)?['role'] != 'owner') throw const BackendException('denied', 'Accès refusé.');
    _member(homeId)!['role'] = 'admin';
    _members.firstWhere((m) => m['home_id'] == homeId && m['user_id'] == newOwnerId)
      ..['role'] = 'owner'
      ..['permissions'] = {};
    _homes[homeId]!['owner_id'] = newOwnerId;
  }

  @override
  Future<Invitation> invite(String homeId, String email, HomeRole role) async {
    await _wait();
    _requireManager(homeId);
    final row = {
      'id': newUuid(),
      'home_id': homeId,
      'email': email.trim().toLowerCase(),
      'role': role.name,
      'token': newUuid().replaceAll('-', ''),
      'expires_at': DateTime.now().toUtc().add(const Duration(days: 7)).toIso8601String(),
    };
    _invitations.add(row);
    return Invitation.fromJson(row);
  }

  @override
  Future<List<Invitation>> listInvitations(String homeId) async {
    await _wait();
    return _invitations.where((i) => i['home_id'] == homeId).map(Invitation.fromJson).toList();
  }

  @override
  Future<void> revokeInvitation(String invitationId) async {
    await _wait();
    _invitations.removeWhere((i) => i['id'] == invitationId);
  }

  @override
  Future<List<Invitation>> myInvitations() async {
    await _wait();
    return const [];
  }

  @override
  Future<String> acceptInvitation(String token) async {
    await _wait();
    throw const BackendException('invalid', 'Invitation invalide ou expirée');
  }

  // ------------------------------------------------------------------ Pièces
  @override
  Future<List<Room>> listRooms(String homeId) async {
    await _wait();
    return _rooms.values.where((r) => r['home_id'] == homeId).map(Room.fromJson).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  @override
  Future<Room> createRoom(String homeId, String name, String? icon, int sortOrder) async {
    await _wait();
    _requireManager(homeId);
    final id = newUuid();
    _rooms[id] = {'id': id, 'home_id': homeId, 'name': name.trim(), 'icon': icon, 'sort_order': sortOrder};
    _log(homeId, 'config_changed', result: 'rooms_insert', details: {'name': name});
    return Room.fromJson(_rooms[id]!);
  }

  @override
  Future<void> updateRoom(Room room) async {
    await _wait();
    _requireManager(room.homeId);
    _rooms[room.id]!
      ..['name'] = room.name
      ..['icon'] = room.icon
      ..['sort_order'] = room.sortOrder;
  }

  @override
  Future<void> deleteRoom(String roomId) async {
    await _wait();
    final r = _rooms.remove(roomId);
    if (r == null) return;
    for (final d in _devices.values) {
      if (d['room_id'] == roomId) d['room_id'] = null;
    }
    _log(r['home_id'] as String, 'config_changed', result: 'rooms_delete', details: {'name': r['name']});
  }

  // ------------------------------------------------------------------ Appareils
  @override
  Future<List<Device>> listDevices(String homeId) async {
    await _wait();
    return _devices.values.where((d) => d['home_id'] == homeId).map((d) => Device.fromJson(_deviceRow(d['id'] as String))).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<void> updateDevice(String deviceId, {String? name, String? roomId, bool clearRoom = false, bool? isPinned, bool? isHidden}) async {
    await _wait();
    final d = _devices[deviceId]!;
    if (name != null) d['name'] = name.trim();
    if (roomId != null) d['room_id'] = roomId;
    if (clearRoom) d['room_id'] = null;
    if (isPinned != null) d['is_pinned'] = isPinned;
    if (isHidden != null) d['is_hidden'] = isHidden;
    d['updated_at'] = _now();
    _events.add(RealtimeEvent('devices', 'UPDATE', Map<String, dynamic>.from(d)));
  }

  // ------------------------------------------------------------------ Commandes
  @override
  Future<DeviceCommand> sendCommand({
    required String homeId,
    required String deviceId,
    required String capabilityKey,
    required dynamic value,
    required String idempotencyKey,
    String? sceneRunId,
  }) async {
    await _wait();
    for (final c in _commands.values) {
      if (c['idempotency_key'] == idempotencyKey) throw const BackendException('invalid', 'Cet élément existe déjà.');
    }
    final d = _devices[deviceId];
    if (d == null) throw const BackendException('invalid', 'Appareil introuvable');
    if (d['is_sensitive'] == true) throw const BackendException('invalid', 'Commande bloquée : appareil sensible non validé');
    final cap = _caps.where((c) => c['device_id'] == deviceId && c['capability_key'] == capabilityKey && c['writable'] == true);
    if (cap.isEmpty) throw const BackendException('invalid', 'Capacité non prise en charge par cet appareil');

    final id = newUuid();
    final row = <String, dynamic>{
      'id': id,
      'home_id': homeId,
      'device_id': deviceId,
      'capability_key': capabilityKey,
      'value': value,
      'idempotency_key': idempotencyKey,
      'status': 'pending',
      'created_at': _now(),
      'scene_run_id': sceneRunId,
    };
    _commands[id] = row;
    _log(homeId, 'command', deviceId: deviceId, requestId: id, result: 'pending', details: {'capability_key': capabilityKey});
    _simulateBridge(row);
    return DeviceCommand.fromJson(row);
  }

  /// Simule la passerelle : envoi, puis confirmation par retour d'état ou échec.
  Future<Map<String, dynamic>> _simulateBridge(Map<String, dynamic> row) {
    final done = Completer<Map<String, dynamic>>();
    final d = _devices[row['device_id']]!;
    Timer(confirmDelay ~/ 3, () {
      row['status'] = 'sent';
      _events.add(RealtimeEvent('device_commands', 'UPDATE', Map<String, dynamic>.from(row)));
    });
    final offline = d['availability'] != 'available';
    Timer(offline ? confirmDelay * 3 : confirmDelay, () {
      if (offline) {
        row['status'] = 'timeout';
        row['error'] = 'Appareil injoignable : aucune réponse de la passerelle';
        _log(row['home_id'] as String, 'command_failed', deviceId: d['id'] as String, requestId: row['id'] as String, result: 'timeout', details: {'error': row['error']});
      } else {
        row['status'] = 'confirmed';
        final state = Map<String, dynamic>.from(d['state'] as Map)..[row['capability_key'] as String] = row['value'];
        if (row['capability_key'] == 'switch' && d['name'] == 'Prise café') state['power'] = row['value'] == true ? 1180.0 : 0.0;
        d['state'] = state;
        d['last_seen_at'] = _now();
        d['updated_at'] = _now();
        _events.add(RealtimeEvent('devices', 'UPDATE', Map<String, dynamic>.from(d)));
        _log(row['home_id'] as String, 'command', deviceId: d['id'] as String, requestId: row['id'] as String, result: 'confirmed');
      }
      row['completed_at'] = _now();
      _events.add(RealtimeEvent('device_commands', 'UPDATE', Map<String, dynamic>.from(row)));
      done.complete(row);
    });
    return done.future;
  }

  @override
  Future<DeviceCommand?> getCommand(String commandId) async {
    final row = _commands[commandId];
    return row == null ? null : DeviceCommand.fromJson(row);
  }

  // ------------------------------------------------------------------ Scènes
  @override
  Future<List<Scene>> listScenes(String homeId) async {
    await _wait();
    return _scenes.values.where((s) => s['home_id'] == homeId).map(Scene.fromJson).toList();
  }

  @override
  Future<Scene> saveScene(Scene scene, {bool isNew = false}) async {
    await _wait();
    _requireManager(scene.homeId);
    _scenes[scene.id] = {
      'id': scene.id,
      'home_id': scene.homeId,
      'name': scene.name.trim(),
      'icon': scene.icon,
      'enabled': scene.enabled,
      'failure_policy': scene.failurePolicy == FailurePolicy.stop ? 'stop' : 'continue',
      'scene_actions': [for (var i = 0; i < scene.actions.length; i++) {'id': newUuid(), ...scene.actions[i].toJson(scene.id, i)}],
    };
    _log(scene.homeId, 'config_changed', result: isNew ? 'scenes_insert' : 'scenes_update', details: {'name': scene.name});
    return Scene.fromJson(_scenes[scene.id]!);
  }

  @override
  Future<void> deleteScene(String sceneId) async {
    await _wait();
    _scenes.remove(sceneId);
  }

  @override
  Future<String> executeScene(String sceneId) async {
    await _wait();
    final s = _scenes[sceneId];
    if (s == null) throw const BackendException('invalid', 'Scène introuvable');
    if (s['enabled'] != true) throw const BackendException('invalid', 'Scène désactivée');
    final homeId = s['home_id'] as String;
    final runId = newUuid();
    final run = <String, dynamic>{
      'id': runId,
      'scene_id': sceneId,
      'home_id': homeId,
      'status': 'running',
      'results': <Map<String, dynamic>>[],
      'started_at': _now(),
    };
    _runs.insert(0, run);
    _log(homeId, 'scene_started', result: 'running', details: {'scene_id': sceneId, 'scene_run_id': runId});
    _events.add(RealtimeEvent('scene_runs', 'INSERT', Map<String, dynamic>.from(run)));

    () async {
      final stop = s['failure_policy'] == 'stop';
      var aborted = false;
      for (final a in (s['scene_actions'] as List).cast<Map<String, dynamic>>()) {
        final results = run['results'] as List<Map<String, dynamic>>;
        if (aborted) {
          results.add({'device_id': a['device_id'], 'capability_key': a['capability_key'], 'status': 'rejected', 'error': 'Scène interrompue'});
          continue;
        }
        final delay = (a['delay_ms'] as int?) ?? 0;
        if (delay > 0) await Future.delayed(Duration(milliseconds: delay));
        try {
          final cmd = await sendCommand(
            homeId: homeId,
            deviceId: a['device_id'] as String,
            capabilityKey: a['capability_key'] as String,
            value: a['value'],
            idempotencyKey: 'scene:$runId:${a['id']}',
            sceneRunId: runId,
          );
          final row = await _waitCommand(cmd.id);
          results.add({'command_id': cmd.id, 'device_id': a['device_id'], 'capability_key': a['capability_key'], 'status': row['status'], 'error': row['error']});
          if (row['status'] != 'confirmed' && stop) aborted = true;
        } on BackendException catch (e) {
          results.add({'device_id': a['device_id'], 'capability_key': a['capability_key'], 'status': 'rejected', 'error': e.message});
          if (stop) aborted = true;
        }
        _events.add(RealtimeEvent('scene_runs', 'UPDATE', Map<String, dynamic>.from(run)));
      }
      final results = run['results'] as List<Map<String, dynamic>>;
      final ok = results.where((r) => r['status'] == 'confirmed').length;
      run['status'] = ok == results.length ? 'success' : (ok == 0 ? 'failed' : 'partial');
      run['finished_at'] = _now();
      _log(homeId, 'scene_finished', result: run['status'] as String, details: {'scene_id': sceneId, 'confirmed': ok, 'total': results.length});
      _events.add(RealtimeEvent('scene_runs', 'UPDATE', Map<String, dynamic>.from(run)));
    }();
    return runId;
  }

  Future<Map<String, dynamic>> _waitCommand(String id) async {
    while (true) {
      final row = _commands[id]!;
      if (row['status'] != 'pending' && row['status'] != 'sent') return row;
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  @override
  Future<List<SceneRun>> listSceneRuns(String homeId, {int limit = 30}) async {
    await _wait();
    return _runs.where((r) => r['home_id'] == homeId).take(limit).map(SceneRun.fromJson).toList();
  }

  // ------------------------------------------------------------------ Automatisations
  @override
  Future<List<Automation>> listAutomations(String homeId) async {
    await _wait();
    return _automations.values.where((a) => a['home_id'] == homeId).map(Automation.fromJson).toList();
  }

  @override
  Future<Automation> saveAutomation(Automation a, {bool isNew = false}) async {
    await _wait();
    _requireManager(a.homeId);
    _automations[a.id] = {...a.toJson(), 'id': a.id};
    _log(a.homeId, 'config_changed', result: isNew ? 'automations_insert' : 'automations_update', details: {'name': a.name});
    return Automation.fromJson(_automations[a.id]!);
  }

  @override
  Future<void> deleteAutomation(String automationId) async {
    await _wait();
    _automations.remove(automationId);
  }

  // ------------------------------------------------------------------ Intégrations
  @override
  Future<List<Integration>> listIntegrations(String homeId) async {
    await _wait();
    return _integrations.where((i) => i['home_id'] == homeId).map(Integration.fromJson).toList();
  }

  @override
  Future<String> createIntegration(String homeId, String provider, String? label) async {
    await _wait();
    _requireManager(homeId);
    final id = newUuid();
    _integrations.add({'id': id, 'home_id': homeId, 'provider': provider, 'status': 'pending', 'label': label});
    return id;
  }

  @override
  Future<void> setIntegrationEnabled(String integrationId, bool enabled) async {
    await _wait();
    _integrations.firstWhere((i) => i['id'] == integrationId)['status'] = enabled ? 'pending' : 'disabled';
  }

  // ------------------------------------------------------------------ Journal
  @override
  Future<List<EventLog>> listEvents(String homeId, {int limit = 100}) async {
    await _wait();
    return _logs.where((l) => l['home_id'] == homeId).take(limit).map(EventLog.fromJson).toList();
  }

  // ------------------------------------------------------------------ Caméras et photos
  @override
  Stream<CameraFrame> watchCamera(String homeId, String deviceId) async* {
    await _wait();
    final d = _devices[deviceId];
    if (d == null || d['availability'] == 'unavailable') return;
    yield CameraFrame(demoCameraFrame(DateTime.now()), DateTime.now());
    yield* Stream.periodic(const Duration(seconds: 1), (_) {
      final now = DateTime.now();
      return CameraFrame(demoCameraFrame(now), now);
    });
  }

  @override
  Future<Uint8List> downloadDevicePhoto(String path) async {
    await _wait();
    final bytes = _photos[path];
    if (bytes == null) throw const BackendException('notFound', 'Image introuvable.');
    return bytes;
  }

  @override
  Future<String> setDevicePhoto(Device device, Uint8List bytes, String contentType) async {
    await _wait();
    final ext = imageExtension(contentType);
    if (ext == null) throw const BackendException('invalid', 'Format d\'image non pris en charge (JPEG, PNG ou WebP).');
    final path = '${device.homeId}/${device.id}-${DateTime.now().millisecondsSinceEpoch}.$ext';
    _photos[path] = bytes;
    _setPhoto(device.id, path);
    return path;
  }

  @override
  Future<void> clearDevicePhoto(Device device) async {
    await _wait();
    _setPhoto(device.id, null);
  }

  void _setPhoto(String deviceId, String? path) {
    final d = _devices[deviceId]!;
    final old = d['photo_path'] as String?;
    if (old != null) _photos.remove(old);
    d['photo_path'] = path;
    d['updated_at'] = _now();
    _events.add(RealtimeEvent('devices', 'UPDATE', Map<String, dynamic>.from(d)));
  }

  // ------------------------------------------------------------------ Temps réel
  @override
  Stream<RealtimeEvent> watchHome(String homeId, {void Function(bool connected)? onStatus}) {
    Timer.run(() => onStatus?.call(true));
    return _events.stream.where((e) => e.record['home_id'] == null || e.record['home_id'] == homeId);
  }

  /// Fait varier les capteurs pour montrer les mises à jour en direct.
  void _startSensors() {
    _sensorTimer?.cancel();
    _sensorTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      for (final d in _devices.values) {
        final state = Map<String, dynamic>.from(d['state'] as Map);
        var changed = false;
        if (state['temperature'] is num) {
          state['temperature'] = double.parse(((state['temperature'] as num) + (_rand.nextDouble() - 0.5) * 0.4).toStringAsFixed(1));
          changed = true;
        }
        if (state['current_temperature'] is num) {
          final target = (state['target_temperature'] as num?) ?? 21;
          final cur = state['current_temperature'] as num;
          state['current_temperature'] = double.parse((cur + (target - cur) * 0.15).toStringAsFixed(1));
          changed = true;
        }
        if (changed) {
          d['state'] = state;
          d['last_seen_at'] = _now();
          _events.add(RealtimeEvent('devices', 'UPDATE', Map<String, dynamic>.from(d)));
        }
      }
    });
  }
}
