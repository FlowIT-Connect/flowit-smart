# Architecture

```
 Téléphone / Web (Flutter)            Supabase (cloud)                 Maison (réseau local)
 ┌──────────────────────┐   anon   ┌────────────────────────┐ service ┌──────────────────────┐
 │ FlowIT Smart          │ ───────▶ │ Auth · Postgres + RLS  │ ◀────── │ FlowIT Bridge (Node) │
 │ clé publique seule    │ ◀─────── │ Realtime · RPC         │ ──────▶ │ WebSocket HA         │
 └──────────────────────┘ realtime └────────────────────────┘ realtime└─────────┬────────────┘
                                                                                  │ LAN
                                                                     Home Assistant · Zigbee2MQTT
                                                                     (Tuya, Shelly, Netatmo…)
```

## Principes
- **L'application ne parle jamais directement aux appareils.** Elle écrit une ligne dans
  `device_commands` (statut `pending`, clé d'idempotence) et observe son évolution.
- **La passerelle** tourne à côté de Home Assistant, sans l'exposer à Internet. Elle réclame
  la commande de façon atomique (`pending → sent`), appelle le service HA, puis passe en
  `confirmed` **uniquement quand l'état réel de l'appareil a changé**. Sinon `failed`,
  `timeout` ou `rejected` (valeur invalide, appareil sensible, intégration désactivée).
- **Interface honnête** : la tuile garde l'état confirmé et affiche un indicateur d'attente ;
  au-delà de 15 s sans réponse, l'application l'indique. Si le temps réel tombe, elle
  bascule sur un rafraîchissement périodique.
- **Scènes** : RPC `execute_scene` côté serveur, actions ordonnées avec délais (`not_before`),
  politique d'échec (continuer / arrêter), résultat agrégé dans `scene_runs`.
- **Automatisations** : déclencheurs heure / état d'appareil / manuel, conditions plage horaire
  et état ; exécutées localement par la passerelle (fonctionnent sans application ouverte),
  anti-boucle 10 s.
- **Sécurité** : RLS par maison et par rôle (owner, admin, member, guest). Les secrets
  (jeton HA, clé service_role) restent dans le `.env` de la passerelle.
- **Journal** : déclencheurs SQL qui tracent commandes, scènes, changements de configuration
  et disponibilité des appareils ; purge via `purge_event_logs(jours)`.

## Application Flutter (`app/lib`)
- `core/` : configuration, thème, icônes, traductions (`context.tr`).
- `data/` : interface `Backend`, implémentation Supabase et `DemoBackend` (maison fictive).
- `state/app_state.dart` : état global (ChangeNotifier), envoi de commandes, temps réel.
- `ui/` : navigation adaptative (barre en bas sur mobile, rail sur grand écran), écrans
  Accueil, Pièces, Appareils, Fiche appareil, Scènes, Automatisations, Paramètres
  (membres, intégrations, journal), connexion et première maison.

## Passerelle (`bridge/src`)
- `adapters/home_assistant.js` : client WebSocket HA (reconnexion avec backoff).
- `adapters/ha_mapping.js` : entités HA → appareils et capacités FlowIT.
- `adapters/fake_home_assistant.js` : simulateur (`ADAPTER=simulator`).
- `adapters/tuya_api.js`, `tuya_mapping.js`, `tuya_cloud.js` : mode sans box (`ADAPTER=tuya_cloud`),
  API cloud Tuya signée, interrogation périodique, confirmation par relecture de l'état.
- `setup.js` : assistant de configuration sur PC (`npm run configurer`), écrit le `.env`.
- `bridge.js` : inventaire, file de commandes, automatisations ; `store.js` : accès Supabase.
