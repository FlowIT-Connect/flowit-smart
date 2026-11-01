import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'config.dart';

/// Jeton push du téléphone, transmis à Supabase (table push_tokens).
typedef PushTokenSink = Future<void> Function(String token, String platform);

/// Notifications push quand l'app est fermée (Firebase Cloud Messaging).
///
/// Le serveur (fonction Supabase `send-push`) envoie chaque notification aux
/// jetons de l'utilisateur ; Android l'affiche lui-même, app fermée ou en
/// arrière-plan. App ouverte, le temps réel affiche déjà le bandeau habituel.
abstract class PushService {
  /// Demande l'autorisation et enregistre le jeton (à chaque connexion).
  Future<void> register(PushTokenSink save);

  /// Oublie le jeton de ce téléphone (déconnexion) et le renvoie pour suppression.
  Future<String?> unregister();
}

/// Push désactivé : tests, mode démo, web, ou Firebase pas encore configuré.
class NoPush implements PushService {
  const NoPush();
  @override
  Future<void> register(PushTokenSink save) async {}
  @override
  Future<String?> unregister() async => null;
}

class FirebasePush implements PushService {
  FirebasePush._();

  StreamSubscription<String>? _refresh;
  String? _token;

  static String? get _platform => switch (defaultTargetPlatform) {
        TargetPlatform.android => 'android',
        TargetPlatform.iOS => 'ios',
        _ => null,
      };

  static FirebaseOptions? get _options {
    final appId = _platform == 'ios' ? AppConfig.firebaseAppIdIos : AppConfig.firebaseAppIdAndroid;
    if (AppConfig.firebaseApiKey.isEmpty || appId.isEmpty || AppConfig.firebaseSenderId.isEmpty || AppConfig.firebaseProjectId.isEmpty) return null;
    return FirebaseOptions(
      apiKey: AppConfig.firebaseApiKey,
      appId: appId,
      messagingSenderId: AppConfig.firebaseSenderId,
      projectId: AppConfig.firebaseProjectId,
    );
  }

  /// Push Firebase si la plateforme et la configuration le permettent, sinon [NoPush].
  static Future<PushService> create() async {
    final options = _options;
    if (kIsWeb || _platform == null || options == null) return const NoPush();
    try {
      await Firebase.initializeApp(options: options);
      return FirebasePush._();
    } catch (e) {
      debugPrint('push: Firebase indisponible ($e)');
      return const NoPush();
    }
  }

  @override
  Future<void> register(PushTokenSink save) async {
    try {
      final m = FirebaseMessaging.instance;
      final perm = await m.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      // Jeton FCM classique : l'API HTTP v1 côté serveur l'accepte telle quelle
      // (l'envoi direct par identifiant d'installation est encore récent).
      // ignore: deprecated_member_use
      final token = await m.getToken();
      if (token == null) return;
      _token = token;
      await save(token, _platform!);
      await _refresh?.cancel();
      // ignore: deprecated_member_use
      _refresh = m.onTokenRefresh.listen((t) {
        _token = t;
        save(t, _platform!).catchError((Object e) => debugPrint('push: jeton non enregistré ($e)'));
      });
    } catch (e) {
      debugPrint('push: enregistrement impossible ($e)');
    }
  }

  @override
  Future<String?> unregister() async {
    await _refresh?.cancel();
    _refresh = null;
    final t = _token;
    _token = null;
    try {
      // ignore: deprecated_member_use
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    return t;
  }
}
