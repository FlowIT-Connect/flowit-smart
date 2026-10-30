import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_launcher.dart';
import '../core/ble_lock.dart';
import '../core/l10n.dart';
import '../data/backend.dart';
import '../data/weather.dart';
import '../models/models.dart';

/// Commande en cours affichée sur un contrôle (attente, puis résultat réel).
class PendingCommand {
  final String key;
  final dynamic value;
  final CommandStatus status;
  final String? commandId;
  final String? error;

  const PendingCommand(this.key, this.value, this.status, {this.commandId, this.error});

  bool get isWaiting => status == CommandStatus.pending || status == CommandStatus.sent;

  PendingCommand withStatus(CommandStatus s, {String? commandId, String? error}) =>
      PendingCommand(key, value, s, commandId: commandId ?? this.commandId, error: error ?? this.error);
}

class Notice {
  final String message;
  final bool isError;
  const Notice(this.message, {this.isError = false});
}

/// État global de l'application (session, maison courante, données, temps réel).
class AppState extends ChangeNotifier {
  AppState(this.backend,
      {Locale? initialLocale,
      this.commandTimeout = const Duration(seconds: 15),
      this.weatherService,
      this.ble = const NoBleLock(),
      this.launcher = const AppLauncher(),
      this.pairingPoll = const Duration(seconds: 2)})
      : locale = initialLocale ?? const Locale('fr') {
    _authSub = backend.authChanges.listen(_onAuth);
    _recoverySub = backend.passwordRecovery.listen((_) {
      passwordRecovery = true;
      notifyListeners();
    });
    if (backend.currentUserId != null) _onAuth(true);
  }

  final Backend backend;
  final Duration commandTimeout;

  /// Bluetooth TTLock (app Android) ; indisponible sur le web.
  final BleLock ble;
  final _bleKeys = <String, String>{};

  /// Ouverture de Smart Life pour coupler un appareil Tuya (app Android).
  final AppLauncher launcher;

  /// Fréquence de lecture de l'état d'un ajout d'appareil.
  final Duration pairingPoll;

  /// Serrure en cours d'ouverture / fermeture Bluetooth (id de l'appareil).
  String? bleBusy;

  /// Météo extérieure (null : désactivée, par ex. dans les tests).
  final WeatherService? weatherService;
  late final StreamSubscription<bool> _authSub;
  late final StreamSubscription<void> _recoverySub;
  StreamSubscription<RealtimeEvent>? _realtimeSub;
  final _notices = StreamController<Notice>.broadcast();
  Timer? _reloadDebounce;

  Locale locale;
  bool signedIn = false;
  bool loading = false;
  bool online = true;
  bool realtimeConnected = true;
  bool passwordRecovery = false;
  String? loadError;

  List<Home> homes = const [];
  Home? home;
  List<Room> rooms = const [];
  Map<String, Device> devices = const {};
  List<Scene> scenes = const [];
  List<Automation> automations = const [];
  List<SceneRun> sceneRuns = const [];
  List<Invitation> myInvitations = const [];
  final Map<String, PendingCommand> pending = {};
  final Map<String, Completer<PendingCommand?>> _waiters = {};

  WeatherPlace weatherPlace = WeatherPlace.algiers;
  WeatherReport? weather;
  bool _weatherLoading = false;
  DateTime? _weatherTriedAt;
  final Map<String, Future<Uint8List?>> _photoCache = {};

  Stream<Notice> get notices => _notices.stream;
  String tr(String key, [Map<String, Object?> args = const {}]) => L10n.of(locale).t(key, args);

  HomeRole get role => home?.myRole ?? HomeRole.member;
  bool get canManage => role.canManage;

  List<Device> get visibleDevices => devices.values.where((d) => !d.isHidden).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  List<Device> devicesInRoom(String? roomId) => visibleDevices.where((d) => d.roomId == roomId).toList();

  Room? roomById(String? id) {
    for (final r in rooms) {
      if (r.id == id) return r;
    }
    return null;
  }

  Scene? sceneById(String id) {
    for (final s in scenes) {
      if (s.id == id) return s;
    }
    return null;
  }

  // ---------------------------------------------------------------- Langue
  Future<void> setLocale(Locale l) async {
    locale = l;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('locale', l.languageCode);
      if (signedIn) await backend.updateLocale(l.languageCode);
    } catch (_) {}
  }

  // ---------------------------------------------------------------- Exécution sûre
  /// Exécute une action ; affiche l'erreur traduite et renvoie false en cas d'échec.
  Future<bool> run(Future<void> Function() action, {String? success}) async {
    try {
      await action();
      _setOnline(true);
      if (success != null) _notices.add(Notice(success));
      return true;
    } on BackendException catch (e) {
      if (e.code == 'network') _setOnline(false);
      _notices.add(Notice(_errorText(e), isError: true));
      return false;
    }
  }

  String _errorText(BackendException e) => switch (e.code) {
        'network' => tr('error.network'),
        'denied' => tr('error.denied'),
        'auth' => tr('error.auth'),
        'rate' => tr('error.rate'),
        _ => e.message,
      };

  void _setOnline(bool v) {
    if (online == v) return;
    online = v;
    notifyListeners();
  }

  void notify(String message, {bool error = false}) => _notices.add(Notice(message, isError: error));

  // ---------------------------------------------------------------- Session
  Future<void> _onAuth(bool isSignedIn) async {
    if (isSignedIn == signedIn) return;
    signedIn = isSignedIn;
    if (!isSignedIn) {
      _bleKeys.clear(); // la clé Bluetooth ne survit pas à la déconnexion
      _clearHome();
      homes = const [];
      home = null;
      notifyListeners();
      return;
    }
    notifyListeners();
    await loadHomes();
  }

  Future<void> signOut() async {
    await run(backend.signOut);
  }

  Future<void> loadHomes({String? select}) async {
    loading = true;
    loadError = null;
    notifyListeners();
    try {
      homes = await backend.listHomes();
      myInvitations = await backend.myInvitations();
      _setOnline(true);
      String? wanted = select;
      if (wanted == null) {
        try {
          wanted = (await SharedPreferences.getInstance()).getString('home');
        } catch (_) {}
      }
      final target = homes.where((h) => h.id == wanted).firstOrNull ?? homes.firstOrNull;
      if (target != null) {
        await selectHome(target);
      } else {
        _clearHome();
        home = null;
      }
    } on BackendException catch (e) {
      if (e.code == 'network') online = false;
      loadError = _errorText(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> selectHome(Home h) async {
    _clearHome();
    home = h;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('home', h.id);
      final saved = prefs.getString('weather.place.${h.id}');
      if (saved != null) weatherPlace = WeatherPlace.fromJson(jsonDecode(saved) as Map<String, dynamic>);
    } catch (_) {}
    await refreshHome();
    unawaited(refreshWeather());
    _realtimeSub = backend.watchHome(h.id, onStatus: (connected) {
      if (realtimeConnected == connected) return;
      realtimeConnected = connected;
      notifyListeners();
      if (connected) refreshHome(silent: true); // resynchronise après reconnexion
    }).listen(_onRealtime);
  }

  void _clearHome() {
    _realtimeSub?.cancel();
    _realtimeSub = null;
    rooms = const [];
    devices = const {};
    scenes = const [];
    automations = const [];
    sceneRuns = const [];
    pending.clear();
    _photoCache.clear();
    weather = null;
    _weatherTriedAt = null;
    weatherPlace = WeatherPlace.algiers;
  }

  Future<void> refreshHome({bool silent = false}) async {
    final h = home;
    if (h == null) return;
    if (!silent) {
      loading = true;
      loadError = null;
      notifyListeners();
    }
    try {
      final results = await Future.wait([
        backend.listRooms(h.id),
        backend.listDevices(h.id),
        backend.listScenes(h.id),
        backend.listAutomations(h.id),
        backend.listSceneRuns(h.id),
      ]);
      if (home?.id != h.id) return;
      rooms = results[0] as List<Room>;
      devices = {for (final d in results[1] as List<Device>) d.id: d};
      scenes = results[2] as List<Scene>;
      automations = results[3] as List<Automation>;
      sceneRuns = results[4] as List<SceneRun>;
      loadError = null;
      _setOnline(true);
    } on BackendException catch (e) {
      if (e.code == 'network') online = false;
      if (!silent) loadError = _errorText(e);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- Temps réel
  void _onRealtime(RealtimeEvent e) {
    switch (e.table) {
      case 'devices':
        final id = e.record['id'] as String?;
        if (id == null) return;
        if (e.type == 'DELETE') {
          devices = Map.of(devices)..remove(id);
        } else if (devices.containsKey(id)) {
          devices = Map.of(devices)..[id] = devices[id]!.mergeRow(e.record);
        } else {
          _scheduleReload();
          return;
        }
        notifyListeners();
      case 'device_capabilities':
        _scheduleReload();
      case 'device_commands':
        _onCommandUpdate(DeviceCommand.fromJson(e.record));
      case 'scene_runs':
        final run = SceneRun.fromJson(e.record);
        final previous = sceneRuns.where((r) => r.id == run.id).firstOrNull;
        sceneRuns = [run, ...sceneRuns.where((r) => r.id != run.id)]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
        if (run.finishedAt != null && previous?.finishedAt == null) _announceRun(run);
        notifyListeners();
    }
  }

  void _scheduleReload() {
    _reloadDebounce?.cancel();
    _reloadDebounce = Timer(const Duration(milliseconds: 600), () async {
      final h = home;
      if (h == null) return;
      try {
        final list = await backend.listDevices(h.id);
        devices = {for (final d in list) d.id: d};
        notifyListeners();
      } on BackendException catch (_) {}
    });
  }

  void _announceRun(SceneRun run) {
    final scene = sceneById(run.sceneId);
    final ok = run.results.where((r) => r['status'] == 'confirmed').length;
    notify(
      tr('scene.finished', {'name': scene?.name ?? '', 'status': tr('run.${run.status}'), 'ok': ok, 'total': run.results.length}),
      error: run.status != 'success',
    );
  }

  // ---------------------------------------------------------------- Commandes (§5.4)
  static String pendingKey(String deviceId, String cap) => '$deviceId|$cap';

  PendingCommand? pendingFor(String deviceId, String cap) => pending[pendingKey(deviceId, cap)];

  /// Envoie une commande : état d'attente, puis résultat confirmé ou erreur.
  /// Une seconde commande sur le même contrôle est ignorée tant que la première attend.
  Future<void> sendCommand(Device device, String cap, dynamic value) async {
    final key = pendingKey(device.id, cap);
    if (pending[key]?.isWaiting ?? false) return;
    if (device.isBlocked) {
      notify(tr('device.sensitiveBlocked'), error: true);
      _waiters.remove(key)?.complete(null);
      return;
    }
    pending[key] = PendingCommand(key, value, CommandStatus.pending);
    notifyListeners();
    try {
      final cmd = await backend.sendCommand(
        homeId: device.homeId,
        deviceId: device.id,
        capabilityKey: cap,
        value: value,
        idempotencyKey: newUuid(),
      );
      _setOnline(true);
      final current = pending[key];
      if (current == null || !current.isWaiting) return;
      pending[key] = current.withStatus(cmd.status, commandId: cmd.id);
      notifyListeners();
      _watchCommand(key, cmd.id);
    } on BackendException catch (e) {
      if (e.code == 'network') _setOnline(false);
      _finishCommand(key, CommandStatus.rejected, _errorText(e), device.name);
    }
  }

  /// Comme [sendCommand], puis attend le résultat définitif (null si la commande n'est pas partie).
  Future<PendingCommand?> sendCommandAndWait(Device device, String cap, dynamic value) {
    final key = pendingKey(device.id, cap);
    if (pending[key]?.isWaiting ?? false) return Future.value(null);
    final waiter = Completer<PendingCommand?>();
    _waiters[key] = waiter;
    sendCommand(device, cap, value);
    return waiter.future;
  }

  /// Suivi de secours par interrogation (si le temps réel est coupé) et délai maximal.
  void _watchCommand(String key, String commandId) {
    final deadline = DateTime.now().add(commandTimeout);
    Timer.periodic(const Duration(seconds: 2), (t) async {
      final p = pending[key];
      if (p == null || p.commandId != commandId || !p.isWaiting) {
        t.cancel();
        return;
      }
      if (DateTime.now().isAfter(deadline)) {
        t.cancel();
        _finishCommand(key, CommandStatus.timeout, tr('command.noResponse'), devices[key.split('|').first]?.name);
        return;
      }
      if (realtimeConnected) return;
      try {
        final cmd = await backend.getCommand(commandId);
        if (cmd != null) _onCommandUpdate(cmd);
      } on BackendException catch (_) {}
    });
  }

  void _onCommandUpdate(DeviceCommand cmd) {
    final key = pendingKey(cmd.deviceId, cmd.capabilityKey);
    final p = pending[key];
    if (p == null || p.commandId != cmd.id) return;
    if (cmd.isWaiting) {
      pending[key] = p.withStatus(cmd.status);
      notifyListeners();
      return;
    }
    final name = devices[cmd.deviceId]?.name;
    if (cmd.status == CommandStatus.confirmed) {
      // L'état confirmé est aussi appliqué localement si la ligne devices arrive après.
      final d = devices[cmd.deviceId];
      if (d != null && d.state[cmd.capabilityKey] != cmd.value) {
        devices = Map.of(devices)..[d.id] = d.copyWith(state: {...d.state, cmd.capabilityKey: cmd.value});
      }
      _finishCommand(key, CommandStatus.confirmed, null, name);
    } else {
      _finishCommand(key, cmd.status, cmd.error ?? tr('command.status.${cmd.status.name}'), name);
    }
  }

  void _finishCommand(String key, CommandStatus status, String? error, String? deviceName) {
    final p = pending[key];
    if (p == null) return;
    pending[key] = p.withStatus(status, error: error);
    notifyListeners();
    _waiters.remove(key)?.complete(pending[key]);
    if (status != CommandStatus.confirmed) {
      notify(tr('command.failed', {'device': deviceName ?? '', 'error': error ?? ''}), error: true);
    }
    Timer(Duration(milliseconds: status == CommandStatus.confirmed ? 900 : 2500), () {
      if (pending[key]?.status == status) {
        pending.remove(key);
        notifyListeners();
      }
    });
  }

  // ---------------------------------------------------------------- Raccourcis de mutation
  /// Ordre local immédiat (réordonnancement), avant l'enregistrement serveur.
  void setRooms(List<Room> list) {
    rooms = list;
    notifyListeners();
  }

  Future<bool> updateDevice(Device d, {String? name, String? roomId, bool clearRoom = false, bool? isPinned, bool? isHidden}) async {
    final ok = await run(() => backend.updateDevice(d.id, name: name, roomId: roomId, clearRoom: clearRoom, isPinned: isPinned, isHidden: isHidden));
    if (ok) {
      devices = Map.of(devices)
        ..[d.id] = d.copyWith(name: name, roomId: roomId, clearRoom: clearRoom, isPinned: isPinned, isHidden: isHidden);
      notifyListeners();
    }
    return ok;
  }

  /// Active ou bloque un appareil de sécurité (serrure) : propriétaire uniquement.
  Future<bool> setDeviceSecurity(Device d, bool enabled) async {
    if (!enabled) _bleKeys.remove(d.id);
    final ok = await run(() => backend.setDeviceSecurity(d.id, enabled),
        success: tr(enabled ? 'access.enabledNotice' : 'access.disabledNotice'));
    if (ok) {
      devices = Map.of(devices)..[d.id] = d.copyWith(securityValidatedAt: enabled ? DateTime.now() : null, clearSecurity: !enabled);
      notifyListeners();
    }
    return ok;
  }

  /// Ouvre ou ferme une serrure TTLock en Bluetooth, devant la porte (app Android).
  Future<bool> bleControl(Device d, {required bool unlock}) async {
    if (bleBusy != null) return false;
    bleBusy = d.id;
    notifyListeners();
    try {
      final key = _bleKeys[d.id] ??= await backend.bleKey(d.id);
      try {
        await ble.control(key, unlock: unlock);
      } on BleLockException catch (e) {
        unawaited(backend.logBleAction(d.id, unlock: unlock, ok: false, error: e.code).catchError((_) {}));
        notify(tr('access.ble.error.${e.code}'), error: true);
        return false;
      }
      unawaited(backend.logBleAction(d.id, unlock: unlock, ok: true).catchError((_) {}));
      notify(tr(unlock ? 'access.ble.unlocked' : 'access.ble.locked', {'name': d.name}));
      return true;
    } on BackendException catch (e) {
      notify(_errorText(e), error: true);
      return false;
    } finally {
      bleBusy = null;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- Ajout d'appareils
  /// Dépose une demande d'ajout pour la passerelle ; null (avec message) en cas de refus.
  Future<String?> requestPairing({required String kind, String? name, String? roomId, String? lockData}) async {
    final h = home;
    if (h == null) return null;
    try {
      final id = await backend.requestPairing(h.id, kind: kind, name: name, roomId: roomId, lockData: lockData);
      _setOnline(true);
      return id;
    } on BackendException catch (e) {
      if (e.code == 'network') _setOnline(false);
      notify(_errorText(e), error: true);
      return null;
    }
  }

  /// Attend la réponse de la passerelle. Renvoie la demande terminée, ou la dernière lue
  /// (encore en attente) si [timeout] est dépassé ; null si elle n'a pas pu être lue.
  Future<PairingRequest?> waitPairing(String requestId, {Duration timeout = const Duration(minutes: 4)}) async {
    final end = DateTime.now().add(timeout);
    PairingRequest? last;
    while (true) {
      try {
        last = await backend.getPairing(requestId) ?? last;
      } on BackendException {
        // Réseau coupé un instant : on réessaie jusqu'au délai.
      }
      if (last != null && last.isFinished) break;
      if (DateTime.now().isAfter(end)) return last;
      await Future<void>.delayed(pairingPoll);
    }
    if (last.status == 'done') await refreshHome(silent: true);
    return last;
  }

  /// Codes d'accès d'une serrure (vide si l'on n'est ni propriétaire ni administrateur).
  Future<List<AccessCode>> accessCodes(String deviceId) async {
    try {
      return await backend.listAccessCodes(deviceId);
    } on BackendException catch (e) {
      notify(_errorText(e), error: true);
      return const [];
    }
  }

  Future<bool> executeScene(Scene s) => run(() async {
        final runId = await backend.executeScene(s.id);
        if (!sceneRuns.any((r) => r.id == runId)) {
          sceneRuns = [SceneRun(id: runId, sceneId: s.id, status: 'running', startedAt: DateTime.now()), ...sceneRuns];
          notifyListeners();
        }
      }, success: tr('scene.started', {'name': s.name}));

  // ---------------------------------------------------------------- Météo extérieure
  /// Actualise la météo si elle date de plus de 15 min (appelé à l'affichage de l'accueil).
  Future<void> refreshWeather({bool force = false}) async {
    final service = weatherService;
    if (service == null || _weatherLoading || home == null) return;
    final last = _weatherTriedAt;
    if (!force && last != null && DateTime.now().difference(last) < const Duration(minutes: 15)) return;
    _weatherLoading = true;
    _weatherTriedAt = DateTime.now();
    final place = weatherPlace;
    try {
      final report = await service.current(place);
      if (place == weatherPlace) {
        weather = report;
        notifyListeners();
      }
    } catch (_) {
      // Météo indisponible : l'accueil n'affiche simplement pas la température extérieure.
    } finally {
      _weatherLoading = false;
    }
  }

  Future<void> setWeatherPlace(WeatherPlace place) async {
    weatherPlace = place;
    weather = null;
    notifyListeners();
    try {
      final h = home;
      if (h != null) (await SharedPreferences.getInstance()).setString('weather.place.${h.id}', jsonEncode(place.toJson()));
    } catch (_) {}
    await refreshWeather(force: true);
  }

  // ---------------------------------------------------------------- Photos d'appareils
  /// Photo prise par l'utilisateur (mise en cache ; null si illisible).
  Future<Uint8List?> devicePhoto(String path) => _photoCache.putIfAbsent(path, () async {
        try {
          return await backend.downloadDevicePhoto(path);
        } on BackendException catch (_) {
          return null;
        }
      });

  Future<bool> setDevicePhoto(Device d, Uint8List bytes, String contentType) => run(() async {
        final path = await backend.setDevicePhoto(d, bytes, contentType);
        _photoCache[path] = Future.value(bytes);
        final current = devices[d.id] ?? d;
        devices = Map.of(devices)..[d.id] = current.copyWith(photoPath: path);
        notifyListeners();
      }, success: tr('photo.saved'));

  Future<bool> clearDevicePhoto(Device d) => run(() async {
        await backend.clearDevicePhoto(d);
        final current = devices[d.id] ?? d;
        devices = Map.of(devices)..[d.id] = current.copyWith(clearPhoto: true);
        notifyListeners();
      });

  @override
  void dispose() {
    _authSub.cancel();
    _recoverySub.cancel();
    _realtimeSub?.cancel();
    _reloadDebounce?.cancel();
    _notices.close();
    super.dispose();
  }
}

/// Donne accès à [AppState] et reconstruit les widgets à chaque changement.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Accès sans abonnement (callbacks).
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
