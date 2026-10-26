# FlowIT Smart, application

Flutter (Android, iOS, Web). Voir `../docs/INSTALLATION.md`.

- Supabase (par défaut) : `flutter run -d chrome` se connecte au projet FlowIT (`qhzlmzfdbajulnymrwvg`).
- Autre projet : `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=<clé publishable>`.
- Mode démo : `flutter run -d chrome --dart-define=SUPABASE_URL= --dart-define=SUPABASE_KEY=`.
- Tests : `flutter analyze && flutter test`.
