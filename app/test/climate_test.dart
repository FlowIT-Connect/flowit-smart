import 'package:flowit_smart/core/climate.dart';
import 'package:flowit_smart/ui/screens/climate_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show pumpApp, signIn;

void main() {
  group('ambiances', () {
    test('programme : dernière plage commencée, y compris la veille', () {
      // 7 janvier 2030 = lundi.
      expect(scheduledPreset(defaultSchedule, DateTime(2030, 1, 7, 7)), 'comfort');
      expect(scheduledPreset(defaultSchedule, DateTime(2030, 1, 7, 12)), 'eco');
      expect(scheduledPreset(defaultSchedule, DateTime(2030, 1, 7, 23)), 'sleep');
      expect(scheduledPreset(defaultSchedule, DateTime(2030, 1, 8, 3)), 'sleep');
      expect(scheduledPreset(defaultSchedule, DateTime(2030, 1, 12, 7)), 'sleep', reason: 'samedi avant 8 h');
      expect(scheduledPreset(const [], DateTime(2030, 1, 7)), isNull);
    });

    test('priorités : pièce > maison > vacances > programme', () {
      final at = DateTime(2030, 1, 7, 12);
      const zone = ClimateZone(roomId: 'r');
      expect(effectivePreset(zone, ClimateSettings.initial, vacation: false, at: at), ('eco', 'schedule'));
      expect(effectivePreset(zone, ClimateSettings.initial, vacation: true, at: at), ('away', 'vacation'));
      const home = ClimateSettings(homePreset: 'comfort');
      expect(effectivePreset(zone, home, vacation: true, at: at), ('comfort', 'home'));
      final room = ClimateZone.fromJson({'room_id': 'r', 'schedule': [for (final e in defaultSchedule) e.toJson()], 'preset_override': 'sleep', 'override_until': '2030-01-07T11:00:00Z'});
      expect(effectivePreset(room, ClimateSettings.initial, vacation: false, at: at).$2, 'schedule', reason: 'dérogation expirée');
    });

    test('réglages : lecture tolérante et valeurs par défaut', () {
      final s = ClimateSettings.fromJson({'presets': {'comfort': {'heat': 22, 'cool': 25}}, 'home_preset': 'away'});
      expect(s.temps('comfort'), const PresetTemps(22, 25));
      expect(s.temps('frost'), const PresetTemps(7, null));
      expect(s.activeHomePreset(), 'away');
    });

    test('fenêtre ouverte : capteurs, délai et état lus et renvoyés', () {
      final z = ClimateZone.fromJson({'room_id': 'r', 'windows': ['w1'], 'window_delay': 5, 'active_window': true});
      expect(z.windows, ['w1']);
      expect(z.windowDelay, 5);
      expect(z.activeWindow, isTrue);
      final next = z.copyWith(windows: ['w1', 'w2'], windowDelay: 1);
      expect(next.toJson()['windows'], ['w1', 'w2']);
      expect(next.toJson()['window_delay'], 1);
      expect(next.toJson().containsKey('active_window'), isFalse, reason: 'écrit par la passerelle');
      expect(const ClimateZone(roomId: 'r').windowDelay, 2);
    });

    test('températures intelligentes : préchauffage et heure de retour', () {
      final s = ClimateSettings.fromJson({'preheat': false, 'preheat_max': 60});
      expect(s.preheat, isFalse);
      expect(s.preheatMax, 60);
      expect(ClimateSettings.fromJson(const {}).preheat, isTrue);
      expect(s.copyWith(preheat: true).toJson()['preheat_max'], 60);
      final now = DateTime(2030, 1, 7, 15, 30);
      expect(returnTime(const TimeOfDay(hour: 18, minute: 0), now), DateTime(2030, 1, 7, 18));
      expect(returnTime(const TimeOfDay(hour: 8, minute: 0), now), DateTime(2030, 1, 8, 8), reason: 'heure passée : demain');
    });
  });

  testWidgets('accueil : Je pars puis Je rentre', (tester) async {
    final state = await pumpApp(tester);
    await signIn(tester);
    await tester.pumpAndSettle();
    final leave = find.byKey(const ValueKey('climate-leave'));
    await tester.scrollUntilVisible(leave, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(leave);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Absence jusqu\'à mon retour'));
    await tester.pumpAndSettle();
    expect(state.climate.settings.activeHomePreset(), 'away');
    expect(state.climate.settings.homePresetUntil, isNull);
    final back = find.byKey(const ValueKey('climate-back'));
    await tester.ensureVisible(back);
    await tester.pumpAndSettle();
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(state.climate.settings.activeHomePreset(), isNull);
    expect(find.byKey(const ValueKey('climate-leave')), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('pièce : associer un capteur de fenêtre et choisir le délai', (tester) async {
    final state = await pumpApp(tester);
    await signIn(tester);
    await tester.pumpAndSettle();
    final zone = state.climate.zones.single;
    final porte = state.devices.values.firstWhere((d) => d.name == 'Porte d\'entrée');
    final nav = Navigator.of(tester.element(find.byType(Scaffold).first));
    nav.push(MaterialPageRoute(builder: (_) => ClimateZoneScreen(roomId: zone.roomId)));
    await tester.pumpAndSettle();
    final box = find.byKey(ValueKey('climate-window-${porte.id}'));
    await tester.scrollUntilVisible(box, 200, scrollable: find.byType(Scrollable).last);
    await tester.pumpAndSettle();
    await tester.tap(box);
    await tester.pumpAndSettle();
    final delay = find.byKey(const ValueKey('climate-window-delay-5'));
    await tester.ensureVisible(delay);
    await tester.pumpAndSettle();
    await tester.tap(delay);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Enregistrer'), 200, scrollable: find.byType(Scrollable).last);
    await tester.ensureVisible(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    final saved = state.climate.zones.single;
    expect(saved.windows, [porte.id]);
    expect(saved.windowDelay, 5);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('accueil : Absence pour toute la maison, puis réglage du salon', (tester) async {
    final state = await pumpApp(tester);
    await signIn(tester);
    await tester.pumpAndSettle();
    final away = find.byKey(const ValueKey('climate-home-away'));
    await tester.scrollUntilVisible(away, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(away);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pendant 2 heures'));
    await tester.pumpAndSettle();
    expect(state.climate.settings.activeHomePreset(), 'away');
    expect(find.text('Absence dans toute la maison'), findsOneWidget);

    await tester.tap(find.text('Chauffage et clim'));
    await tester.pumpAndSettle();
    expect(find.text('Salon'), findsOneWidget);
    await tester.tap(find.text('Salon'));
    await tester.pumpAndSettle();
    expect(find.text('Absence · choisi pour la maison'), findsOneWidget);
    expect(find.text('Thermostat'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Ajouter une plage'), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Ajouter une plage'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ajouter une plage'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Enregistrer'), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Enregistrer'));
    await tester.pump(const Duration(seconds: 6)); // le message « Absence activé » disparaît
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(state.climate.zones.single.schedule.length, defaultSchedule.length + 1);
    await tester.pump(const Duration(seconds: 4));
  });
}
