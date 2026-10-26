import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/l10n.dart';
import 'data/backend.dart';
import 'data/demo_backend.dart';
import 'data/supabase_backend.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final Backend backend;
  if (AppConfig.hasSupabase) {
    await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseKey);
    backend = SupabaseBackend(Supabase.instance.client);
  } else {
    backend = DemoBackend();
  }

  Locale? locale;
  try {
    final code = (await SharedPreferences.getInstance()).getString('locale');
    if (code != null) locale = Locale(code);
  } catch (_) {}
  locale ??= L10n.resolve(WidgetsBinding.instance.platformDispatcher.locale);

  runApp(FlowItApp(state: AppState(backend, initialLocale: locale)));
}
