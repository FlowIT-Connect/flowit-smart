# Tests

| Partie | Commande | Résultat (30/10/2026) |
|---|---|---|
| SQL (fonctions, RLS, scènes, journal) | `cd supabase/tests && sh run_tests.sh` (PostgreSQL 16+, variables PG*) | 58 / 58 |
| Application Flutter | `cd app && flutter analyze && flutter test` | 0 alerte, 29 / 29 |
| Passerelle | `cd bridge && npm ci && npm test` | 88 / 88 |

## Ce qui est couvert
- SQL : création de maison, rôles et RLS, invitations, transfert de propriété, suppression de
  compte, exécution de scène (délais, politique stop / continuer, agrégation), journalisation.
- Flutter : traductions complètes FR / EN / AR, cycle d'une commande (attente, confirmation,
  délai dépassé, doublon ignoré, appareil sensible bloqué), parcours d'écrans en mode démo.
- Passerelle : correspondance HA → FlowIT, déclencheurs et conditions, file de commandes
  (une à la fois par appareil, scènes séquentielles, réclamation atomique), forme des
  requêtes Supabase.
- Caméras, photos, météo (29/10) : règles d'accès aux images (membre restreint, autre maison,
  écriture réservée à la passerelle), entité caméra HA et caméras directes, images envoyées
  seulement pendant qu'un membre regarde, photo produit Tuya, météo Open-Meteo (réponse, clé
  commerciale), vue caméra et photos dans l'application.
- Contrôle d'accès TTLock (30/10) : serrure bloquée par défaut, activation par le propriétaire
  seul et journalisée, commandes réservées au propriétaire / administrateurs et refusées aux
  scènes et automatisations, codes lisibles par les seuls gestionnaires ; client TTLock (OAuth
  MD5, jeton renouvelé, erreurs expliquées) contre un cloud TTLock simulé, création de code, accès partagés (partage programmé, désactivation, réactivation,
  suppression) et ouverture à distance (avec / sans passerelle), écran du boîtier en mode démo.
- Test visuel : application web en mode démo pilotée par Playwright (captures dans `screenshots/`).

## Pas encore testé
- Contre le vrai cloud TTLock et une vraie serrure (euapi.ttlock.com injoignable depuis le conteneur de développement).
- Contre un vrai projet Supabase (Realtime, Auth e-mail) : à faire dès que le projet est créé.
- Avec du vrai matériel via Home Assistant (le simulateur parle le même protocole WebSocket).
- Sur téléphone physique Android / iOS.

## Recette suggérée
1. Appliquer les migrations, lancer l'app avec Supabase, créer compte + maison + intégration.
2. Passerelle en `ADAPTER=simulator` : vérifier import, commandes confirmées, scène « Je pars ».
3. Remplacer par Home Assistant réel avec 2 ou 3 appareils, mesurer le temps de confirmation.
