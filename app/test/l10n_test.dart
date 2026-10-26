import 'dart:io';

import 'package:flowit_smart/core/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fr = L10n.strings['fr']!;

  test('les trois langues ont les mêmes clés', () {
    for (final code in ['en', 'ar']) {
      final other = L10n.strings[code]!;
      expect(fr.keys.toSet().difference(other.keys.toSet()), isEmpty, reason: 'clés manquantes en $code');
      expect(other.keys.toSet().difference(fr.keys.toSet()), isEmpty, reason: 'clés en trop en $code');
    }
  });

  test('les paramètres {x} sont identiques dans chaque traduction', () {
    final param = RegExp(r'\{(\w+)\}');
    for (final key in fr.keys) {
      final expected = param.allMatches(fr[key]!).map((m) => m[1]).toSet();
      for (final code in ['en', 'ar']) {
        final got = param.allMatches(L10n.strings[code]![key]!).map((m) => m[1]).toSet();
        expect(got, expected, reason: '$code:$key');
      }
    }
  });

  test('toutes les clés littérales du code existent', () {
    final used = <String>{};
    final pattern = RegExp(r"""(?:tr|tryTr)\('([a-zA-Z_.0-9]+)'""");
    final ternary = RegExp(r"""'((?:nav|dashboard|room|common|scene|automation|validation|auth|device)\.[a-zA-Z_.]+)'""");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      if (f.path.endsWith('l10n.dart')) continue;
      final src = f.readAsStringSync();
      used.addAll(pattern.allMatches(src).map((m) => m[1]!));
      used.addAll(ternary.allMatches(src).map((m) => m[1]!));
    }
    final missing = used.where((k) => !fr.containsKey(k) && !k.endsWith('.') && !k.endsWith('.dart')).toList()..sort();
    expect(missing, isEmpty);
  });

  test('interpolation et repli', () {
    final l = L10n.of(const Locale('ar'));
    expect(l.t('room.deviceCount', {'n': 3}), contains('3'));
    expect(l.t('cle.inexistante'), 'cle.inexistante');
    expect(L10n.of(const Locale('de')).code, 'fr');
  });
}
