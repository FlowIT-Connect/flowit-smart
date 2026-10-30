
import 'package:flowit_smart/core/ble_lock.dart';
import 'package:flowit_smart/data/backend.dart';
import 'package:flowit_smart/data/demo_backend.dart';
import 'package:flowit_smart/models/models.dart';
import 'package:flowit_smart/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Backend de démo dont la passerelle ne répond jamais.
class SilentBackend extends DemoBackend {
  SilentBackend() : super(latency: Duration.zero, confirmDelay: const Duration(hours: 1), liveSensors: false);
}

/// Bluetooth simulé : note les clés reçues, peut échouer.
class FakeBle implements BleLock {
  final calls = <(String, bool)>[];
  BleLockException? failWith;

  @override
  bool get available => true;

  @override
  Future<void> control(String lockData, {required bool unlock}) async {
    calls.add((lockData, unlock));
    if (failWith != null) throw failWith!;
  }
}

Future<AppState> signedIn(Backend backend, {Duration timeout = const Duration(seconds: 15), BleLock ble = const NoBleLock()}) async {
  final state = AppState(backend, commandTimeout: timeout, ble: ble);
  await backend.signIn('test@flowit.dz', 'x');
  for (var i = 0; i < 50 && state.devices.isEmpty; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return state;
}

Device byName(AppState s, String name) => s.devices.values.firstWhere((d) => d.name == name);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('commande : attente puis confirmation, état mis à jour', () async {
    final state = await signedIn(DemoBackend(latency: Duration.zero, confirmDelay: const Duration(milliseconds: 200), liveSensors: false));
    final plug = byName(state, 'Prise café');
    expect(plug.isOn, isFalse);

    await state.sendCommand(plug, 'switch', true);
    expect(state.pendingFor(plug.id, 'switch')?.isWaiting, isTrue, reason: 'pas de succès avant confirmation');
    expect(state.devices[plug.id]!.isOn, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(state.pendingFor(plug.id, 'switch')?.status, CommandStatus.confirmed);
    expect(state.devices[plug.id]!.isOn, isTrue);
  });

  test('double commande ignorée tant que la première attend', () async {
    final backend = DemoBackend(latency: Duration.zero, confirmDelay: const Duration(milliseconds: 300), liveSensors: false);
    final state = await signedIn(backend);
    final light = byName(state, 'Plafonnier');
    await state.sendCommand(light, 'switch', false);
    final first = state.pendingFor(light.id, 'switch')!.commandId;
    await state.sendCommand(light, 'switch', true);
    expect(state.pendingFor(light.id, 'switch')!.commandId, first);
    expect(state.pendingFor(light.id, 'switch')!.value, false);
  });

  test('appareil hors ligne : délai dépassé signalé', () async {
    final state = await signedIn(DemoBackend(latency: Duration.zero, confirmDelay: const Duration(milliseconds: 100), liveSensors: false));
    final notices = <Notice>[];
    state.notices.listen(notices.add);
    final bulb = byName(state, 'Ampoule chevet');
    expect(bulb.availability, Availability.unavailable);
    await state.sendCommand(bulb, 'switch', true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(state.pendingFor(bulb.id, 'switch')?.status, CommandStatus.timeout);
    expect(notices.any((n) => n.isError), isTrue);
  });

  test('passerelle muette : délai client de sécurité', () async {
    final state = await signedIn(SilentBackend(), timeout: const Duration(seconds: 3));
    final plug = byName(state, 'Prise café');
    await state.sendCommand(plug, 'switch', true);
    await Future<void>.delayed(const Duration(seconds: 5));
    expect(state.pendingFor(plug.id, 'switch')?.status, CommandStatus.timeout);
    expect(state.devices[plug.id]!.isOn, isFalse, reason: 'état inchangé sans confirmation');
  });

  test('appareil sensible : aucune commande envoyée', () async {
    final state = await signedIn(DemoBackend(latency: Duration.zero, liveSensors: false));
    final lock = byName(state, 'Serrure');
    await state.sendCommand(lock, 'lock', false);
    expect(state.pendingFor(lock.id, 'lock'), isNull);
  });

  test('contrôle d\'accès : bloqué, activé par le propriétaire, code créé', () async {
    final state = await signedIn(DemoBackend(latency: Duration.zero, confirmDelay: const Duration(milliseconds: 100), liveSensors: false));
    final box = byName(state, 'Boîtier d\'accès');
    expect(box.isAccessControl, isTrue);
    expect(box.isBlocked, isTrue);
    expect(await state.sendCommandAndWait(box, 'access_code', {'type': 'one_time'}), isNull);

    expect(await state.setDeviceSecurity(box, true), isTrue);
    final enabled = byName(state, 'Boîtier d\'accès');
    expect(enabled.isSecurityEnabled, isTrue);
    final result = await state.sendCommandAndWait(enabled, 'access_code', {'type': 'one_time', 'name': 'Livreur'});
    expect(result?.status, CommandStatus.confirmed);
    final codes = await state.accessCodes(box.id);
    expect(codes.single.commandId, result!.commandId);
    expect(codes.single.name, 'Livreur');
    expect(codes.single.code, matches(RegExp(r'^\d{8}$')));
    expect(AccessRecord.fromState(enabled.state['access_log']).first.method, 'code');

    final start = DateTime.now().add(const Duration(hours: 1)).toUtc().toIso8601String();
    final end = DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String();
    final shared = await state.sendCommandAndWait(enabled, 'ekey', {'action': 'send', 'receiver': 'amina@x.dz', 'name': 'Amina', 'start': start, 'end': end});
    expect(shared?.status, CommandStatus.confirmed);
    final amina = SharedKey.fromState(byName(state, 'Boîtier d\'accès').state['ekeys']).firstWhere((k) => k.name == 'Amina');
    expect(amina.isScheduled, isTrue);
    expect(amina.receiver, 'amina@x.dz');
    await state.sendCommandAndWait(byName(state, 'Boîtier d\'accès'), 'ekey', {'action': 'freeze', 'key_id': amina.id});
    expect(SharedKey.fromState(byName(state, 'Boîtier d\'accès').state['ekeys']).firstWhere((k) => k.id == amina.id).isFrozen, isTrue);
  });

  test('Bluetooth : refusé tant que la serrure est bloquée, puis ouverture et fermeture journalisées', () async {
    final ble = FakeBle();
    final backend = DemoBackend(latency: Duration.zero, confirmDelay: const Duration(milliseconds: 50), liveSensors: false);
    final state = await signedIn(backend, ble: ble);
    final box = byName(state, 'Boîtier d\'accès');
    expect(await state.bleControl(box, unlock: true), isFalse);
    expect(ble.calls, isEmpty);

    await state.setDeviceSecurity(box, true);
    expect(await state.bleControl(byName(state, 'Boîtier d\'accès'), unlock: true), isTrue);
    expect(await state.bleControl(byName(state, 'Boîtier d\'accès'), unlock: false), isTrue);
    expect(ble.calls, [('demo-lockdata', true), ('demo-lockdata', false)]);

    ble.failWith = const BleLockException('timeout', 'hors de portée');
    expect(await state.bleControl(byName(state, 'Boîtier d\'accès'), unlock: true), isFalse);
    expect(state.bleBusy, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final logs = await backend.listEvents(state.home!.id);
    expect(logs.where((e) => e.eventType == 'ble_key_read'), hasLength(1), reason: 'clé lue une fois puis gardée en mémoire');
    expect(logs.where((e) => e.details['channel'] == 'bluetooth').map((e) => e.eventType), containsAll(['command', 'command_failed']));
  });

  test('scène : exécution, résultat partiel journalisé (appareil hors ligne)', () async {
    final state = await signedIn(DemoBackend(latency: Duration.zero, confirmDelay: const Duration(milliseconds: 50), liveSensors: false));
    final scene = state.scenes.firstWhere((s) => s.name == 'Je pars');
    await state.executeScene(scene);
    for (var i = 0; i < 100 && state.sceneRuns.firstOrNull?.finishedAt == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final run = state.sceneRuns.first;
    expect(run.status, 'partial');
    expect(run.results, hasLength(4));
    final events = await state.backend.listEvents(state.home!.id);
    expect(events.any((e) => e.eventType == 'scene_finished'), isTrue);
  });
}
