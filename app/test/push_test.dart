import 'package:flowit_smart/core/push.dart';
import 'package:flowit_smart/data/demo_backend.dart';
import 'package:flowit_smart/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePush implements PushService {
  String? token;
  int registered = 0;

  @override
  Future<void> register(PushTokenSink save) async {
    registered++;
    token = 'fcm-jeton-de-test-0123456789';
    await save(token!, 'android');
  }

  @override
  Future<String?> unregister() async {
    final t = token;
    token = null;
    return t;
  }
}

void main() {
  test('push : jeton enregistré à la connexion, supprimé à la déconnexion', () async {
    final backend = DemoBackend();
    final push = FakePush();
    final state = AppState(backend, initialLocale: const Locale('ar'), push: push);
    await backend.signIn('demo@solea-dz.com', 'demo');
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(push.registered, 1);
    expect(backend.pushTokens['fcm-jeton-de-test-0123456789'], {'platform': 'android', 'locale': 'ar'});

    await state.signOut();
    expect(backend.pushTokens, isEmpty);
    state.dispose();
  });

  test('sans Firebase configuré : aucun push, rien ne casse', () async {
    expect(await const NoPush().unregister(), isNull);
    expect(await FirebasePush.create(), isA<NoPush>());
  });
}
