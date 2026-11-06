import 'package:flowit_smart/models/models.dart';
import 'package:flowit_smart/ui/screens/automations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show pumpApp, signIn;

Future<void> openAutomations(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.schedule_outlined).last);
  await tester.pumpAndSettle();
}

void main() {
  test('automatisation : SAUF SI, PUIS et priorité relus ; base ancienne ménagée', () {
    final a = Automation.fromJson({
      'id': 'a',
      'home_id': 'h',
      'name': 'Vent',
      'trigger': {'type': 'weather', 'metric': 'wind_speed', 'op': 'gt', 'value': 80},
      'actions': [
        {'device_id': 'v', 'capability_key': 'cover_position', 'value': 0},
      ],
      'exceptions': [
        {'type': 'sun', 'is': 'night'},
      ],
      'follow_up': {'after_minutes': 30, 'actions': [], 'conditions': []},
      'priority': 'security',
    });
    expect(a.exceptions, hasLength(1));
    expect(a.followUp!['after_minutes'], 30);
    expect(a.priority, 'security');
    final simple = Automation(id: 'b', homeId: 'h', name: 'x', trigger: const {'type': 'manual'}, actions: const [{}]);
    expect(simple.toJson().containsKey('follow_up'), isFalse, reason: 'colonnes de la phase 5 absentes si inutiles');
    expect(simple.toJson(includeAdvanced: true)['exceptions'], isEmpty);
  });

  testWidgets('carte : déclencheur météo, PUIS, règle de sécurité et historique', (tester) async {
    final state = await pumpApp(tester);
    await signIn(tester);
    await openAutomations(tester);
    final list = find.descendant(of: find.byType(AutomationsScreen), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('Vents forts : fermer les volets'), 200, scrollable: list);
    expect(find.text('Quand Vent > 80 km/h pendant 2 min'), findsOneWidget);
    expect(find.textContaining('puis après 30 min'), findsOneWidget);
    expect(find.byIcon(Icons.shield_rounded), findsOneWidget);
    final wind = state.automations.firstWhere((a) => a.trigger['type'] == 'weather');
    final history = find.byKey(ValueKey('automation-history-${wind.id}'));
    await tester.scrollUntilVisible(history, 200, scrollable: list);
    await tester.drag(list, const Offset(0, -250));
    await tester.pumpAndSettle();
    await tester.tap(history);
    await tester.pumpAndSettle();
    expect(find.textContaining('Exécutée'), findsWidgets);
    expect(find.textContaining('Vent 86 km/h'), findsOneWidget);
    expect(find.textContaining('SAUF SI'), findsOneWidget);
  });

  testWidgets('éditeur : modèle « Vents forts » prérempli, réenregistrement sans perte du PUIS', (tester) async {
    final state = await pumpApp(tester);
    await signIn(tester);
    await openAutomations(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('template-wind')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Vents forts : fermer les volets'), findsOneWidget);
    expect(find.text('Délai de confirmation'), findsOneWidget);
    final editor = find.descendant(of: find.byType(AutomationEditor), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byKey(const ValueKey('follow-switch')), 300, scrollable: editor);
    final follow = tester.widget<SwitchListTile>(find.byKey(const ValueKey('follow-switch')));
    expect(follow.value, isTrue);
    Navigator.of(tester.element(find.byType(AutomationEditor))).pop();
    await tester.pumpAndSettle();

    final wind = state.automations.firstWhere((a) => a.trigger['type'] == 'weather');
    await tester.runAsync(() async {
      await state.backend.saveAutomation(wind);
    });
    await tester.pumpWidget(const SizedBox());
    final list = await tester.runAsync(() => state.backend.listAutomations(state.home!.id));
    final saved = list!.firstWhere((a) => a.id == wind.id);
    expect(saved.followUp!['conditions'], isNotEmpty);
    expect(saved.priority, 'security');
  });

  testWidgets('éditeur : modèle « Forte chaleur » : clim en froid, choisie d\'office', (tester) async {
    await pumpApp(tester);
    await signIn(tester);
    await openAutomations(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('template-heat')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Forte chaleur : allumer la clim'), findsOneWidget);
    final editor = find.descendant(of: find.byType(AutomationEditor), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byKey(const ValueKey('follow-switch')), 300, scrollable: editor);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('follow-switch'))).value, isTrue);
    expect(find.text('Climatiseur salon'), findsWidgets, reason: 'la clim de la maison est déjà choisie');
  });
}
