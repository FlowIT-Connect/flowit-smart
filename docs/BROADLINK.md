# Télécommande Broadlink (RM4 Pro, RM4 mini) dans Solea

Le Broadlink pilote en infrarouge tout ce qui a une télécommande (clim, télé, décodeur,
ventilateur…). Solea le reçoit **par Home Assistant**, qui le gère en local (sans le cloud
Broadlink), puis par le module **FlowIT Bridge** de la box.

## 1. Ajouter le Broadlink dans Home Assistant (une seule fois)

1. Le Broadlink doit être sur le même réseau Wi-Fi que la box, déjà configuré dans l'app
   Broadlink. Dans l'app Broadlink, l'option **« Verrouiller l'appareil »** doit être
   désactivée (sinon HA ne peut pas lui parler).
2. Home Assistant > **Paramètres > Appareils et services** : « Broadlink » apparaît dans
   **Découverts** > **Configurer** > Valider. (Sinon : **Ajouter une intégration** >
   Broadlink > adresse IP du RM4 Pro.)
3. HA crée `remote.<nom>` et, si le câble capteur est branché, la température et
   l'humidité.

## 2. Mettre à jour le module FlowIT Bridge (version 2.2.0)

Paramètres > Modules complémentaires > FlowIT Bridge > **Mettre à jour** (ou Reconstruire),
puis **Redémarrer**. Rien à saisir : en mode `tuya_cloud`, le module reprend les appareils
de l'intégration Broadlink (réglage `ha_integrations`, `broadlink` par défaut).

Journal attendu : `bridge.ha_import`, puis `home_assistant.inventory … broadlink: 1`.
Le Broadlink apparaît dans Solea avec sa température et son humidité.

## 3. Clim : choisir sa télécommande dans la bibliothèque (le plus simple)

Comme l'app Broadlink, Solea connaît déjà les télécommandes de 395 clims (Daikin, Midea, Gree,
LG, Samsung, Hyundai, Hisense…). Fiche du Broadlink > **Choisir la marque de ma clim** :

1. chercher la marque, puis toucher **Essayer** sur une télécommande : le Broadlink envoie
   Froid 24° ;
2. si la clim bipe ou démarre : **Oui, garder celle-ci**. Sinon **Non, essayer la suivante**
   (Solea éteint la clim et passe à la suivante).

La fiche **Clim** a alors tous les modes (froid, chaud, déshumidification, ventilation, auto
selon le modèle), toutes les températures et les vitesses de ventilation (et l'oscillation
quand la télécommande l'a), sans rien apprendre. Les touches déjà apprises hors réglage
(ex. « allumé ») restent en boutons. **Retirer** revient aux touches apprises.

Les codes viennent de la bibliothèque libre SmartIR (licence MIT,
https://github.com/smartHomeHub/SmartIR) : la box télécharge ceux de la télécommande
choisie une seule fois, puis les garde (`/data/broadlink` du module). Index régénéré par
`tools/ir_climate_index.sh`.

## 4. Apprendre les touches depuis Solea

Fiche du Broadlink > **Apprendre les touches d'une télécommande** :

1. choisir l'appareil (Télé, Clim, Décodeur, Ventilateur ou un autre nom) et la touche ;
2. toucher **Apprendre**, puis appuyer sur cette touche de la vraie télécommande, pointée
   vers le Broadlink (à moins d'un mètre), dans les 30 secondes ;
3. Solea confirme et propose la touche suivante. Appui long sur une touche cochée pour
   l'oublier.

Chaque appareil appris devient un appareil Solea (« Télé », « Clim »…) avec ses touches, à
ranger dans une pièce et à utiliser dans les scènes et automatisations. Les touches déjà
apprises dans Home Assistant (`remote.learn_command`) sont reprises aussi.

### Clim : un vrai thermostat

Si les touches de la clim suivent ces noms, Solea en fait un thermostat (mode + consigne),
utilisable par les ambiances, programmes, fenêtre ouverte et préchauffage :

| Touche | Ce qu'elle envoie |
| --- | --- |
| `off` | éteindre (obligatoire) |
| `cool_22`, `cool_24`… | froid à 22 °C, 24 °C… |
| `heat_20`, `heat_22`… | chaud |
| `dry`, `fan_only`, `auto` | déshumidifier, ventilation, auto |

Pour apprendre `cool_22` : régler la télécommande de la clim sur Froid 21 °C, lancer
l'apprentissage, puis appuyer sur **température +** (la télécommande envoie tout le
réglage, Froid 22 °C). Solea choisit la température apprise la plus proche de la consigne.
La température de la pièce vient du capteur du Broadlink.

L'infrarouge ne renvoie aucun état : Solea affiche le dernier ordre envoyé. Si quelqu'un
utilise la vraie télécommande, l'affichage de Solea ne le sait pas.

## Limites

- Infrarouge seulement (pas encore la radio 433 MHz du RM4 Pro).
- Les codes restent dans Home Assistant ; seuls les noms des touches vont dans Solea.
- Passerelle sur PC (hors box) : `HA_IMPORT_PLATFORMS=broadlink`, `HA_URL`, `HA_TOKEN`, et
  `HA_CONFIG_DIR` (dossier de configuration de HA) pour lire les touches apprises.
