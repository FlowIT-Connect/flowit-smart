/// Configuration fournie à la compilation :
///   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_KEY=CLE_PUBLIQUE
/// Sans ces valeurs, l'application démarre en mode démo (données simulées).
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Clé publique (anon / publishable) uniquement — jamais la clé service_role.
  static const supabaseKey = String.fromEnvironment('SUPABASE_KEY');

  static bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
