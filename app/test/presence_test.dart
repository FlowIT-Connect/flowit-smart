import 'package:flowit_smart/core/presence.dart';
import 'package:flowit_smart/models/models.dart';
import 'package:flowit_smart/ui/screens/automations_screen.dart';
import 'package:flowit_smart/ui/screens/device_detail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show pumpApp, signIn;

EventLog ev(int min, String result) =>
    EventLog(id: min, eventType: 'presence', result: result, createdAt: DateTime(2026, 11, 5).add(Duration(minutes: min)));

void main() {
  final from = DateTime(2026, 11, 5);
  final now = from.add(const Duration(hours: 12));

  test('journée : passages, durée totale, présence en cours', () {
    final day = presenceDay([ev(60, 'detected'), ev(90, 'clear'), ev(600, 'detected')], presentNow: true, from: from, now: now);
    expect(day.arrivals, 2);
    expect(day.segments.length, 2);
    expect(day.total, const Duration(minutes: 30 + 120));
    expect(day.lastChange, from.add(const Duration(minutes: 600)));
    expect(day.lastArrival, from.add(const Duration(minutes: 600)));
  });

  test('présence depuis la veille : la journée commence occupée', () {
    final day = presenceDay([ev(30, 'clear')], presentNow: false, from: from, now: now);
    expect(day.arrivals, 0);
    expect(day.total, const Duration(minutes: 30));
  });

  test('aucun passage : état actuel, doublons ignorés', () {
    expect(presenceDay(const [], presentNow: false, from: from, now: now).total, Duration.zero);
    expect(presenceDay(const [], presentNow: true, from: from, now: now).total, const Duration(hours: 12));
    final dup = presenceDay([ev(60, 'detected'), ev(61, 'detected'), ev(70, 'clear')], presentNow: false, from: from, now: now);
    expect(dup.arrivals, 1);
    expect(dup.total, const Duration(minutes: 10));
  });

  testWidgets('fiche du détecteur : carte de présence, frise et automatisation en 1 clic', (tester) async {
    final state = await pumpApp(tester);
    await signIn(tester);
    final sensor = state.devices.values.firstWhere((d) => d.name == 'Détecteur couloir');
    showDeviceDetail(tester.element(find.byType(Scaffold).first), sensor.id);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('presence-card')), findsOneWidget);
    expect(find.text('Personne'), findsOneWidget);
    expect(find.text('Aujourd\'hui'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('presence-automation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('presence-automation')));
    await tester.pumpAndSettle();
    expect(find.byType(AutomationEditor), findsOneWidget);
    expect(find.text('Détecteur couloir'), findsWidgets); // déclencheur déjà choisi
  });
}
