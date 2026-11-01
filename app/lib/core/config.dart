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

  /// Firebase (notifications push quand l'app est fermée), projet solea-a979b.
  /// Valeurs publiques tirées de google-services.json (elles sont dans chaque APK) ;
  /// vides = push désactivé, le reste de l'app marche. iOS : à ajouter avec la clé APNs.
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY', defaultValue: 'AIzaSyCvouU7F7gxl4l3RjGeojGt87_vYyjGogQ');
  static const firebaseAppIdAndroid = String.fromEnvironment('FIREBASE_APP_ID_ANDROID', defaultValue: '1:174318293704:android:0f0086c5b54b82309fcbfd');
  static const firebaseAppIdIos = String.fromEnvironment('FIREBASE_APP_ID_IOS');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID', defaultValue: '174318293704');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID', defaultValue: 'solea-a979b');

  static bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
