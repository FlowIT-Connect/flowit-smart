# Installation

## 1. Supabase
1. Créer un projet Supabase (région Europe conseillée).
2. Appliquer dans l'ordre (SQL Editor ou `supabase db push`) :
   - `supabase/migrations/20261026000000_flowit_smart_init.sql`
   - `supabase/migrations/20261026010000_flowit_smart_app.sql`
3. Authentication > URL Configuration : mettre l'URL de l'application web comme « Site URL »
   (les liens de confirmation et de mot de passe oublié y renvoient).
4. Relever l'URL du projet et la clé **publishable/anon** (jamais la service_role dans l'app).

## 2. Application
```bash
cd app
flutter pub get
# Mode démo (aucun compte) :
flutter run -d chrome
# Avec Supabase :
flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_KEY=sb_publishable_xxx
# Builds
flutter build apk --release --dart-define=...
flutter build web --release --no-web-resources-cdn --dart-define=...
```
Au premier lancement : créer un compte, puis une maison. Dans Paramètres > Intégrations,
créer une intégration « Home Assistant » et copier son identifiant.

## 3. Passerelle (dans la maison)
Le plus simple : Home Assistant OS + module complémentaire **FlowIT Bridge**, voir
[MAISON_REELLE.md](MAISON_REELLE.md). Variante Docker ci-dessous.

Prérequis : une machine allumée en permanence sur le réseau local (Raspberry Pi 4/5, mini-PC)
avec Docker.
```bash
cd bridge
cp .env.example .env      # compléter SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, INTEGRATION_ID, HA_TOKEN
docker compose up -d                     # passerelle + Home Assistant
docker compose --profile zigbee up -d    # + Mosquitto + Zigbee2MQTT (clé USB Zigbee)
```
Le jeton HA se crée dans Home Assistant : profil > Sécurité > Jetons d'accès longue durée.
Dans HA, ajouter les intégrations des marques (MQTT pour Zigbee2MQTT, Tuya, Shelly…) :
la passerelle importe automatiquement les appareils, puis on les range par pièce dans l'app.

### Essai sans matériel
`ADAPTER=simulator` dans `.env` (pas besoin de HA_TOKEN) : 10 appareils fictifs apparaissent
dans l'application et répondent aux commandes.
Sans Docker : `npm ci && npm start` (Node 22).
