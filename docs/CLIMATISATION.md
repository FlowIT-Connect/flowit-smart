# Climatiseurs et chauffage dans Solea

Solea reconnaît les appareils de chauffage et de climatisation d'après les fonctions
qu'ils déclarent réellement : rien n'est supposé. Ce qui n'est pas déclaré n'apparaît pas.

## Appareils pris en charge

| Appareil | Par Tuya / Smart Life | Par Home Assistant |
| --- | --- | --- |
| Climatiseur connecté (split, mobile) | catégorie `kt` : marche, mode, consigne, ventilation, oscillation, mode nuit, éco | entité `climate` |
| Climatiseur classique avec télécommande | télécommande infrarouge Tuya : à vérifier sur un vrai boîtier (ses codes varient selon le modèle) | intégrations IR (Broadlink, SmartIR) |
| Thermostat d'ambiance / de chaudière | catégorie `wk` : consigne, programme (auto, manuel, éco, confort, absence), état de chauffe | entité `climate` |
| Tête thermostatique de radiateur | catégorie `wkf` : consigne, programme, détection fenêtre ouverte, verrouillage enfant, batterie | entité `climate` |
| Radiateur électrique | catégorie `qn` : marche/chauffe, consigne | entité `climate` |
| Chauffe-eau, chaudière | catégorie `rs` : marche, consigne, mode | entité `water_heater` : consigne, mode, absence |

## Ce que l'app affiche

- **Mode** : Arrêt, Auto, Climatisation, Chauffage, Déshumidification, Ventilation.
- **Ambiance** : Programme, Manuel, Confort, Éco, Nuit, Absence, Hors-gel, Boost (selon l'appareil).
- **Ventilation** : Auto, Silencieux, Faible, Moyenne, Forte, Turbo.
- **Oscillation**, **Mode nuit**, **Mode éco**, **Détection fenêtre ouverte**, **Verrouillage enfant**, **Hors-gel**.
- Dans les réglages de l'appareil : **Étalonnage de la sonde** (± quelques degrés).
- **Activité** (lecture seule) : chauffe en cours, refroidit, en attente.

## Si un appareil manque une fonction

Dans la fenêtre de la passerelle, cherchez la ligne de l'appareil et envoyez-nous sa
catégorie et la liste de ses codes Tuya : on ajoute la correspondance.

## Thermostat de chaudière sans fil (Wi-Fi + RF 433 MHz)

Exemple : thermostat ECOBUY vendu sur Ouedkniss, qui reprend le modèle EZAIOT R9BW & RC9P (Smart Life / Tuya, thermostat sur 3 piles AA, récepteur 100-240 V). Il se compose de deux pièces :

- le **thermostat d'ambiance**, sur piles, posé dans la pièce de vie : il mesure la température
  et l'humidité et envoie ses ordres par radio 433 MHz (jusqu'à 200 m en champ libre) ;
- le **récepteur Wi-Fi**, branché près de la chaudière : son relais ferme le contact
  « thermostat d'ambiance » de la chaudière. C'est lui qui parle au cloud Tuya.

Prendre la **version 3 A (contact sec)** pour une chaudière murale. La version 16 A sert au
chauffage électrique au sol.

### Branchement (à faire chaudière hors tension)

1. Repérer sur le bornier de la chaudière l'entrée **TA** / **thermostat d'ambiance**
   (souvent un pont entre deux bornes). Retirer le pont.
2. Relier ces deux bornes aux bornes **COM** et **OPEN** (parfois notée **NO**) du récepteur. Ne jamais faire passer
   l'alimentation 230 V de la chaudière par le relais.
3. Alimenter le récepteur en 230 V (L, N) et l'appairer au thermostat (notice du vendeur).

### Ajout dans Solea

1. Ajouter le thermostat dans **Smart Life** (Wi-Fi 2,4 GHz) avec le compte déjà relié à Solea.
2. La passerelle le découvre (catégorie `wk`) au prochain inventaire ; il arrive « Sans pièce » :
   le ranger dans la bonne pièce.
3. Dans **Chauffage et clim**, l'associer à la pièce pour profiter des ambiances, du programme
   de la semaine, de la fenêtre ouverte et du préchauffage.

Ce que Solea pilote : marche/arrêt, consigne, température et humidité mesurées, programme
(auto, manuel, vacances → Programme, Manuel, Absence), mode éco, hors-gel, verrouillage enfant,
étalonnage de la sonde, état du relais (chauffe / en attente) et piles.

Les codes Tuya varient d'un lot à l'autre : si une fonction manque, envoyer la catégorie et les
codes Tuya de l'appareil : on ajoute la correspondance.

## Solea HVAC Connect : ajouter un équipement par sa marque

Dans **Appareils › Ajouter un appareil › Climatisation et chauffage**, Solea guide en 5 étapes :

1. **Type** : climatiseur, chaudière, thermostat ou tête de radiateur.
2. **Marque** : environ 45 marques de clims et 45 de chaudières, celles distribuées en Algérie en tête ; « Autre marque » propose les solutions universelles.
3. **Modèle** (référence facultative) et présence du Wi-Fi.
4. **Façon de le connecter**, la recommandée en premier :

| Voie | Pour | Ce qu'elle permet |
| --- | --- | --- |
| Wi-Fi via Smart Life | appareils compatibles Smart Life / Tuya | marche, mode, consigne, ventilation, température |
| Télécommande infrarouge Tuya | toute clim à télécommande | marche, mode, consigne, ventilation (sans retour d'état) |
| Application du fabricant via Home Assistant | Daikin, MELCloud, SmartThings, LG ThinQ, Gree+, ViCare, myVAILLANT… | tout ce que permet l'application |
| Thermostat connecté sur la chaudière | toutes les chaudières (bornier thermostat d'ambiance) | chauffe selon la pièce, programmes, ambiances |
| Passerelle OpenTherm | chaudières avec bornier OpenTherm | départ, eau chaude, modulation, diagnostic |
| Bus de la chaudière (eBUS, EMS) | groupes Vaillant et Bosch | consignes, états, codes d'erreur |
| Interface Modbus / RS485 | clims professionnelles, VRF, grosses chaudières | consigne, température réelle, état, codes d'erreur |

5. **Mise en place et test** : les étapes s'affichent, puis « Tester la connexion » demande à la passerelle de repérer l'appareil et affiche les commandes réellement disponibles.

Sécurité : Solea ne coupe jamais l'alimentation électrique d'une chaudière ; il passe toujours par l'entrée de commande prévue par le fabricant.

Ajouter une marque = une ligne dans `app/lib/core/hvac_catalog.dart` : aucune intégration n'est codée marque par marque.

## Ambiances par pièce (Confort, Éco, Nuit, Absence, Hors-gel)

Sur l'accueil, la carte **Chauffage et clim** change l'ambiance de toute la maison en un geste
(jusqu'à nouvel ordre, pendant 2 heures ou jusqu'à demain 7 h). Dans l'écran complet :

- **Pièces** : chaque pièce a ses appareils pilotés et son programme de la semaine
  (par défaut : Confort au lever et au retour, Éco la journée, Nuit à 22 h 30, Confort le week-end).
- **Températures des ambiances** : en chauffage et en climatisation (21 / 24 °C en Confort, 19 / 27 en Éco,
  18 / 26 en Nuit, 16 / 29 en Absence, 7 °C en Hors-gel par défaut).
- Ordre de priorité : ambiance choisie pour la pièce, puis pour la maison, puis Vacances (Absence),
  puis le programme.
- Mode **Hiver** de l'accueil : les appareils passent en chauffage ; mode **Été** : en climatisation.
  Sans saison, chaque appareil garde son mode.
- La passerelle applique l'ambiance **quand elle change** : un réglage fait à la main entre-temps est respecté.

Base : migration `20261110000000_solea_climate.sql` (tables `climate_settings`, `climate_zones`, fonction `set_climate_preset`).

## Fenêtre ouverte

Dans le réglage d'une pièce, la section **Fenêtre ouverte** associe les capteurs d'ouverture
(fenêtres, porte-fenêtre, Aqara, Zigbee, Tuya…) et le délai avant coupure (1, 2, 5 ou 10 minutes ; 2 par défaut).

- Une fenêtre reste ouverte plus longtemps que le délai : la passerelle **coupe la clim ou le chauffage** de la pièce
  et prévient les membres du logement (notification « Fenêtre ouverte »). La carte de la pièce l'affiche.
- La coupure passe **toujours par l'appareil** (mode Arrêt, ou consigne Hors-gel s'il n'a pas de mode) :
  jamais par une prise ou un disjoncteur, surtout pas pour une chaudière.
- Fenêtre fermée : chaque appareil reprend le mode qu'il avait (ou celui de la saison), puis l'ambiance du moment.
- Les têtes thermostatiques qui détectent elles-mêmes une fenêtre ouverte (`window_open`) déclenchent aussi la coupure.
- Redémarrage de la passerelle pendant une coupure : la pièce reste coupée, et à la fermeture le mode de la saison est remis.

Base : migration `20261111000000_solea_climate_windows.sql` (colonnes `windows`, `window_delay`, `active_window`).

## Températures intelligentes

- **Je pars / Je rentre** (accueil et écran Chauffage et clim) : « Je pars » met toute la maison en Absence,
  jusqu'au retour ou jusqu'à une heure annoncée (« Je rentre à 18 h ») ; « Je rentre » remet chaque pièce sur son programme.
- **Préchauffage anticipé** (actif par défaut, avance de 2 h au plus, réglable de 1 à 4 h) : la passerelle regarde
  le prochain changement d'ambiance (programme, fin d'une Absence, retour annoncé). S'il demande plus de chaud
  (ou plus de frais en clim) et que la pièce mettra au moins ce temps à y arriver, elle l'applique dès maintenant
  (la pièce affiche « préchauffage pour l'heure prévue »). Une fois commencé, le préchauffage continue jusqu'à l'heure prévue.
- Temps de montée : 15 min par degré en chauffage, 10 en clim au départ, puis **appris pour chaque pièce** :
  à chaque montée d'au moins 1 °C jusqu'à la consigne, la passerelle mesure les minutes par degré (hors marge météo)
  et les lisse (30 % pour la nouvelle mesure). L'écran de la pièce affiche la vitesse apprise ;
  **météo** : +25 % sous 8 °C dehors, +50 % sous 0 °C (en clim : au-dessus de 32 et 38 °C).
- Pas de préchauffage vers une ambiance plus fraîche (Nuit), ni sans température mesurée dans la pièce.
- Géolocalisation (départ et retour détectés par le téléphone) : prévue plus tard, en option.

Base : migrations `20261112000000_solea_climate_smart.sql` (colonnes `preheat`, `preheat_max` de `climate_settings`)
et `20261113000000_solea_climate_learning.sql` (`heat_rate`, `cool_rate` de `climate_zones`).

## Absence automatique (géolocalisation, optionnelle)

- Le gestionnaire l'active dans **Chauffage et clim → Températures intelligentes** (il faut la position du logement)
  et choisit le rayon « à la maison » (200 m, 500 m, 1 km ou 2 km ; 300 m par défaut).
- Chaque membre décide sur son téléphone : **Partager ma présence depuis ce téléphone**. Le téléphone envoie sa position
  approximative ; le serveur (`report_presence`) ne garde que « à la maison » ou « parti » et la distance arrondie à 50 m,
  **jamais la position**. Couper le partage efface la ligne.
- Tous les membres qui partagent sont partis depuis 10 minutes : la passerelle met la maison en **Absence** (sauf si une
  ambiance a été choisie à la main) et prévient. Dès que l'un d'eux revient : retour au programme (avec le préchauffage).
- Limite actuelle : la position est envoyée quand Solea est ouverte (ou tourne encore en arrière-plan). Le suivi
  application fermée demandera une autorisation « toujours » et sera ajouté plus tard.

Base : migration `20261114000000_solea_presence.sql` (`geo_enabled`, `geo_radius`, `geo_away`, table `member_presence`, fonction `report_presence`).
