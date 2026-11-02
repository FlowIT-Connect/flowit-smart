import 'package:flowit_smart/core/notifications.dart';
import 'package:flowit_smart/data/demo_backend.dart';
import 'package:flowit_smart/ui/screens/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show pumpApp, signIn;

void main() {
  group('notifications', () {
    test('12 types, catégories et priorités cohérentes', () {
      expect(NotificationKind.all, hasLength(12));
      for (final k in NotificationKind.all) {
        expect(notificationCategories, contains(k.category), reason: k.type);
        expect(notificationPriorities, contains(k.priority), reason: k.type);
      }
      expect(NotificationKind.of('smoke').priority, 'critical');
    });

    test('réglages relus et bornés', () {
      final s = NotificationSettings.fromJson({'off': ['motion', 'inconnu'], 'temp_max': 99, 'temp_min': -50});
      expect(s.off, {'motion'});
      expect(s.enabled('motion'), isFalse);
      expect(s.tempMax, 60);
      expect(s.tempMin, -20);
      final t = s.toggle('motion', true).toggle('door_closed', false);
      expect(NotificationSettings.fromJson(t.toJson()).off, {'door_closed'});
    });
  });

  testWidgets('centre de notifications : non lues, filtre, tout lire, temps réel', (tester) async {
    final state = await pumpApp(tester);
    await signIn(tester);
    await tester.pumpAndSettle();
    expect(state.unreadNotifications, 3);
    final bell = find.byKey(const ValueKey('notification-bell'));
    expect(find.descendant(of: bell, matching: find.text('3')), findsOneWidget);

    await tester.tap(bell);
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(find.text('Porte ouverte'), findsOneWidget);
    expect(find.text('Porte d\'entrée · Entrée'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('notif-filter-climate')));
    await tester.pumpAndSettle();
    expect(find.text('Porte ouverte'), findsNothing);
    expect(find.text('Vents forts détectés'), findsOneWidget);
    expect(find.text('Vent 86 km/h · rafales 102 km/h'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('notif-filter-all')));
    await tester.tap(find.byKey(const ValueKey('notif-tab-unread')));
    await tester.pumpAndSettle();
    expect(find.text('Mouvement détecté'), findsOneWidget);
    expect(find.text('Appareil déconnecté'), findsNothing, reason: 'déjà lue');

    await tester.tap(find.byKey(const ValueKey('notif-read-all')));
    await tester.pumpAndSettle();
    expect(state.unreadNotifications, 0);
    expect(find.text('Tout est lu'), findsOneWidget);

    // Nouvelle alerte poussée par le serveur.
    (state.backend as DemoBackend).demoNotify(state.home!.id, 'smoke', 'Détecteur cuisine · Cuisine', data: {'device': 'Détecteur cuisine', 'room': 'Cuisine'});
    await tester.pumpAndSettle();
    expect(state.unreadNotifications, 1);
    expect(find.text('Fumée détectée'), findsWidgets);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('réglages : couper un type est enregistré dans le profil', (tester) async {
    final state = await pumpApp(tester);
    await signIn(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notification-bell')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notif-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('notif-switch-motion')));
    await tester.pumpAndSettle();
    expect(state.notificationSettings.enabled('motion'), isFalse);
    final prefs = await tester.runAsync(() => state.backend.getPreferences());
    expect((prefs!['notifications'] as Map)['off'], ['motion']);
  });
}
