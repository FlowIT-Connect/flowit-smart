# Publier Solea sur Google Play et l'App Store

La publication est automatique : le workflow GitHub **« Publier sur les stores »**
(`.github/workflows/publier-stores.yml`) compile l'app, la signe et l'envoie aux stores avec
fastlane (`app/fastlane/`). Il faut seulement, **une seule fois**, créer les clés et les
enregistrer comme secrets GitHub. Ensuite, chaque nouvelle version part en un clic.

Les comptes Google Play Console et Apple Developer déjà utilisés pour ResidenceConnect
servent aussi pour Solea : un compte développeur peut publier autant d'applications que l'on veut.

## Ce qui est déjà prêt dans le dépôt

- Identifiant définitif de l'app : **`com.soleadz.app`** (Android et iOS). Il ne pourra plus
  changer après la première publication.
- Nom affiché : **Solea** sur Android et iOS.
- Signature Android de production (clé lue dans les secrets GitHub, jamais dans le dépôt).
- iOS : messages d'autorisation Bluetooth, appareil photo et photos ; déclaration « pas de
  chiffrement spécial » (évite une question à chaque envoi).
- Textes des fiches en français et en anglais : `app/fastlane/metadata/`.
- Politique de confidentialité : `app/web/confidentialite.html`, en ligne après fusion sur
  https://flowit-connect.github.io/flowit-smart/confidentialite.html
- La suppression du compte existe dans l'app (Paramètres › Compte › Supprimer mon compte),
  ce que Google et Apple exigent.

## Où saisir les secrets

GitHub › dépôt `flowit-smart` › **Settings › Secrets and variables › Actions › New repository secret**
(https://github.com/flowit-connect/flowit-smart/settings/secrets/actions).
Ne collez jamais une clé ou un mot de passe dans le chat ni dans un fichier du dépôt.

| Secret | Pour | Contenu |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | Android | contenu du fichier `solea-upload.base64.txt` |
| `ANDROID_KEYSTORE_PASSWORD` | Android | mot de passe choisi pour la clé |
| `ANDROID_KEY_ALIAS` | Android | `solea` |
| `ANDROID_KEY_PASSWORD` | Android | même mot de passe que ci-dessus |
| `PLAY_SERVICE_ACCOUNT_JSON` | Android | tout le contenu du fichier JSON du compte de service |
| `ASC_KEY_ID` | iOS | identifiant de la clé API App Store Connect |
| `ASC_ISSUER_ID` | iOS | « Issuer ID » affiché au-dessus de la liste des clés |
| `ASC_KEY_P8_BASE64` | iOS | fichier `.p8` converti en base64 |
| `APPLE_TEAM_ID` | iOS | Team ID (10 caractères) |
| `MATCH_GIT_URL` | iOS | adresse du dépôt privé des certificats |
| `MATCH_GIT_BASIC_AUTHORIZATION` | iOS | `FlowIT-Connect:jeton` converti en base64 |
| `MATCH_PASSWORD` | iOS | nouveau mot de passe qui chiffre les certificats |

## Android (Google Play)

1. **Créer la clé de publication.** Sur le PC Windows, double-cliquer
   `app\android\Creer-cle-Android.cmd`. Il crée `solea-upload.jks` et `solea-upload.base64.txt`
   (Android Studio ou Java 17 doit être installé). Remplir les 4 secrets `ANDROID_…`.
   Garder une copie de `solea-upload.jks` et du mot de passe en lieu sûr, puis supprimer le `.txt`.
2. **Créer l'app dans la Play Console** : Toutes les applications › Créer une application ›
   nom « Solea », langue Français, Application, Gratuite.
3. **Première version, à la main** (Google l'impose pour une nouvelle app) : GitHub › Actions ›
   « Publier sur les stores » › Run workflow › plateforme `android`. À la fin, télécharger
   `Solea-google-play-…` en bas de la page de l'exécution (rubrique Artifacts), le dézipper, puis
   Play Console › Tester › Tests internes › Créer une release › déposer `app-release.aab`.
   Accepter « Signature d'application Play » quand Google le propose.
4. **Autoriser GitHub à publier** :
   - Google Cloud Console (https://console.cloud.google.com) : créer un projet « solea-publication »,
     activer **Google Play Android Developer API**, puis IAM › Comptes de service › Créer
     (nom « github-solea ») › Clés › Ajouter une clé › JSON. Le fichier se télécharge.
   - Play Console › Utilisateurs et autorisations › Inviter : l'adresse e-mail du compte de
     service (…@….iam.gserviceaccount.com), accès à l'app Solea avec « Publier dans les canaux de
     test » et « Gérer les versions de production ».
   - Coller tout le contenu du JSON dans le secret `PLAY_SERVICE_ACCOUNT_JSON`.
5. **Fiche du store** (Play Console › Développer la présence sur le Play Store, puis
   « Contenu de l'application ») : icône 512×512, image de présentation 1024×500, au moins
   2 captures de téléphone, URL de la politique de confidentialité, questionnaire de
   classification, sécurité des données, public cible, publicité (non), et **un compte de
   démonstration** pour les testeurs de Google (l'app demande une connexion).

> Si le compte Google Play est un compte **personnel créé après novembre 2023**, Google exige,
> pour chaque nouvelle app, un test fermé avec au moins 12 testeurs pendant 14 jours avant la
> production. Un compte d'organisation (entreprise) n'a pas cette obligation.

## iOS (App Store)

Aucun Mac n'est nécessaire : la compilation se fait sur un Mac de GitHub.

1. **Déclarer l'identifiant** : https://developer.apple.com/account › Certificates, IDs & Profiles ›
   Identifiers › + › App IDs › App › description « Solea », Bundle ID explicite `com.soleadz.app`.
2. **Créer l'app** : App Store Connect › Apps › + › Nouvelle app › iOS, nom « Solea » (si le nom est
   déjà pris sur l'App Store, essayer « Solea Maison »), langue Français, Bundle ID `com.soleadz.app`,
   SKU `solea`.
3. **Clé API** : App Store Connect › Utilisateurs et accès › Intégrations › Clés API App Store Connect ›
   Générer, accès **Admin** (nécessaire pour créer le certificat). Noter le Key ID et l'Issuer ID,
   télécharger le fichier `.p8` (une seule fois possible). Pour le secret `ASC_KEY_P8_BASE64`,
   dans PowerShell :
   `[Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\Downloads\AuthKey_XXXX.p8"))`
4. **Team ID** : https://developer.apple.com/account › Membership details › Team ID.
5. **Coffre des certificats (fastlane match)** :
   - Créer sur GitHub un dépôt **privé et vide** `FlowIT-Connect/solea-certificats`.
     `MATCH_GIT_URL` = `https://github.com/FlowIT-Connect/solea-certificats.git`
   - Créer un jeton GitHub (Settings › Developer settings › Fine-grained tokens), limité au dépôt
     `solea-certificats`, permission **Contents : Read and write**. Puis, dans PowerShell :
     `[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("FlowIT-Connect:LE_JETON"))`
     et coller le résultat dans `MATCH_GIT_BASIC_AUTHORIZATION`.
   - `MATCH_PASSWORD` : inventer un mot de passe solide et le garder ; il chiffre les certificats.
   Au premier lancement, fastlane crée le certificat de distribution et le profil, puis les range
   chiffrés dans ce dépôt. Apple limite le nombre de certificats de distribution par compte :
   si la création échoue pour cette raison, en révoquer un ancien inutilisé.
6. **Lancer** : Actions › « Publier sur les stores » › Run workflow › plateforme `ios`. La version
   apparaît dans TestFlight environ 15 minutes après la fin.
7. **Fiche et soumission** (App Store Connect) : captures iPhone 6,9 pouces (1320×2868),
   « Confidentialité de l'app » (données collectées : e-mail, nom, photos, contenu de l'utilisateur ;
   aucune utilisée pour le suivi), compte de démonstration pour l'équipe de revue d'Apple,
   puis choisir le build et « Soumettre pour vérification ».

## Publier une nouvelle version

1. Augmenter `version:` dans `app/pubspec.yaml` (ex. `1.0.1+1` ; le nombre après `+` est remplacé
   automatiquement par le numéro de l'exécution GitHub).
2. Fusionner sur `main`, puis lancer « Publier sur les stores » (ou pousser une étiquette `v1.0.1`).

Options du lancement manuel :

- **Piste Google Play** : `internal` (testeurs internes, par défaut), `alpha` (test fermé),
  `beta` (test ouvert), `production`.
- **Statut** : `draft` tant que l'app n'a jamais été publiée (Google refuse autre chose) ;
  `completed` ensuite pour diffuser directement.
- **Fiches** : coché, les textes de `app/fastlane/metadata/` remplacent ceux des stores.

iOS envoie toujours sur TestFlight ; la mise en vente reste un clic dans App Store Connect.

## Avant d'ouvrir au public

- Créer l'adresse **contact@solea-dz.com** (citée dans la politique de confidentialité et comme
  page d'assistance), ou changer l'adresse dans `app/web/confidentialite.html`.
- Les fiches demandent un compte de démonstration : créer un compte Solea avec une maison de test.
- Juridique Algérie (voir le plan de commercialisation) : déclaration ANPDP (loi 18-07), transfert
  de données hors d'Algérie (Supabase).
