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

  static bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
