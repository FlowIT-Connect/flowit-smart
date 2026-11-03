import 'package:flowit_smart/core/qr/qr_recognition.dart';
import 'package:flowit_smart/data/demo_backend.dart';
import 'package:flowit_smart/models/models.dart';
import 'package:flowit_smart/state/app_state.dart';
import 'package:flowit_smart/ui/screens/qr_device_flow_screen.dart';
import 'package:flowit_smart/ui/widgets/room_visual.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show pumpApp, signIn;

Device byName(AppState s, String name) => s.devices.values.firstWhere((d) => d.name == name);

Future<AppState> signedIn(DemoBackend backend) async {
  final state = AppState(backend);
  await backend.signIn('test@flowit.dz', 'x');
  for (var i = 0; i < 50 && state.devices.isEmpty; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return state;
}

/// Appui long puis glisser jusqu'à [to] (mode organisation actif pendant le geste).
Future<TestGesture> longPressDrag(WidgetTester tester, Finder from) async {
  final gesture = await tester.startGesture(tester.getCenter(from));
  await tester.pump(const Duration(milliseconds: 700));
  await gesture.moveBy(const Offset(4, 4));
  await tester.pump(const Duration(milliseconds: 50));
  return gesture;
}

Finder tileOf(String name) => find.ancestor(of: find.text(name).first, matching: find.byType(Card)).first;

void main() {
  group('ordre et suppression (état)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('ordre personnel enregistré et retrouvé à la réouverture', () async {
      final backend = DemoBackend(latency: Duration.zero, liveSensors: false);
      final first = await signedIn(backend);
      final pinned = first.visibleDevices.where((d) => d.isPinned).toList();
      final reversed = [for (final d in pinned.reversed) d.id];
      await first.saveOrder('favorites', reversed);
      expect([for (final d in first.ordered('favorites', pinned)) d.id], reversed);

      // « Fermer et rouvrir » : nouvel état, même compte.
      SharedPreferences.setMockInitialValues({});
      final again = AppState(backend);
      for (var i = 0; i < 50 && again.devices.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final pinnedAgain = again.visibleDevices.where((d) => d.isPinned).toList();
      expect([for (final d in again.ordered('favorites', pinnedAgain)) d.id], reversed);
    });

    test('retirer de ma résidence : favoris, scènes et ordre nettoyés, puis remise', () async {
      final backend = DemoBackend(latency: Duration.zero, liveSensors: false);
      final state = await signedIn(backend);
      final lamp = byName(state, 'Plafonnier');
      await state.saveOrder('devices', [lamp.id, byName(state, 'Prise café').id]);
      final result = await state.removeDevice(lamp, unlink: false);
      expect(result, isNotNull);
      expect(result!.scenes, greaterThanOrEqualTo(2));
      expect(state.devices.containsKey(lamp.id), isFalse);
      expect(state.layouts['devices'], isNot(contains(lamp.id)));
      await state.refreshHome(silent: true);
      expect(state.devices.containsKey(lamp.id), isFalse, reason: 'invisible après rechargement');
      expect(state.scenes.expand((s) => s.actions).any((a) => a.deviceId == lamp.id), isFalse);
      final removed = await state.loadRemovedDevices();
      expect(removed.map((d) => d.name), contains('Plafonnier'));
      expect(await state.restoreDevice(removed.firstWhere((d) => d.id == lamp.id)), isTrue);
      expect(state.devices.containsKey(lamp.id), isTrue);
      expect(state.devices[lamp.id]!.isPinned, isFalse, reason: 'retiré des favoris');
    });

    test('dissocier définitivement : supprimé, puis autorisé de nouveau', () async {
      final backend = DemoBackend(latency: Duration.zero, liveSensors: false);
      final state = await signedIn(backend);
      final plug = byName(state, 'Prise café');
      expect(await state.removeDevice(plug, unlink: true), isNotNull);
      await state.refreshHome(silent: true);
      expect(state.devices.containsKey(plug.id), isFalse);
      expect(await state.loadRemovedDevices(), isEmpty, reason: 'pas dans les appareils retirés');
      final excluded = await state.loadExcludedDevices();
      expect(excluded.single.name, 'Prise café');
      expect(await state.allowExcludedDevice(excluded.single), isTrue);
      expect(await state.loadExcludedDevices(), isEmpty);
    });

    test('pièces : ordre personnel, suppression avec déplacement des appareils', () async {
      final backend = DemoBackend(latency: Duration.zero, liveSensors: false);
      final state = await signedIn(backend);
      expect(state.rooms.length, greaterThan(1));
      final reversed = [for (final r in state.rooms.reversed) r.id];
      await state.saveOrder('rooms', reversed);
      expect([for (final r in state.orderedRooms) r.id], reversed);

      final room = state.rooms.firstWhere((r) => state.devices.values.any((d) => d.roomId == r.id));
      final target = state.rooms.firstWhere((r) => r.id != room.id);
      final inside = [for (final d in state.devices.values) if (d.roomId == room.id) d.id];
      await state.saveOrder(AppState.roomSection(room.id), inside);
      expect(await state.deleteRoom(room, moveTo: target.id), isTrue);
      expect(state.rooms.any((r) => r.id == room.id), isFalse);
      for (final id in inside) {
        expect(state.devices[id]!.roomId, target.id, reason: 'appareil rangé dans la pièce choisie');
      }
      expect(state.layouts['rooms'], isNot(contains(room.id)));
      expect(state.layouts.containsKey(AppState.roomSection(room.id)), isFalse);
      await state.refreshHome(silent: true);
      expect(state.rooms.any((r) => r.id == room.id), isFalse, reason: 'supprimée sur le serveur');
      for (final id in inside) {
        expect(state.devices[id]!.roomId, target.id);
      }
    });

    test('pièces : suppression sans destination, appareils gardés sans pièce', () async {
      final backend = DemoBackend(latency: Duration.zero, liveSensors: false);
      final state = await signedIn(backend);
      final room = state.rooms.firstWhere((r) => state.devices.values.any((d) => d.roomId == r.id));
      final inside = [for (final d in state.devices.values) if (d.roomId == room.id) d.id];
      expect(await state.deleteRoom(room), isTrue);
      await state.refreshHome(silent: true);
      for (final id in inside) {
        expect(state.devices.containsKey(id), isTrue);
        expect(state.devices[id]!.roomId, isNull);
      }
    });
  });

  group('écrans', () {
    testWidgets('appui long : organisation, déplacement d\'une tuile, Terminer', (tester) async {
      final state = await pumpApp(tester);
      await signIn(tester);
      await tester.pumpAndSettle();
      final ids = state.ordered('favorites', state.visibleDevices.where((d) => d.isPinned).toList()).map((d) => d.id).toList();
      expect(find.byKey(const ValueKey('organize-bar')), findsNothing);

      // Un appui court ouvre la fiche, pas l'organisation.
      final gesture = await longPressDrag(tester, tileOf('Plafonnier'));
      expect(find.byKey(const ValueKey('organize-bar')), findsOneWidget);
      expect(find.text('Organisation des appareils'), findsOneWidget);
      await gesture.moveTo(tester.getCenter(tileOf('Prise café')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      final saved = state.layouts['favorites'];
      expect(saved, isNotNull);
      expect(saved!.indexOf(byName(state, 'Plafonnier').id), 1);
      expect(saved.first, byName(state, 'Prise café').id);
      expect(saved.toSet(), ids.toSet());

      await tester.tap(find.byKey(const ValueKey('organize-done')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('organize-bar')), findsNothing);
    });

    testWidgets('déposer une tuile sur une autre pièce', (tester) async {
      final state = await pumpApp(tester);
      await signIn(tester);
      await tester.pumpAndSettle();
      final lamp = byName(state, 'Plafonnier');
      final kitchen = state.rooms.firstWhere((r) => r.id != lamp.roomId);
      final gesture = await longPressDrag(tester, tileOf('Plafonnier'));
      final target = find.byKey(ValueKey('drop-room-${kitchen.id}'));
      expect(target, findsOneWidget);
      await gesture.moveTo(tester.getCenter(target));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.devices[lamp.id]!.roomId, kitchen.id);
      await tester.tap(find.byKey(const ValueKey('organize-done')));
      await tester.pumpAndSettle();
    });

    testWidgets('croix en mode organisation : confirmation puis retrait de la résidence', (tester) async {
      final state = await pumpApp(tester);
      await signIn(tester);
      await tester.pumpAndSettle();
      final plug = byName(state, 'Prise café');
      final gesture = await longPressDrag(tester, tileOf('Prise café'));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(ValueKey('remove-${plug.id}')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Voulez-vous vraiment supprimer cet appareil de votre installation SOLEA ?'), findsOneWidget);

      // Annuler : rien ne change.
      await tester.tap(find.byKey(const ValueKey('removal-cancel')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.devices.containsKey(plug.id), isTrue);

      // Depuis les favoris : retirer du favori seulement.
      await tester.tap(find.byKey(ValueKey('remove-${plug.id}')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('removal-favorite')));
      await tester.tap(find.byKey(const ValueKey('removal-confirm')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.devices[plug.id]!.isPinned, isFalse);
      expect(state.devices.containsKey(plug.id), isTrue);

      // Retirer de la résidence (croix d'une autre favorite).
      final lamp = byName(state, 'Plafonnier');
      await tester.tap(find.byKey(ValueKey('remove-${lamp.id}')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('removal-home')));
      await tester.tap(find.byKey(const ValueKey('removal-confirm')));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(state.devices.containsKey(lamp.id), isFalse);
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 500)); // messages de confirmation refermés
      }
      await tester.tap(find.byKey(const ValueKey('organize-done')));
      await tester.pumpAndSettle();
    });

    testWidgets('pièces : appui long, déplacement, puis suppression avec confirmation', (tester) async {
      final state = await pumpApp(tester);
      await signIn(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pièces').last);
      await tester.pumpAndSettle();
      final rooms = state.orderedRooms;
      final first = rooms[0];
      final second = rooms[1];
      Finder card(String name) => find.ancestor(of: find.text(name).first, matching: find.byType(RoomPhotoCard)).first;

      final gesture = await longPressDrag(tester, card(first.name));
      expect(find.text('Organisation des pièces'), findsOneWidget);
      await gesture.moveTo(tester.getCenter(card(second.name)));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.layouts['rooms']!.indexOf(first.id), 1);
      expect(state.orderedRooms.first.id, second.id);

      // Poubelle : confirmation, Annuler puis Supprimer en rangeant les appareils.
      final inside = [for (final d in state.devices.values) if (d.roomId == first.id) d.id];
      await tester.tap(find.byKey(ValueKey('remove-${first.id}')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Voulez-vous vraiment supprimer cette pièce de votre installation SOLEA ?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('room-remove-cancel')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.rooms.any((r) => r.id == first.id), isTrue);

      await tester.tap(find.byKey(ValueKey('remove-${first.id}')));
      await tester.pump(const Duration(milliseconds: 300));
      if (inside.isNotEmpty) {
        await tester.tap(find.byKey(const ValueKey('room-remove-target')));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.text(second.name).last);
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.tap(find.byKey(const ValueKey('room-remove-confirm')));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(state.rooms.any((r) => r.id == first.id), isFalse);
      for (final id in inside) {
        expect(state.devices[id]!.roomId, second.id);
      }
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.tap(find.byKey(const ValueKey('organize-done')));
      await tester.pumpAndSettle();
      expect(find.text('Organisation des pièces'), findsNothing);
    });

    Future<AppState> openFlow(WidgetTester tester, String raw) async {
      final state = await pumpApp(tester);
      await signIn(tester);
      await tester.pumpAndSettle();
      if (raw == 'SN2024A0012345') {
        final done = state.setDeviceIdentity(byName(state, 'Plafonnier').id, serialNumber: raw);
        await tester.pump(const Duration(milliseconds: 50));
        await done;
      }
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      nav.push(MaterialPageRoute<void>(builder: (_) => QrDeviceFlowScreen(recognition: const QrRecognizer().recognize(raw))));
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets('QR valide (lien Tuya) : marque prise en charge, connexion proposée', (tester) async {
      await openFlow(tester, 'https://smartapp.tuya.com/s/p?p=abc123&uuid=0123456789abcd&v=1.0');
      expect(find.byKey(const ValueKey('qrflow-support-supported')), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('qrflow-connect')), 300, scrollable: find.byType(Scrollable).last);
      expect(find.byKey(const ValueKey('qrflow-connect')), findsOneWidget);
      expect(find.text('Appareil connecté : la passerelle le joint.'), findsNothing, reason: 'jamais « connecté » sans connexion réelle');
    });

    testWidgets('QR non reconnu : ajout manuel et signalement à l\'administrateur', (tester) async {
      final state = await openFlow(tester, 'Bonjour tout le monde !');
      expect(find.text('QR code non reconnu'), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('qrflow-report')), 300, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.byKey(const ValueKey('qrflow-report')));
      await tester.pumpAndSettle();
      final scans = (state.backend as DemoBackend).qrScans;
      expect(scans, isNotEmpty);
      expect(scans.every((s) => s['reported_at'] != null || s['recognition_status'] == 'unknown'), isTrue);
      expect(scans.any((s) => s['reported_at'] != null), isTrue);
    });

    testWidgets('QR déjà enregistré : l\'appareil existant est signalé', (tester) async {
      final state = await openFlow(tester, 'SN2024A0012345');
      expect(find.byKey(const ValueKey('qrflow-duplicate')), findsOneWidget);
      expect(find.byKey(const ValueKey('qrflow-connect')), findsNothing);
      expect((state.backend as DemoBackend).qrScans.single['recognition_status'], 'duplicate');
    });

    testWidgets('QR d\'un appareil incompatible (Shelly) : pas de connexion annoncée', (tester) async {
      final state = await openFlow(tester, r'WIFI:T:WPA;S:shellyplus1-a8032ab12345;P:motdepasse;;');
      expect(find.byKey(const ValueKey('qrflow-support-homeAssistant')), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('qrflow-unsupported')), 300, scrollable: find.byType(Scrollable).last);
      expect(find.byKey(const ValueKey('qrflow-unsupported')), findsOneWidget);
      expect(find.byKey(const ValueKey('qrflow-connect')), findsNothing);
      expect(find.textContaining('motdepasse'), findsNothing, reason: 'mot de passe jamais affiché');
      expect((state.backend as DemoBackend).qrScans.single['raw_payload'], isNot(contains('motdepasse')));
    });
  });
}
