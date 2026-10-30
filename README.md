# FlowIT Smart

Application domotique multimarque (cahier des charges v1.0 du 26/10/2026).

| Dossier | Contenu |
|---|---|
| `app/` | Application Flutter (Android, iOS, Web), FR / EN / AR (RTL) |
| `bridge/` | FlowIT Bridge : passerelle Node.js qui relie Supabase à Home Assistant sur le réseau local, ou directement au cloud Tuya |
| `supabase/` | Migrations SQL (schéma, RLS, fonctions) et tests |
| `docs/` | Architecture, installation, tests, limites, dépendances |
| `screenshots/` | Captures de l'application en mode démo |

**Version web en ligne** : https://flowit-connect.github.io/flowit-smart/ (republiée automatiquement à chaque push sur `main` touchant `app/`, voir `.github/workflows/deploy-web.yml`).

Démarrage rapide sans matériel ni compte : `cd app && flutter run -d chrome`
(par défaut, l'application se connecte au projet Supabase FlowIT ; avec `--dart-define=SUPABASE_URL=` vide, elle démarre en **mode démo** avec une maison fictive).

**Piloter une vraie maison** : suivre [docs/MAISON_REELLE.md](docs/MAISON_REELLE.md) (Home Assistant + module FlowIT Bridge, dossier `flowit_bridge/`).

**Tester des appareils Tuya / Smart Life sans box** : suivre [docs/TUYA_SANS_BOX.md](docs/TUYA_SANS_BOX.md) (la passerelle tourne sur un PC et passe par le cloud Tuya).

**Serrures et contrôles d'accès TTLock** (codes d'accès, historique, ouverture à distance avec passerelle G2/G3) : voir [docs/TTLOCK.md](docs/TTLOCK.md).

**Ajouter un appareil depuis Solea** (serrure TTLock en Bluetooth, appareil Smart Life guidé) : voir [docs/AJOUTER_UN_APPAREIL.md](docs/AJOUTER_UN_APPAREIL.md).

**Caméras IP, photos d'appareils, température extérieure** : voir [docs/CAMERAS_PHOTOS_METEO.md](docs/CAMERAS_PHOTOS_METEO.md).

Lire ensuite : [Architecture](docs/ARCHITECTURE.md), [Installation](docs/INSTALLATION.md),
[Tests](docs/TESTS.md), [Limites connues](docs/LIMITES.md), [Dépendances](docs/DEPENDANCES.md).
