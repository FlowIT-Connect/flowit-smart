import 'package:flowit_smart/models/models.dart';
import 'package:flowit_smart/ui/widgets/camera_history.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show pumpApp, signIn;

Future<void> openSecurity(WidgetTester tester) async {
  await tester.tap(find.text('Réglages').last);
  await tester.pumpAndSettle();
  final entry = find.text('Sécurité et vidéo');
  await tester.scrollUntilVisible(entry, 200, scrollable: find.byType(Scrollable).first);
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
            {'step': 'connexion', 'ok': false, 'detail': 'Identifiants refusés'},
          ],
          'detected': {'relay_outputs': 1},
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
          {'device_id': 'd1', 'capability_key': 'camera', 'type': 'string', 'writable': false, 'metadata': meta},
        ],
      });
      final live = cam({
        'kind': 'camera',
        'live': 'webrtc',
        'category': 'intercom',
        'udi': {'video_stream': true, 'audio_input': true},
      });
      expect(live.hasLiveVideo, isTrue);
      expect(live.isIntercom, isTrue);
      expect(live.udi.microphone, isTrue);
      final stills = cam({'kind': 'camera'});
      expect(stills.hasLiveVideo, isFalse);
      expect(stills.udi.enabled, isEmpty);
    });

    test('historique : carte mémoire annoncée par le boîtier, heures lisibles ou non', () {
      Device cam(Map<String, dynamic> meta) => Device.fromJson({
        'id': 'd1',
        'home_id': 'h1',
        'name': 'Salon',
        'protocol': 'other',
        'connection_source': 'local',
        'availability': 'available',
        'state': {},
        'device_capabilities': [
          {'device_id': 'd1', 'capability_key': 'camera', 'type': 'string', 'writable': false, 'metadata': meta},
        ],
      });
      expect(cam({'kind': 'camera', 'live': 'webrtc', 'playback': 'sd'}).hasPlayback, isTrue);
      expect(cam({'kind': 'camera', 'live': 'webrtc'}).hasPlayback, isFalse);
      expect(cam({'kind': 'camera', 'playback': 'sd'}).hasPlayback, isFalse, reason: 'pas de relais : pas de relecture');
      final q = RecordingQuery.fromJson({
        'id': 'q1',
        'status': 'done',
        'slots': [
          {'start': '2026-11-04T09:00:00Z', 'end': '2026-11-04T10:00:00Z', 'codec': 'H265'},
          {'start': '2026-11-04T13:00:00Z', 'end': '2026-11-04T14:00:00Z', 'codec': 'H264'},
        ],
      });
      expect(q.slots.map((s) => s.playable), [false, true]);
      expect(q.slots.first.start.isUtc, isFalse, reason: 'affiché à l\'heure du téléphone');
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

  testWidgets('historique : frise des heures enregistrées, relecture d\'une heure', (tester) async {
    await pumpApp(tester);
    await signIn(tester);
    final cam = Device.fromJson({
      'id': 'd-hist',
      'home_id': 'h1',
      'name': 'Salon',
      'protocol': 'other',
      'connection_source': 'local',
      'availability': 'available',
      'state': {},
      'device_capabilities': [
        {
          'device_id': 'd-hist',
          'capability_key': 'camera',
          'type': 'string',
          'writable': false,
          'metadata': {'kind': 'camera', 'live': 'webrtc', 'playback': 'sd'},
        },
      ],
    });
    DateTime? played;
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          body: SingleChildScrollView(
            child: CameraHistory(device: cam, onPlay: (t) => played = t),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Hier : toute la journée est passée, les passages de démonstration sont là.
    await tester.tap(find.byKey(const ValueKey('history-prev-day')));
    await tester.pumpAndSettle();
    expect(find.text('Hier'), findsOneWidget);
    String time() => tester.widget<Text>(find.byKey(const ValueKey('history-time'))).data!;
    expect(time(), '20:00:00', reason: 'la barre s\'ouvre sur le dernier enregistrement');
    // -30 s : lecture juste avant.
    await tester.tap(find.byIcon(Icons.replay_30_rounded));
    await tester.pumpAndSettle();
    expect([played?.hour, played?.minute, played?.second], [19, 59, 30]);
    // Glisser vers la droite remonte le temps ; lâcher lance la lecture.
    await tester.drag(find.byKey(const ValueKey('history-timeline')), const Offset(480, 0));
    await tester.pumpAndSettle();
    expect(played?.hour, 18);
    // Ancien format (H.265) : explication, pas de lecture.
    final before = played;
    await tester.drag(find.byKey(const ValueKey('history-timeline')), const Offset(2600, 0));
    await tester.pump();
    expect(played, before);
    expect(find.textContaining('H.265'), findsWidgets);
    await tester.pumpAndSettle();
    // Rien d'enregistré à cet endroit : on saute au passage suivant.
    await tester.drag(find.byKey(const ValueKey('history-timeline')), const Offset(-800, 0));
    await tester.pumpAndSettle();
    expect([played?.hour, played?.minute], [12, 0]);
  });

  testWidgets('caméra motorisée : boutons sous la vidéo, onglets Aperçu / Relecture, pavé de direction', (tester) async {
    await pumpApp(tester);
    await signIn(tester);
    final cam = Device.fromJson({
      'id': 'd-ptz',
      'home_id': 'h1',
      'name': 'Hero',
      'protocol': 'other',
      'connection_source': 'local',
      'availability': 'available',
      'state': {},
      'device_capabilities': [
        {
          'device_id': 'd-ptz',
          'capability_key': 'camera',
          'type': 'string',
          'writable': false,
          'metadata': {
            'kind': 'camera',
            'live': 'webrtc',
            'playback': 'sd',
            'udi': {'video_stream': true, 'snapshot': true, 'audio_input': true, 'audio_output': true, 'ptz_control': true},
          },
        },
      ],
    });
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute(builder: (_) => Scaffold(body: SingleChildScrollView(child: CameraVideoPanel(device: cam)))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    for (final k in ['video-sound', 'video-talk', 'video-quality', 'video-fullscreen', 'ptz-pad', 'ptz-preset']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
    }
    expect(find.text('Aperçu'), findsOneWidget);
    // Appui maintenu sur une flèche : la caméra tourne ; doigt levé : elle s'arrête.
    final g = await tester.startGesture(tester.getCenter(find.byIcon(Icons.arrow_left_rounded)));
    await tester.pump(const Duration(milliseconds: 800));
    await g.up();
    await tester.pump();
    await tester.tap(find.text('Relecture'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('ptz-pad')), findsNothing, reason: 'le pavé laisse la place à la barre du temps');
    expect(find.byKey(const ValueKey('history-timeline')), findsOneWidget);
    await tester.tap(find.text('Aperçu'));
    await tester.pump(const Duration(seconds: 1));
    nav.pop();
    await tester.pumpAndSettle();
  });

  testWidgets('ajout simple : caméra Dahua trouvée sur le réseau, code de sécurité, sans adresse à taper', (tester) async {
    await pumpApp(tester);
    await signIn(tester);
    await openSecurity(tester);
    await tester.tap(find.text('Ajouter un équipement'));
    await tester.pumpAndSettle();
    expect(find.text('Scanner le QR code'), findsOneWidget);
    await tester.ensureVisible(find.text('Lancer la recherche'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lancer la recherche'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Caméra Dahua démo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Caméra Dahua démo'));
    await tester.pumpAndSettle();
    // Le panneau QR est rempli : modèle, numéro de série, adresse trouvée ; il ne manque que le code.
    expect(find.text('9K00AB1CDEF2345'), findsOneWidget);
    expect(find.text('Dahua DH-H5A'), findsOneWidget);
    await tester.tap(find.text('Ajouter et tester').first);
    await tester.pumpAndSettle();
    expect(find.text('Donnez un nom et le code de sécurité.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Code de sécurité'), 'TEST1234');
    await tester.tap(find.text('Ajouter et tester').first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.textContaining('9K00AB1CDEF2345'), findsWidgets);
    expect(find.text('Dahua (QR code)'), findsOneWidget);
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
