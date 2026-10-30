import 'package:flowit_smart/app.dart';
import 'package:flowit_smart/data/demo_backend.dart';
import 'package:flowit_smart/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> pumpApp(WidgetTester tester, {Locale locale = const Locale('fr'), Size size = const Size(400, 860)}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = AppState(DemoBackend(latency: Duration.zero, confirmDelay: const Duration(milliseconds: 300), liveSensors: false), initialLocale: locale);
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
}
