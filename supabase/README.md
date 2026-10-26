# FlowIT Smart — Supabase

Schéma initial dérivé du cahier des charges v1.0 (§4, §5, §7, §9).

## Contenu

`migrations/20261026000000_flowit_smart_init.sql` crée :

| Table | Rôle |
|---|---|
| `profiles` | Profil applicatif, créé automatiquement à l'inscription (Supabase Auth) |
| `homes`, `home_members`, `home_invitations` | Maisons, rôles (`owner`, `admin`, `member`, `installer`), invitations par e-mail |
| `rooms` | Pièces (icône, ordre) |
| `integrations`, `integration_secrets` | Home Assistant, Tuya, Zigbee2MQTT… Secrets fermés au client (Vault recommandé) |
| `devices`, `device_bindings`, `device_capabilities` | Appareils, identifiant fournisseur caché, capacités en liste blanche |
| `device_commands` | Commandes : le client crée `pending`, le backend confirme ou signale l'échec |
| `scenes`, `scene_actions`, `scene_runs` | Scènes, actions ordonnées, historique d'exécution |
| `automations` | Déclencheur, conditions et actions (JSON validé) |
| `event_logs` | Journal en lecture seule, alimenté par triggers et backend |

## Sécurité vérifiée (tests locaux sur PostgreSQL 16)

- Un utilisateur étranger ne voit aucune maison ni appareil et ne peut pas commander.
- Un membre limité à certains appareils ne voit ni ne commande les autres.
- Un membre ne peut pas s'élever en `admin`, ni créer de pièce.
- Le client ne peut pas forcer le statut d'une commande ni lire `device_bindings` / `integration_secrets`.
- Doubles commandes bloquées par `idempotency_key`. Capacités non prises en charge refusées.
- Un membre révoqué ne peut plus commander immédiatement.
- Appareils `is_sensitive` (serrures…) bloqués par défaut.

## Appliquer

- Avec le connecteur Supabase : Claude applique la migration directement.
- Sinon : `supabase db push` (CLI) ou coller le fichier dans l'éditeur SQL du tableau de bord.

## Étapes suivantes

1. Edge Function `device-bridge` (service_role) : lit les `device_commands` en `pending`, appelle l'API REST/WebSocket Home Assistant, met à jour le statut (`confirmed` / `failed` / `timeout`).
2. Synchronisation HA vers `devices` / `device_capabilities` / `state` (temps réel via Supabase Realtime).
3. Auth : activer e-mail (et téléphone si besoin), limiter les tentatives, durée de session.
4. Client Flutter : `supabase_flutter` avec la clé `anon` uniquement, jamais la `service_role`.
