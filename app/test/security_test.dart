import 'package:flowit_smart/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show pumpApp, signIn;

Future<void> openSecurity(WidgetTester tester) async {
  await tester.tap(find.text('Paramètres').last);
  await tester.pumpAndSettle();
  final entry = find.text('Sécurité et vidéo');
  await tester.ensureVisible(entry);
  await tester.pumpAndSettle();
  await tester.tap(entry);
  await tester.pumpAndSettle();
}

void main() {
  group('Modèles vidéo', () {
    test('capacités : seules les fonctions vraies sont proposées', () {
      final caps = UdiCapabilities.fromJson({'video_stream': true, 'door_relay': false, 'audio_input': true, 'x': 'oui'});
      expect(caps.enabled, ['video_stream', 'audio_input']);
      expect(caps.has('door_relay'), isFalse);
      expect(UdiCapabilities.fromJson(null).enabled, isEmpty);
    });

    test('équipement : diagnostic, statut et test en cours', () {
      final s = VideoSource.fromJson({
        'id': 's1',
        'home_id': 'h1',
        'name': 'Portail',
        'category': 'intercom',
        'driver': 'onvif',
        'host': '192.168.1.20',
        'port': 80,
        'status': 'auth_error',
        'capabilities': {'video_stream': true},
        'diagnostic': {
          'steps': [
            {'step': 'connexion', 'ok': false, 'detail': 'Identifiants refusés'}
          ],
          'detected': {'relay_outputs': 1}
        },
        'test_requested_at': '2026-10-31T10:00:00Z',
        'diagnosed_at': '2026-10-31T10:00:05Z',
      });
      expect(s.status, VideoSourceStatus.authError);
      expect(s.isIntercom, isTrue);
      expect(s.steps.single.ok, isFalse);
      expect(s.detected['relay_outputs'], 1);
      expect(s.testing, isFalse);
      expect(s.address, '192.168.1.20:80');
    });

    test('appareil : vidéo fluide seulement si le boîtier l\'annonce', () {
      Device cam(Map<String, dynamic> meta) => Device.fromJson({
            'id': 'd1',
            'home_id': 'h1',
            'name': 'Entrée',
            'protocol': 'other',
            'connection_source': 'local',
            'availability': 'available',
            'state': {},
            'device_capabilities': [
              {'device_id': 'd1', 'capability_key': 'camera', 'type': 'string', 'writable': false, 'metadata': meta}
            ],
          });
      final live = cam({'kind': 'camera', 'live': 'webrtc', 'category': 'intercom', 'udi': {'video_stream': true, 'audio_input': true}});
      expect(live.hasLiveVideo, isTrue);
      expect(live.isIntercom, isTrue);
      expect(live.udi.microphone, isTrue);
      final stills = cam({'kind': 'camera'});
      expect(stills.hasLiveVideo, isFalse);
      expect(stills.udi.enabled, isEmpty);
    });

    test('boîtier : en ligne si signalé depuis moins de 3 minutes', () {
      expect(MediaGateway(relayOk: true, lastSeenAt: DateTime.now()).liveReady, isTrue);
      expect(MediaGateway(relayOk: true, lastSeenAt: DateTime.now().subtract(const Duration(minutes: 10))).online, isFalse);
      expect(const MediaGateway().online, isFalse);
    });
  });

  testWidgets('Sécurité et vidéo : vue générale, caméra et diagnostic', (tester) async {
    await pumpApp(tester);
    await signIn(tester);
    await openSecurity(tester);
    expect(find.text('Mes caméras'), findsOneWidget);
    expect(find.text('Caméra entrée'), findsOneWidget);
    expect(find.text('Images fixes'), findsOneWidget, reason: 'démo : pas de vidéo fluide annoncée');
    expect(find.text('Boîtier en ligne, relais vidéo arrêté'), findsOneWidget);
    await tester.tap(find.byTooltip('Diagnostic'));
    await tester.pumpAndSettle();
    expect(find.text('TP-Link · Tapo C200 · firmware 1.3.6'), findsWidgets);
    expect(find.text('Flux vidéo RTSP'), findsOneWidget);
    expect(find.text('Relancer le test'), findsOneWidget);
    await tester.ensureVisible(find.text('Relancer le test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Relancer le test'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('ajout : recherche sur le réseau, saisie et contrôles', (tester) async {
    await pumpApp(tester);
    await signIn(tester);
    await openSecurity(tester);
    await tester.tap(find.text('Ajouter un équipement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lancer la recherche'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Déjà ajouté'), findsOneWidget);
    await tester.ensureVisible(find.text('Visiophone démo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Visiophone démo'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '192.168.1.40'), findsOneWidget);

    // RTSP : identifiants dans l'adresse refusés.
    await tester.ensureVisible(find.text('RTSP'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RTSP'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(TextFormField, 'Adresse du flux RTSP'));
    await tester.enterText(find.widgetWithText(TextFormField, 'Adresse du flux RTSP'), 'rtsp://admin:1234@192.168.1.50/stream');
    await tester.ensureVisible(find.text('Ajouter et tester'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter et tester'));
    await tester.pumpAndSettle();
    expect(find.text('Mettez l\'identifiant et le mot de passe dans les champs dédiés'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Adresse du flux RTSP'), 'rtsp://192.168.1.50/stream');
    await tester.ensureVisible(find.text('Ajouter et tester'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter et tester'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    // Retour sur la fiche du nouvel équipement : la démo dit honnêtement qu'aucun appareil réel n'a été contacté.
    expect(find.text('Visiophone démo'), findsWidgets);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Démonstration : aucun boîtier vidéo réel'), findsWidgets);
  });
}
