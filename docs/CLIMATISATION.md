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
