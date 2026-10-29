import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/device_photos.dart';
import 'core/l10n.dart';
import 'core/theme.dart';
import 'data/backend.dart';
import 'data/demo_backend.dart';
import 'data/supabase_backend.dart';
import 'data/weather.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final (font, file) in const [('Manrope', 'OFL-Manrope.txt'), ('IBM Plex Sans Arabic', 'OFL-IBMPlexSansArabic.txt')]) {
      yield LicenseEntryWithLineBreaks([font], await rootBundle.loadString('assets/fonts/$file'));
    }
  });
  await ThemeController.instance.load();
  await DevicePhotoCatalog.load();

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

  runApp(FlowItApp(state: AppState(backend, initialLocale: locale, weatherService: OpenMeteoWeather())));
}
