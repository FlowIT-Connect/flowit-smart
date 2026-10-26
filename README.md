# FlowIT Smart

Application domotique multimarque (cahier des charges v1.0 du 26/10/2026).

| Dossier | Contenu |
|---|---|
| `app/` | Application Flutter (Android, iOS, Web), FR / EN / AR (RTL) |
| `bridge/` | FlowIT Bridge : passerelle Node.js qui relie Supabase à Home Assistant sur le réseau local |
| `supabase/` | Migrations SQL (schéma, RLS, fonctions) et tests |
| `docs/` | Architecture, installation, tests, limites, dépendances |
| `screenshots/` | Captures de l'application en mode démo |

**Version web en ligne** : https://flowit-connect.github.io/flowit-smart/ (republiée automatiquement à chaque push sur `main` touchant `app/`, voir `.github/workflows/deploy-web.yml`).

Démarrage rapide sans matériel ni compte : `cd app && flutter run -d chrome`
(par défaut, l'application se connecte au projet Supabase FlowIT ; avec `--dart-define=SUPABASE_URL=` vide, elle démarre en **mode démo** avec une maison fictive).

Lire ensuite : [Architecture](docs/ARCHITECTURE.md), [Installation](docs/INSTALLATION.md),
[Tests](docs/TESTS.md), [Limites connues](docs/LIMITES.md), [Dépendances](docs/DEPENDANCES.md).
