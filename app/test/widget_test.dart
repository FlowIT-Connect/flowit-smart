import 'package:flowit_smart/core/location.dart';
import 'package:flowit_smart/app.dart';
import 'package:flowit_smart/data/demo_backend.dart';
import 'package:flowit_smart/state/app_state.dart';
import 'package:flowit_smart/ui/screens/add_device_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowit_smart/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> pumpApp(WidgetTester tester, {Locale locale = const Locale('fr'), Size size = const Size(400, 860), LocationService location = const NoLocation()}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = AppState(DemoBackend(latency: Duration.zero, confirmDelay: const Duration(milliseconds: 300), liveSensors: false), initialLocale: locale, location: location);
  await tester.pumpWidget(FlowItApp(state: state));
  await tester.pumpAndSettle();
  return state;
}

Future<void> signIn(WidgetTester tester) async {
  await tester.tap(find.byType(FilledButton).first);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('connexion démo puis accueil', (tester) async {
    await pumpApp(tester);
    expect(find.text('Se connecter'), findsOneWidget);
    await signIn(tester);
    expect(find.text('Favoris'), findsOneWidget);
    expect(find.text('Plafonnier'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Ampoule chevet'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Ampoule chevet'), findsOneWidget, reason: 'section À vérifier');
  });

  testWidgets('bascule d\'une prise : attente puis confirmation', (tester) async {
    final state = await pumpApp(tester);
    await signIn(tester);
    final tile = find.ancestor(of: find.text('Prise café'), matching: find.byType(Card));
    final sw = find.descendant(of: tile, matching: find.byType(Switch));
    expect(tester.widget<Switch>(sw).value, isFalse);
    await tester.tap(sw);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.descendant(of: tile, matching: find.byType(CircularProgressIndicator)), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<Switch>(sw).value, isTrue);
    expect(state.devices.values.firstWhere((d) => d.name == 'Prise café').isOn, isTrue);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('fiche appareil : capacités réelles, appareil sensible bloqué', (tester) async {
    await pumpApp(tester);
    await signIn(tester);
    await tester.tap(find.text('Appareils').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'serrure');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Serrure'));
    await tester.pumpAndSettle();
    expect(find.textContaining('commande à distance bloquée'), findsOneWidget);
    expect(find.text('Verrou'), findsNothing);
  });

  testWidgets('fiche climatiseur : mode, ventilation, oscillation, mode nuit', (tester) async {
    final state = await pumpApp(tester);
    await signIn(tester);
    await tester.tap(find.text('Appareils').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'climatiseur');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Climatiseur salon'));
    await tester.pumpAndSettle();
    expect(find.text('Climatisation'), findsWidgets);
    expect(find.text('Moyenne'), findsOneWidget);
    await tester.ensureVisible(find.text('Moyenne'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Moyenne'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(state.devices.values.firstWhere((d) => d.name == 'Climatiseur salon').state['fan_mode'], 'medium');
    expect(find.text('Oscillation'), findsOneWidget);
    expect(find.text('Mode nuit'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('boîtier TTLock : activation par le propriétaire puis code d\'accès', (tester) async {
    await pumpApp(tester);
    await signIn(tester);
    await tester.tap(find.text('Appareils').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'boîtier');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Boîtier d\'accès'));
    await tester.pumpAndSettle();
    expect(find.text('Fonctions de sécurité bloquées'), findsOneWidget);
    expect(find.text('Créer un code'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Activer le contrôle d\'accès'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Activer le contrôle d\'accès').last);
    await tester.pumpAndSettle();
    expect(find.text('Fonctions de sécurité bloquées'), findsNothing);
    await tester.ensureVisible(find.text('Créer un code'));
    await tester.tap(find.text('Créer un code'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Créer le code'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Code créé'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Fermer'));
    await tester.pumpAndSettle();

    // Accès partagé : désactiver puis réactiver la clé de Karim
    await tester.ensureVisible(find.text('Karim'));
    final menu = find.descendant(of: find.widgetWithText(ListTile, 'Karim'), matching: find.byType(PopupMenuButton<String>));
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Désactiver').last);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.textContaining('Désactivé'), findsOneWidget);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Réactiver').last);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.textContaining('Actif'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('rideau : boutons Ouvrir / Stop / Fermer', (tester) async {
    final state = await pumpApp(tester);
    await signIn(tester);
    await tester.tap(find.text('Appareils').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'volet');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volet salon'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'Ouvrir'), findsOneWidget, reason: 'pas de doublon avec le curseur');
    expect(find.widgetWithText(FilledButton, 'Stop'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Fermer'));
    await tester.pump(const Duration(milliseconds: 400));
    final volet = state.devices.values.firstWhere((d) => d.name == 'Volet salon');
    expect(volet.state['cover_control'], 'close');
    expect(volet.state['cover_position'], 0);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('robot aspirateur : Nettoyer puis Pause, retour à la base, puissance', (tester) async {
    final state = await pumpApp(tester);
    await signIn(tester);
    await tester.tap(find.text('Appareils').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'robot');
    await tester.pumpAndSettle();
    expect(find.textContaining('En charge · 92 %'), findsOneWidget, reason: 'état et batterie sur la tuile');
    await tester.tap(find.text('Robot aspirateur'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'Base'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Arrêter'), findsNothing, reason: 'rien à arrêter à la base');
    await tester.tap(find.widgetWithText(FilledButton, 'Nettoyer'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    Device robot() => state.devices.values.firstWhere((d) => d.name == 'Robot aspirateur');
    expect(robot().state['vacuum_state'], 'cleaning');
    expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Arrêter'), findsOneWidget);
    expect(find.text('Nettoyage'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Base'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(robot().state['vacuum_state'], 'returning');
    await tester.scrollUntilVisible(find.text('Maximum').first, 200, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maximum').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(robot().state['suction'], 'max');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('robot aspirateur : carte, pièces choisies puis zone dessinée', (tester) async {
    final state = await pumpApp(tester);
    await signIn(tester);
    await tester.tap(find.text('Appareils').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'robot');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Robot aspirateur'));
    await tester.pumpAndSettle();
    expect(find.text('Nettoyage intelligent'), findsOneWidget);
    final map = find.byKey(const ValueKey('vacuum-map'));
    await tester.scrollUntilVisible(find.text('Choisis une pièce'), 200, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null && w.painter.runtimeType.toString() == '_MapPainter'), findsOneWidget);
    expect(find.text('Salon'), findsNothing, reason: 'nom dessiné sur la carte, pas un widget texte');
    await tester.ensureVisible(map);
    await tester.pumpAndSettle();
    // Centre de la carte : le salon.
    await tester.tap(map);
    await tester.pumpAndSettle();
    expect(find.text('Nettoyer 1 pièce'), findsOneWidget);
    await tester.tap(find.text('2 fois'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nettoyer 1 pièce'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    Device robot() => state.devices.values.firstWhere((d) => d.name == 'Robot aspirateur');
    expect(robot().state['vacuum_state'], 'cleaning');
    expect(state.pendingFor(robot().id, 'vacuum_clean')?.value, {'mode': 'rooms', 'rooms': ['0'], 'passes': 2});
    await tester.pumpAndSettle();
    // Zone : trop petite d'abord, puis assez grande.
    // (le haut de la fiche couvre le sélecteur une fois la carte défilée : on le choisit directement)
    tester.widget<SegmentedButton<String>>(find.byType(SegmentedButton<String>)).onSelectionChanged!({'zone'});
    await tester.pumpAndSettle();
    expect(find.text('Dessine une zone'), findsOneWidget);
    await tester.ensureVisible(map);
    await tester.pumpAndSettle();
    final c = tester.getCenter(map);
    await tester.dragFrom(c, const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('Dessine une zone'), findsOneWidget, reason: 'zone de quelques centimètres refusée');
    await tester.dragFrom(c - const Offset(60, 40), const Offset(120, 80));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nettoyer la zone'));
    await tester.pump(const Duration(milliseconds: 400));
    final zone = state.pendingFor(robot().id, 'vacuum_clean')!.value as Map;
    expect(zone['mode'], 'zone');
    expect((zone['zone'] as List).length, 4);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('robot aspirateur : plan du logement seul, cadré sur la carte, pièces choisies dessous', (tester) async {
    final state = await pumpApp(tester);
    await signIn(tester);
    final robot = state.devices.values.firstWhere((d) => d.name == 'Robot aspirateur');
    // Comme le yeedi de Baziz : un seul contour (le logement) pour 5 pièces, robot loin du plan.
    state.devices = Map.of(state.devices)
      ..[robot.id] = robot.copyWith(state: {
        ...robot.state,
        'vacuum_map': {
          'rooms': [
            {'id': '0', 'name': 'A', 'pts': [[0, 0], [6000, 0], [6000, 4000], [0, 4000]]},
            for (final id in ['1', '2', '3', '4']) {'id': id, 'name': String.fromCharCode(65 + int.parse(id)), 'pts': []},
          ],
          'bot': [-40000, -40000],
          'charger': [-40000, -39800],
        },
      });
    await tester.tap(find.text('Appareils').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'robot');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Robot aspirateur'));
    await tester.pumpAndSettle();
    final chips = find.byKey(const ValueKey('vacuum-room-2'));
    await tester.scrollUntilVisible(chips, 200, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    for (final id in ['0', '1', '2', '3', '4']) {
      expect(find.byKey(ValueKey('vacuum-room-$id')), findsOneWidget, reason: 'les 5 pièces se choisissent sous la carte');
    }
    expect(find.byType(SegmentedButton<String>), findsNothing, reason: 'pas de zone tant que le plan est approximatif');
    final painter = tester.widget<CustomPaint>(
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null && w.painter.runtimeType.toString() == '_MapPainter'),
    );
    final mapBox = tester.getSize(find.byKey(const ValueKey('vacuum-map')));
    // Plan de 6 m × 4 m (+ marges) qui remplit le cadre : bien plus que quelques pixels.
    expect(mapBox.width, greaterThan(250));
    expect(painter.painter, isNotNull);
    await tester.tap(chips);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nettoyer 1 pièce'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(state.pendingFor(robot.id, 'vacuum_clean')?.value, {'mode': 'rooms', 'rooms': ['2'], 'passes': 1});
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('arabe : interface de droite à gauche sans débordement', (tester) async {
    await pumpApp(tester, locale: const Locale('ar'));
    await signIn(tester);
    final dir = Directionality.of(tester.element(find.byType(NavigationBar)));
    expect(dir, TextDirection.rtl);
    expect(find.text('المفضلة'), findsOneWidget);
    for (final label in ['الغرف', 'الأجهزة', 'المشاهد', 'الأتمتة', 'الإعدادات']) {
      await tester.tap(find.byTooltip(label).first);
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('grand écran : rail de navigation, toutes les pages', (tester) async {
    await pumpApp(tester, size: const Size(1280, 800));
    await signIn(tester);
    expect(find.byType(NavigationRail), findsOneWidget);
    for (final label in ['Pièces', 'Appareils', 'Scènes', 'Automatisations', 'Paramètres', 'Accueil']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('ajout d\'un appareil Smart Life depuis l\'onglet Appareils', (tester) async {
    await pumpApp(tester);
    await signIn(tester);
    await tester.tap(find.text('Appareils').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un appareil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter manuellement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appareil Smart Life (Tuya)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Prise bureau');
    // Les tests tournent comme sur Android : bouton d'ouverture de Smart Life.
    final added = find.text('Ouvrir Smart Life');
    await tester.drag(find.byType(ListView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(added);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Recherche du nouvel appareil'), findsOneWidget);
    for (var i = 0; i < 12 && find.text('Prise bureau est prêt').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('Prise bureau est prêt'), findsOneWidget);
    await tester.ensureVisible(find.text('Terminer'));
    await tester.tap(find.text('Terminer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'bureau');
    await tester.pumpAndSettle();
    expect(find.text('Prise bureau'), findsOneWidget);
  });

  testWidgets('serrure : sur le web, renvoi vers l\'app Android', (tester) async {
    await pumpApp(tester);
    await signIn(tester);
    await tester.tap(find.text('Appareils').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un appareil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter manuellement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Serrure TTLock'));
    await tester.pumpAndSettle();
    expect(find.textContaining('app Android Solea'), findsOneWidget);
    expect(find.text('Rechercher la serrure'), findsNothing);
  });

  testWidgets('logement plein : ajout bloqué, demande de déblocage, page Paiements de l\'exploitant', (tester) async {
    final state = await pumpApp(tester);
    await signIn(tester);
    (state.backend as DemoBackend).setDeviceLimit(state.home!.id, state.devices.length);
    await tester.tap(find.text('Appareils').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un appareil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter manuellement'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Appareils : ${state.devices.length} / ${state.devices.length}'), findsOneWidget);
    await tester.tap(find.text('Appareil Smart Life (Tuya)'));
    await tester.pumpAndSettle();
    expect(find.text('Ouvrir Smart Life'), findsNothing, reason: 'choix désactivé quand le logement est plein');
    await tester.tap(find.text("Débloquer plus d'appareils"));
    await tester.pumpAndSettle();
    expect(find.textContaining('dès confirmation du paiement'), findsOneWidget);
    Navigator.of(tester.element(find.byType(AddDeviceScreen))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Réglages').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Paiements'), 200, scrollable: find.byType(Scrollable).last);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paiements'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paiement reçu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer le paiement'));
    await tester.pumpAndSettle();
    expect(find.text('Payé'), findsOneWidget);
    expect(state.plan!.deviceLimit, 20);
    expect(state.plan!.isFull, isFalse);
  });

  testWidgets('exploitant : appareil du compte installateur rangé dans un logement', (tester) async {
    final state = await pumpApp(tester);
    await signIn(tester);
    await tester.tap(find.text('Réglages').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Appareils à attribuer'), 200, scrollable: find.byType(Scrollable).last);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appareils à attribuer'));
    await tester.pumpAndSettle();
    expect(find.text('À attribuer (2)'), findsOneWidget);
    await tester.tap(find.text('Attribuer').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(state.home!.name).last);
    await tester.pumpAndSettle();
    expect(find.text('À attribuer (1)'), findsOneWidget);
    expect(find.text('Attribués (1)'), findsOneWidget);
  });
}
