# Site international Solea

Site public de Solea (présentation, appareils compatibles, Solea Gateway, solutions,
automatisations, partenaires, contact), puis boutique, espace client et administration.
Séparé de l'application Flutter (`app/`), qui reste sur app.solea-dz.com.

**État : lot 1 sur 5** (socle et site public). Voir « Lots » plus bas.

## Technologies

| Élément | Choix |
|---|---|
| Interface | Next.js 16 (React 19, TypeScript), rendu serveur pour le référencement |
| Style | Tailwind CSS 4, polices Manrope et IBM Plex Sans Arabic (incluses, licence OFL) |
| Langues | next-intl : `fr` `en` `ar` (RTL) `es` `de` `it`, une URL par langue (`/fr/...`) |
| Base de données | Projet Supabase **dédié au site** (pas celui de l'app) |
| Hébergement | Netlify (projet « flowit-smart », domaine solea-dz.com), ou Docker sur le serveur ADEX |

## Démarrer en local

```sh
cd site
npm install
cp .env.example .env    # facultatif en local
npm run dev             # http://localhost:3000
```

Sans `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY`, le site fonctionne, mais les formulaires
affichent clairement « pas encore relié » au lieu de faire semblant d'enregistrer.

## Variables d'environnement

| Variable | Rôle |
|---|---|
| `SITE_URL` | Adresse publique (`https://solea-dz.com`) : liens canoniques, hreflang, sitemap |
| `SUPABASE_URL` | URL du projet Supabase du site |
| `SUPABASE_PUBLISHABLE_KEY` | Clé **publique** (publishable) du projet. Jamais la clé secrète |
| `GEOIP_DB` | Chemin de la base DB-IP Lite (`.mmdb`). Téléchargée automatiquement par le `Dockerfile` |

## Base de données (projet Supabase du site)

1. Créer un projet sur supabase.com (par exemple « solea-site », région Europe).
2. SQL Editor : coller et exécuter `supabase/migrations/20261101000000_site_forms.sql`.
3. Mettre l'URL du projet et sa clé publishable dans le `.env` du serveur.

Le fichier crée trois tables (préinscriptions Gateway, demandes de contact / devis,
demandes de partenariat). Les visiteurs **ne peuvent ni lire ni écrire directement** :
ils passent par trois fonctions qui valident les données et limitent les envois
(5 demandes par heure et par adresse e-mail). La lecture se fera dans l'administration (lot 4).

Ces migrations sont dans `site/supabase/` exprès : l'intégration GitHub de Supabase de l'app
lit `supabase/` à la racine et ne doit jamais les appliquer au projet de l'app.

## Pays, langue et devise

- Première visite sur `/` : langue choisie d'après le navigateur (et le pays si le proxy
  fournit un en-tête `CF-IPCountry` ou `X-Country-Code`).
- Ensuite un bandeau **propose** la langue et la devise du pays détecté (adresse IP lue dans
  la base DB-IP Lite sur le serveur, rien n'est envoyé à un service externe, l'IP n'est pas
  conservée). Le visiteur accepte, choisit lui-même ou ferme ; le choix est gardé un an.
- Le bouton 🌐 de l'en-tête permet à tout moment de changer langue, pays et devise.
- Règles (exemples du cahier des charges) dans `src/lib/locales.ts`, testées dans
  `tests/unit/locales.test.mjs`. Ajouter un pays = une ligne.
- Ajouter une langue : l'ajouter à `locales` dans `src/lib/locales.ts` et créer
  `messages/<code>.json` (le test vérifie que toutes les clés sont présentes).

## Tests

```sh
npm run typecheck
npm test                                  # langues, détection pays, devises (11 tests)
npm run build && sh scripts/serve-standalone.sh &
node tests/e2e.mjs                        # navigateur : 60 pages, RTL, bandeau, préférences, formulaires, SEO (13 tests)
sh supabase/tests/run_tests.sh            # SQL sur PostgreSQL 16 (17 tests)
```

Les mêmes tests tournent sur GitHub à chaque PR (`.github/workflows/site-ci.yml`).

## Mise en ligne sur Netlify (solution actuelle)

Le fichier `netlify.toml` à la racine du dépôt indique à Netlify de construire le dossier `site/`.
Une seule fois, dans le projet Netlify « flowit-smart » : *Project configuration → Build & deploy →
Link repository*, choisir `FlowIT-Connect/flowit-smart`, branche `main`. Variables d'environnement
(*Environment variables*) : `SITE_URL`, `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` (valeurs de
`.env.example`, toutes publiques). Ensuite chaque fusion sur `main` met le site à jour.
Le pays du visiteur est lu dans l'en-tête de géolocalisation de Netlify.

## Autre possibilité : serveur ADEX (Docker)

```sh
git clone https://github.com/FlowIT-Connect/flowit-smart.git
cd flowit-smart/site
cp .env.example .env && nano .env   # SITE_URL, SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY
docker compose up -d --build        # le site écoute sur 127.0.0.1:3000
```

Puis faire pointer solea-dz.com et www vers le serveur (enregistrements A chez Namecheap,
à la place des redirections provisoires vers l'app) et ajouter le site au proxy HTTPS
du serveur. Les étapes détaillées seront fournies au lot 5.

## Photos

Le site utilise pour l'instant des **illustrations vectorielles** (villa, Solea Gateway,
icônes) : aucune photo n'est reprise sans licence. Les photographies Unsplash / Pexels
seront ajoutées dès que ces sites seront accessibles depuis l'environnement de
développement, avec un fichier de crédits. La Solea Gateway est toujours marquée
« illustration conceptuelle, rendu non contractuel ».

## Lots

1. **Socle et site public** (ce lot) : 10 pages × 6 langues, RTL, pays / devise,
   formulaires Gateway, contact / devis, partenariat, SEO de base.
2. Catalogue et boutique : produits, recherche, filtres, comparateur, favoris, panier.
3. Comptes et commandes : inscription, connexion, mot de passe oublié, espace client,
   commandes, factures, e-mails (dont la notification de l'administrateur à chaque demande).
4. Administration : produits, import / export Excel et CSV, images, commandes, clients,
   devises, traductions, Gateway, rôles, journal.
5. Pages légales, tests complets, documentation, mise en ligne.
