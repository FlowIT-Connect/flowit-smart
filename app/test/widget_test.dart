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
    await tester.tap(find.text('Serrure'));
    await tester.pumpAndSettle();
    expect(find.textContaining('commande à distance bloquée'), findsOneWidget);
    expect(find.text('Verrou'), findsNothing);
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
