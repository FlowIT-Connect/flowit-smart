import 'package:flowit_smart/core/home_summary.dart';
import 'package:flowit_smart/models/models.dart';
import 'package:flowit_smart/ui/widgets/home_summary_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show pumpApp, signIn;

Device dev(String id, Map<String, dynamic> state, List<List<dynamic>> caps, {String availability = 'available', String? room}) => Device.fromJson({
      'id': id,
      'home_id': 'h',
      'room_id': room,
      'name': id,
      'protocol': 'wifi',
      'connection_source': 'tuya',
      'availability': availability,
      'state': state,
      'device_capabilities': [
        for (final c in caps) {'device_id': id, 'capability_key': c[0], 'type': c[1], 'writable': c[2], 'metadata': <String, dynamic>{}},
      ],
    });

void main() {
  group('tableau récapitulatif', () {
    test('aucune valeur inventée quand il n\'y a pas de capteur', () {
      final s = HomeOverview.of([dev('lampe', {'switch': true}, [['switch', 'boolean', true]])]);
      expect(s.total, 1);
      expect(s.online, 1);
      expect(s.securityLevel, SummaryLevel.none);
      expect(s.indoorTemperature, isNull);
      expect(s.humidity, isNull);
      expect(s.climateState, 'off');
    });

    test('valeurs réelles, appareils hors ligne ignorés', () {
      final s = HomeOverview.of([
        dev('capteur salon', {'temperature': 22.0, 'humidity': 60}, [['temperature', 'sensor', false], ['humidity', 'sensor', false]], room: 'salon'),
        dev('capteur chambre', {'temperature': 20.0, 'humidity': 50}, [['temperature', 'sensor', false], ['humidity', 'sensor', false]], room: 'chambre'),
        dev('capteur HS', {'temperature': 40.0, 'humidity': 99}, [['temperature', 'sensor', false], ['humidity', 'sensor', false]], availability: 'unavailable'),
        dev('clim', {'target_temperature': 24.0, 'hvac_mode': 'cool', 'current_temperature': 27.0}, [['target_temperature', 'number', true], ['hvac_mode', 'enum', true]]),
      ]);
      expect(s.total, 4);
      expect(s.offline, 1);
      expect(s.homeLevel, SummaryLevel.warning);
      expect(s.indoorTemperature, closeTo(23, .01));
      expect(s.setpoint, 24);
      expect(s.climateState, 'cool');
      expect(s.humidity, 55);
      expect(s.humidityByRoom, {'salon': 60, 'chambre': 50});
    });

    test('sécurité : porte ouverte, serrure, danger', () {
      final porte = dev('porte', {'contact': false}, [['contact', 'sensor', false]]);
      final serrure = dev('serrure', {'lock': true}, [['lock', 'boolean', true]]);
      expect(HomeOverview.of([serrure]).securityLevel, SummaryLevel.ok);
      final s = HomeOverview.of([porte, serrure]);
      expect(s.securityDevices, 2);
      expect(s.openings, 1);
      expect(s.securityLevel, SummaryLevel.warning);
      final fumee = dev('fumée', {'smoke': true}, [['smoke', 'sensor', false]]);
      expect(HomeOverview.of([porte, fumee]).securityLevel, SummaryLevel.alert);
    });
  });

  testWidgets('accueil : 4 indicateurs, détail de l\'humidité par pièce', (tester) async {
    await pumpApp(tester);
    await signIn(tester);
    expect(find.byType(HomeSummaryPanel), findsOneWidget);
    for (final label in ['Maison connectée', 'Sécurité', 'Climatisation', 'Humidité']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('15 appareils'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('summary-humidity')));
    await tester.pumpAndSettle();
    expect(find.textContaining('%'), findsWidgets);
  });

  testWidgets('carte de pièce : appui long sur les lumières = tout allumer / éteindre', (tester) async {
    final state = await pumpApp(tester);
    await signIn(tester);
    await tester.tap(find.text('Pièces').last);
    await tester.pumpAndSettle();
    final lights = state.devicesInRoom(state.rooms.firstWhere((r) => r.name == 'Salon').id).where((d) => d.capability('brightness') != null).toList();
    expect(lights.any((d) => d.isOn == true), isTrue, reason: 'le plafonnier est allumé dans la démo');
    await tester.longPress(find.byKey(const ValueKey('group-Salon-light')));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    for (final l in lights) {
      final cur = state.devices[l.id]!;
      if (cur.isOnline) expect(cur.isOn, isFalse, reason: cur.name);
    }
    await tester.tap(find.byKey(const ValueKey('group-Salon-light')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Salon · Lumières'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
