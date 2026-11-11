# FlowIT Bridge (passerelle Solea)

Deux usages, au choix dans **Mode** :

## Mode `tuya_cloud` : la passerelle Solea sur la box (PC inutile)

La passerelle Solea complète tourne sur la box Home Assistant, toujours allumée :
appareils Smart Life (et Zigbee Smart Life), serrures TTLock, robot aspirateur yeedi.
Avec **Afficher les appareils Solea dans Home Assistant** (`ha_mqtt`) et le module
**Mosquitto broker** démarré, ils apparaissent aussi dans Home Assistant (intégration MQTT),
sans utilisateur ni mot de passe MQTT à créer.

Réglages : les mêmes que dans le fichier `.env` de la passerelle du PC (Tuya, TTLock) et
`yeedi\.env` du module yeedi (mots de passe en MD5). **Arrêtez la passerelle du PC** avant
de démarrer ce module : deux passerelles pour la même intégration se gêneraient.

Onglet **Journal** : `tuya.inventory`, `ttlock.inventory`, `yeedi.inventory`, puis
`ha_mqtt.published`.

**Télécommande Broadlink (RM4 Pro, RM4 mini)** : ajoutez-la d'abord dans Home Assistant
(Paramètres > Appareils et services, « Broadlink » découvert > Configurer). Le module la
reprend tout seul (`bridge.ha_import`, puis `home_assistant.inventory … broadlink: 1`) :
sa température et son humidité arrivent dans Solea, et les touches s'apprennent depuis
Solea (fiche du Broadlink > Apprendre une touche). Clim : « Choisir la marque de ma clim »
(bibliothèque de 395 télécommandes, modes et vitesses sans apprentissage, codes gardés dans
/data/broadlink). Guide : docs/BROADLINK.md.

## Mode `home_assistant` : les appareils de ce Home Assistant dans Solea

1. **Clé secrète Supabase** : supabase.com > projet > Project Settings > API Keys >
   clé `service_role` (ou `secret`). Ne la partagez avec personne.
2. **Identifiant d'intégration** : dans l'application, Paramètres > Intégrations > Ajouter >
   Home Assistant, puis copier l'identifiant affiché.
3. Enregistrer, puis **Démarrer**. L'onglet **Journal** doit afficher `home_assistant.connected`.

Pour essayer sans matériel : **Mode** = `simulator`.

Guides : docs/MAISON_REELLE.md et docs/HOME_ASSISTANT_MQTT.md du dépôt.
