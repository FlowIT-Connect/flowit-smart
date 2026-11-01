# Solea Yeedi : piloter un robot aspirateur yeedi depuis Solea

Ce petit module relie votre compte **yeedi** (ou Ecovacs) à la passerelle Solea.
Dans l'application, le robot apparaît comme un appareil avec :

- les boutons **Nettoyer**, **Pause** / **Reprendre**, **Base** (retour à la station) et **Arrêter** ;
- la **puissance d'aspiration** (Silencieux, Standard, Fort, Maximum) ;
- l'**état** (nettoyage, en pause, vers la base, en charge, à l'arrêt, erreur), la **batterie** et le message d'erreur éventuel.

Il fonctionne aussi dans les automatisations (par exemple : lancer le robot à 10 h en semaine).

Modèles reconnus : yeedi 2 hybrid, yeedi vac 2 / vac 2 pro, yeedi vac hybrid, yeedi vac max, yeedi k650,
yeedi mop station, et la plupart des Deebot Ecovacs récents.

## Pourquoi un module à part ?

Il utilise la bibliothèque libre [ecovacs-deebot](https://github.com/mrbungle64/ecovacs-deebot.js),
sous licence **GPL version 3**. Pour que la passerelle Solea reste privée, ce module est un programme
séparé, lui-même publié sous **GPL v3 ou ultérieure** (voir `LICENSE`). Les deux programmes
se parlent uniquement par une petite API HTTP locale protégée par un jeton.

Le cloud yeedi n'a pas d'API officielle publique : une mise à jour de yeedi peut casser la connexion
jusqu'à ce que la bibliothèque soit mise à jour.

## Installation sur le PC Windows (à côté de la passerelle)

1. Téléchargez le ZIP de Solea et ouvrez le dossier `yeedi` (il est à côté du dossier `bridge`).
2. Lancez **`Configurer-Yeedi.cmd`** (Windows + R, puis le chemin complet du fichier).
3. Le Bloc-notes s'ouvre : saisissez l'e-mail et le mot de passe de l'**application yeedi**,
   vérifiez le pays (DZ pour l'Algérie), enregistrez (Ctrl + S) et fermez.
4. Le module vérifie le compte, affiche vos robots, se relie tout seul à la passerelle Solea
   (il ajoute `YEEDI_URL` et `YEEDI_TOKEN` dans `bridge\.env`) puis démarre. **Gardez cette fenêtre ouverte.**
5. Relancez la passerelle Solea (`bridge\Lancer-Passerelle.cmd`) : le robot apparaît dans l'application
   (rangé « Sans pièce » au début, rechargez l'app).

Les fois suivantes : lancez **`Lancer-Yeedi.cmd`**, puis la passerelle.

Le mot de passe yeedi n'est jamais enregistré en clair : seule son empreinte MD5 est gardée dans `yeedi\.env`.

## Sur le serveur (Docker)

Voir `bridge/docker-compose.serveur.yml` : remplissez `yeedi/.env`
(`YEEDI_EMAIL`, `YEEDI_PASSWORD_MD5`, `YEEDI_COUNTRY`, `YEEDI_TOKEN`), ajoutez dans `bridge/.env`
`YEEDI_URL=http://yeedi:8790` et le même `YEEDI_TOKEN`, puis
`docker compose -f docker-compose.serveur.yml --profile yeedi up -d --build`.

## Réglages (`yeedi/.env`)

| Réglage | Rôle | Par défaut |
| --- | --- | --- |
| `YEEDI_EMAIL` | compte de l'application yeedi | — |
| `YEEDI_PASSWORD_MD5` | empreinte MD5 du mot de passe | — |
| `YEEDI_COUNTRY` | pays du compte, 2 lettres | `DZ` |
| `YEEDI_DOMAIN` | `yeedi.com`, ou vide pour un compte Ecovacs | `yeedi.com` |
| `YEEDI_TOKEN` | jeton partagé avec la passerelle | créé par la configuration |
| `YEEDI_HOST` / `YEEDI_PORT` | adresse d'écoute | `127.0.0.1` / `8790` |

## En cas de souci

- **« yeedi.login_failed »** : e-mail, mot de passe ou pays faux. Relancez `Configurer-Yeedi.cmd`.
- **Le robot est « Indisponible » dans Solea** : la fenêtre du module est fermée, ou le robot n'est plus sur le Wi-Fi.
- **Une commande reste « délai dépassé »** : le robot n'a pas confirmé (bloqué, soulevé, batterie vide). Regardez l'app yeedi.

## Pour les développeurs

`npm test` lance les tests (robot simulé, aucun compte nécessaire).
API locale : `GET /robots` et `POST /robots/:id/command` avec `{"action": "start|pause|resume|stop|charge"}`
ou `{"suction": "quiet|standard|strong|max"}`, en-tête `Authorization: Bearer <YEEDI_TOKEN>`.
