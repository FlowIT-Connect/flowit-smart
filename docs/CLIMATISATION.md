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
- **Oscillation**, **Mode nuit**, **Mode éco**, **Détection fenêtre ouverte**, **Verrouillage enfant**.
- **Activité** (lecture seule) : chauffe en cours, refroidit, en attente.

## Si un appareil manque une fonction

Dans la fenêtre de la passerelle, cherchez la ligne de l'appareil et envoyez-nous sa
catégorie et la liste de ses codes Tuya : on ajoute la correspondance.

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
