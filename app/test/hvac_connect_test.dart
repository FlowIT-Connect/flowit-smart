import 'package:flowit_smart/core/hvac_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show pumpApp, signIn;

HvacBrand brand(String name) => hvacBrands.firstWhere((b) => b.name == name);

void main() {
  group('bibliothèque HVAC', () {
    test('noms uniques, chaque marque a au moins un type', () {
      final names = hvacBrands.map((b) => b.name).toList();
      expect(names.toSet().length, names.length);
      expect(hvacBrands.every((b) => b.types.isNotEmpty), isTrue);
      expect(brandsFor(HvacType.airConditioner).length, greaterThan(35));
      expect(brandsFor(HvacType.boiler).length, greaterThan(40));
    });

    test('marques distribuées en Algérie en tête, recherche', () {
      final list = brandsFor(HvacType.boiler);
      final firstOther = list.indexWhere((b) => !b.algeria);
      expect(list.take(firstOther).every((b) => b.algeria), isTrue);
      expect(brandsFor(HvacType.airConditioner, query: 'mitsu').map((b) => b.name), ['Mitsubishi Electric', 'Mitsubishi Heavy Industries']);
    });

    test('clim sans Wi-Fi : télécommande infrarouge, quelle que soit la marque', () {
      expect(routesFor(HvacType.airConditioner, brand('Condor'), hasWifi: false), [HvacRoute.infrared]);
      expect(routesFor(HvacType.airConditioner, null, hasWifi: false), [HvacRoute.infrared]);
    });

    test('clim Wi-Fi avec application connue : Home Assistant puis infrarouge, Modbus pour les gammes pro', () {
      expect(routesFor(HvacType.airConditioner, brand('Daikin'), hasWifi: true), [HvacRoute.homeAssistant, HvacRoute.infrared, HvacRoute.modbus]);
      expect(routesFor(HvacType.airConditioner, brand('Condor'), hasWifi: true).first, HvacRoute.tuyaWifi);
    });

    test('chaudière : jamais de coupure d\'alimentation, entrée thermostat toujours proposée', () {
      for (final b in brandsFor(HvacType.boiler)) {
        final routes = routesFor(HvacType.boiler, b, hasWifi: false);
        expect(routes, contains(HvacRoute.roomThermostat), reason: b.name);
        expect(routes, isNot(contains(HvacRoute.tuyaWifi)), reason: b.name);
      }
      expect(routesFor(HvacType.boiler, brand('Saunier Duval'), hasWifi: false), [HvacRoute.roomThermostat, HvacRoute.boilerBus]);
      expect(routesFor(HvacType.boiler, brand('Viessmann'), hasWifi: true).first, HvacRoute.homeAssistant);
    });
  });

  testWidgets('parcours : clim Gree sans Wi-Fi → infrarouge → test → commandes détectées', (tester) async {
    await pumpApp(tester);
    await signIn(tester);
    await tester.tap(find.text('Appareils').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter un appareil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter manuellement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Climatisation et chauffage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Climatiseur'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'gree');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gree'));
    await tester.pumpAndSettle();
    expect(find.text('Application de la marque : Gree+'), findsOneWidget);
    await tester.tap(find.text('Non, télécommande ou boutons seulement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Télécommande infrarouge Tuya'));
    await tester.pumpAndSettle();
    expect(find.textContaining('choisissez la marque Gree'), findsOneWidget);
    final test = find.text('Tester la connexion');
    await tester.scrollUntilVisible(test, 200, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Clim chambre');
    await tester.pumpAndSettle();
    await tester.tap(test);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Recherche de l\'appareil'), findsOneWidget);
    for (var i = 0; i < 12 && find.text('Commandes compatibles').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.text('Commandes compatibles'), findsOneWidget);
    expect(find.text('Clim chambre est prêt'), findsOneWidget);
    await tester.ensureVisible(find.text('Terminer'));
    await tester.tap(find.text('Terminer'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsWidgets, reason: 'retour à la liste des appareils');
  });
}
