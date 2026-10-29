# Caméras, photos d'appareils et météo

Trois nouveautés de Solea, expliquées simplement.

![Vue caméra](../screenshots/fr_camera.png) ![Accueil avec la température extérieure](../screenshots/fr_meteo.png)

---

## 1. Caméras IP

### Ce que vous voyez dans l'application
- Une caméra apparaît comme un appareil, avec l'icône caméra (ou sa photo).
- En ouvrant sa fiche, l'image s'affiche **en direct** : elle est rafraîchie environ **chaque
  seconde**, avec l'heure de la dernière image. Bouton plein écran avec zoom au doigt.
- Si la caméra possède un détecteur de mouvement, il s'affiche dans « Mesures » et peut
  déclencher des automatisations comme n'importe quel capteur.

### Comment ça marche (et pourquoi c'est sûr)
1. Quand vous ouvrez la fiche d'une caméra, l'application prévient la passerelle Solea.
2. La passerelle, qui est **dans la maison**, lit l'image de la caméra sur le réseau local et
   l'envoie dans un espace de stockage privé.
3. L'application affiche cette image. Vous fermez la fiche : 15 secondes plus tard, la passerelle
   arrête d'envoyer des images.

Personne ne regarde = aucune image ne quitte la maison. Seuls les membres autorisés sur la
caméra peuvent voir ses images (un membre limité à certains appareils ne la voit pas).
La caméra n'a pas besoin d'être exposée sur Internet.

### Brancher une caméra : deux façons

**A. Avec Home Assistant (recommandé)** : ajoutez la caméra dans Home Assistant, elle apparaît
toute seule dans Solea. Intégrations HA à utiliser selon la marque :

| Caméra | Intégration Home Assistant |
|---|---|
| Hikvision, Dahua, Uniview, la plupart des caméras « ONVIF » | ONVIF |
| TP-Link Tapo | ONVIF (ou « Tapo: Cameras Control » via HACS) |
| Reolink | Reolink |
| Ezviz | EZVIZ |
| Imou | ONVIF |
| Caméras Tuya / Smart Life | Tuya |
| N'importe quelle caméra avec une adresse d'image ou un flux RTSP | Generic Camera |

**B. Sans Home Assistant (passerelle sur un PC de la maison)** : indiquez les caméras dans le
fichier `.env` de la passerelle, puis redémarrez-la :

```
CAMERAS=Entrée=http://admin:MOTDEPASSE@192.168.1.20/ISAPI/Streaming/channels/101/picture;Garage=http://admin:MOTDEPASSE@192.168.1.21/cgi-bin/snapshot.cgi
```

- Une caméra = `Nom=adresse de l'image`, séparées par `;`.
- Adresses d'image courantes : Hikvision `/ISAPI/Streaming/channels/101/picture`,
  Dahua / Imou `/cgi-bin/snapshot.cgi`, Reolink `/cgi-bin/api.cgi?cmd=Snap&channel=0&user=…&password=…`.
- La passerelle doit être sur **le même réseau** que les caméras (pas sur le serveur distant).
- Si la caméra répond « 401 », activez l'authentification « Basic » dans ses réglages ou passez
  par Home Assistant (qui gère toutes les méthodes).

### Limites actuelles
- C'est une **image par seconde**, pas une vidéo fluide, et **sans le son**. Pour la vidéo
  fluide, l'étape suivante est un relais WebRTC (go2rtc) : à prévoir si besoin.
- Les caméras Tuya ne sont pas lues par le mode « Tuya sans box » : passez par Home Assistant.

---

## 2. Photos réelles des appareils

Chaque appareil affiche une photo, choisie automatiquement dans cet ordre :

1. **Votre photo** : dans la fiche d'un appareil › Gestion › « Photo de l'appareil », prenez en
   photo votre propre climatiseur, votre caméra… (propriétaire, administrateur ou installateur).
2. **La photo officielle du produit** : pour les appareils Tuya / Smart Life, la passerelle
   récupère automatiquement la photo du produit, la même que dans l'app Smart Life.
3. **La photo du type d'appareil** (climatiseur, caméra, ampoule…) livrée avec l'application,
   si elle a été ajoutée dans `app/assets/devices/` (voir `LISEZMOI.md` dans ce dossier).
4. Sinon, l'icône.

Un climatiseur est reconnu à ses modes (froid, déshumidification, ventilation) : il a sa propre
icône et sa propre photo, différentes d'un thermostat de chauffage.

> Photos par type : aucune n'est livrée pour l'instant. Utilisez vos propres photos de produits
> ou des photos libres de droits pour un usage commercial, puis déposez-les dans
> `app/assets/devices/` avec les noms indiqués dans `LISEZMOI.md`.

---

## 3. Température extérieure

- Sur l'accueil, la pastille **« Dehors 27° »** donne la température actuelle de la ville de la
  maison. En la touchant : ressenti, minimum / maximum du jour, humidité, vent.
- **Changer de ville** : villes d'Algérie en un geste, ou recherche libre (n'importe quelle ville).
  Le choix est mémorisé pour chaque maison. Par défaut : Alger.
- Actualisation toutes les 15 minutes environ.
- Source : [Open-Meteo](https://open-meteo.com). Son offre gratuite est réservée à un usage non
  commercial : avant la commercialisation, souscrire l'offre « API » d'Open-Meteo et compiler
  l'application avec `--dart-define=WEATHER_API_KEY=VOTRE_CLE`.

---

## Mise en service

1. **Base de données** : appliquer la migration
   `supabase/migrations/20261029000000_solea_media.sql` (Supabase › SQL Editor, ou
   `supabase db push`). Elle ajoute les photos d'appareils et deux espaces de stockage privés
   (`camera-frames`, `device-photos`) avec leurs règles d'accès.
2. **Passerelle** : mettre à jour (`git pull` puis redémarrer, ou mettre à jour le module
   « FlowIT Bridge » 1.1.0 dans Home Assistant).
3. **Application** : republiée automatiquement après fusion.
