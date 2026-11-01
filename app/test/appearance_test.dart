import 'package:flowit_smart/core/appearance.dart';
import 'package:flowit_smart/core/theme.dart';
import 'package:flowit_smart/ui/screens/appearance_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show pumpApp, signIn;

void main() {
  tearDown(() => AppearanceController.instance.value = Appearance.defaults);

  group('apparence', () {
    test('valeurs bornées et relues depuis le profil', () {
      final a = Appearance.fromJson({'theme': 'inconnu', 'blur': 99, 'brightness': -3, 'glass_opacity': 5, 'background': 'http://x'});
      expect(a.theme, 'solea');
      expect(a.blur, 40);
      expect(a.brightness, -.6);
      expect(a.glassOpacity, 1.8);
      expect(a.background, isNull);
      final b = Appearance.defaults.copyWith(theme: 'green_glass', background: 'lib:nature_2', accent: const Color(0xFF60A5FA));
      expect(Appearance.fromJson(b.toJson()), b);
      expect(b.libraryKey, 'nature_2');
    });

    test('7 thèmes + Solea, couleurs cohérentes', () {
      expect(appThemes, hasLength(8));
      expect(const Appearance(theme: 'light_glass').forcedMode, ThemeMode.light);
      expect(const Appearance(theme: 'premium_black').forcedMode, ThemeMode.dark);
      expect(Appearance.defaults.forcedMode, isNull);
      expect(Appearance.defaults.colors(Brightness.dark), same(FlowColors.dark));
      expect(const Appearance(theme: 'green_glass').colors(Brightness.dark).brand, const Color(0xFF34D399));
      expect(const Appearance(theme: 'custom', accent: Color(0xFFF472B6)).colors(Brightness.dark).brand, const Color(0xFFF472B6));
      // Transparence des cartes : verre plus couvrant.
      final opaque = const Appearance(glassOpacity: 1.5).colors(Brightness.dark);
      expect(opaque.glass.a, greaterThan(FlowColors.dark.glass.a));
    });
  });

  testWidgets('écran Apparence : thème et fond enregistrés dans le profil', (tester) async {
    final state = await pumpApp(tester);
    await signIn(tester);
    await tester.tap(find.text('Paramètres').last);
    await tester.pumpAndSettle();
    final settings = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.byKey(const ValueKey('open-appearance')), 200, scrollable: settings);
    await tester.tap(find.byKey(const ValueKey('open-appearance')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('appearance-preview')), findsOneWidget);

    final lists = find.descendant(of: find.byType(AppearanceScreen), matching: find.byType(ListView));
    await tester.dragUntilVisible(find.byKey(const ValueKey('theme-blue_glass')), lists.at(1), const Offset(-120, 0), maxIteration: 10);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theme-blue_glass')));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(find.byKey(const ValueKey('bg-nature_2')), lists.first, const Offset(0, -200), maxIteration: 15);
    await tester.tap(find.byKey(const ValueKey('bg-nature_2')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await tester.pumpAndSettle();

    expect(find.byType(AppearanceScreen), findsNothing);
    final look = AppearanceController.instance.value;
    expect(look.theme, 'blue_glass');
    expect(look.background, 'lib:nature_2');
    final saved = await tester.runAsync(() => state.backend.getPreferences());
    expect((saved!['appearance'] as Map)['theme'], 'blue_glass');
  });
}
