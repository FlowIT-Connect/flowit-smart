# Voir les appareils Solea dans Home Assistant

La passerelle Solea peut publier tous ses appareils dans Home Assistant : le robot yeedi,
les serrures TTLock, les appareils Smart Life et leurs sous-appareils Zigbee (détecteur de
présence…). Ils apparaissent tout seuls dans l'intégration **MQTT** de Home Assistant.

## Ce qui apparaît

| Appareil Solea | Dans Home Assistant |
| --- | --- |
| Robot yeedi | Aspirateur (démarrer, pause, arrêt, retour à la base, puissance), débit d'eau, batterie |
| Serrure TTLock | Batterie et dernière ouverture, **lecture seule** (l'ouverture reste dans Solea) |
| Détecteur de présence | Présence, luminosité, sensibilité et distances (réglages) |
| Prise, interrupteur | Interrupteur, puissance, énergie |
| Rideau | Volet (ouvrir, fermer, stop, position) |

La carte du robot et le nettoyage par pièce restent dans Solea.

## Mise en place (une seule fois)

1. Dans Home Assistant : **Paramètres › Modules complémentaires › Boutique**, installer
   **Mosquitto broker**, puis **Démarrer**.
2. **Paramètres › Personnes › Utilisateurs** : créer un utilisateur `solea` avec un mot de
   passe (il sert seulement à MQTT).
3. **Paramètres › Appareils et services** : Home Assistant propose l'intégration **MQTT**,
   cliquer sur **Configurer**.
4. Dans le fichier `bridge\.env` de la passerelle (ou un fichier `bridge\homeassistant.env`), ajouter (adresse de Home Assistant) :

   ```
   HA_MQTT_URL=mqtt://solea:MOTDEPASSE@192.168.1.50:1883
   ```

   Un caractère spécial du mot de passe s'écrit encodé (`@` → `%40`, `:` → `%3A`).
5. Relancer la passerelle. Dans sa fenêtre : `ha_mqtt.connected`, puis `ha_mqtt.published`.

Les appareils sont dans **Paramètres › Appareils et services › MQTT**.

## Bon à savoir

- Un ordre donné dans Home Assistant passe par la passerelle, avec les mêmes vérifications
  que l'application, et déclenche les automatisations Solea.
- Passerelle arrêtée : les appareils passent « indisponible » dans Home Assistant.
- Un appareil retiré de Solea disparaît aussi de Home Assistant.
