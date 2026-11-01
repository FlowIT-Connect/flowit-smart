import 'package:flowit_smart/core/home_modes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show pumpApp, signIn;

void main() {
  test('vacances : actives entre les dates, programmées avant', () {
    final now = DateTime(2026, 12, 1);
    final m = HomeModes(vacation: true, vacationFrom: DateTime(2026, 12, 20), vacationTo: DateTime(2027, 1, 3));
    expect(m.vacationActive(now), isFalse);
    expect(m.vacationScheduled(now), isTrue);
    expect(m.vacationActive(DateTime(2026, 12, 25)), isTrue);
    expect(const HomeModes(vacation: true).vacationActive(now), isTrue);
    final back = HomeModes.fromJson({'home_id': 'h', ...m.toJson()});
    expect(back.vacationTo, m.vacationTo);
  });

  testWidgets('accueil : Été puis Vacances avec simulation de présence', (tester) async {
    final state = await pumpApp(tester);
    await signIn(tester);
    await tester.pumpAndSettle();
    final scroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.byKey(const ValueKey('mode-summer')), 200, scrollable: scroll);
    await tester.tap(find.byKey(const ValueKey('mode-summer')));
    await tester.pumpAndSettle();
    expect(state.homeModes.season, 'summer');
    await tester.tap(find.byKey(const ValueKey('mode-winter')));
    await tester.pumpAndSettle();
    expect(state.homeModes.season, 'winter');

    await tester.tap(find.byKey(const ValueKey('mode-vacation')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vacation-switch')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('simulation-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('simulation-switch')));
    await tester.pumpAndSettle();
    final plafonnier = state.devices.values.firstWhere((d) => d.name == 'Plafonnier');
    await tester.ensureVisible(find.byKey(ValueKey('sim-${plafonnier.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('sim-${plafonnier.id}')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('vacation-save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vacation-save')));
    await tester.pumpAndSettle();
    expect(state.homeModes.vacationActive(), isTrue);
    expect(state.homeModes.simulationDevices, [plafonnier.id]);
    final saved = await tester.runAsync(() => state.backend.getHomeModes(state.home!.id));
    expect(saved!.presenceSimulation, isTrue);
    expect(saved.season, 'winter');
    expect(find.text('Vacances'), findsWidgets);
    await tester.pump(const Duration(seconds: 4));
  });
}
