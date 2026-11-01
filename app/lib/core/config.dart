/// Configuration fournie à la compilation :
///   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_KEY=CLE_PUBLIQUE
/// Par défaut : projet Supabase FlowIT (qhzlmzfdbajulnymrwvg).
/// Pour le mode démo (données simulées) : --dart-define=SUPABASE_URL= --dart-define=SUPABASE_KEY=
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://qhzlmzfdbajulnymrwvg.supabase.co',
  );

  /// Clé publique (anon / publishable) uniquement — jamais la clé service_role.
  static const supabaseKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_is45UbEkZS6diyGIF0iCxQ_-gqZt0id',
  );

  /// Clé de l'offre commerciale Open-Meteo (météo extérieure). Vide = offre gratuite.
  static const weatherApiKey = String.fromEnvironment('WEATHER_API_KEY');

  /// Firebase (notifications push quand l'app est fermée). Valeurs publiques tirées
  /// de google-services.json ; vides = push désactivé, le reste de l'app marche.
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppIdAndroid = String.fromEnvironment('FIREBASE_APP_ID_ANDROID');
  static const firebaseAppIdIos = String.fromEnvironment('FIREBASE_APP_ID_IOS');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  static bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
