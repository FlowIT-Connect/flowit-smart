# Piloter une vraie maison avec FlowIT Smart

Ce qui marche déjà : l'application en ligne (https://app.solea-dz.com/)
et sa base Supabase. Il manque un petit boîtier **dans la maison** qui parle aux appareils :
c'est **Home Assistant**, avec le module **FlowIT Bridge** qui le relie à l'application.

```
Téléphone (FlowIT Smart) ⇄ Internet (Supabase) ⇄ Box Home Assistant + FlowIT Bridge ⇄ ampoules, prises…
```

> **Pas encore de box ?** Pour tester des prises et ampoules Tuya / Smart Life tout de suite,
> sans Home Assistant, suivez [TUYA_SANS_BOX.md](TUYA_SANS_BOX.md) (passerelle sur un PC, via le cloud Tuya).

## 1. Le matériel à acheter

| Quoi | Conseil | Prix indicatif |
|---|---|---|
| Box Home Assistant | **Home Assistant Green** (prête à brancher) ou Raspberry Pi 5 (4 Go) + carte microSD 64 Go + alimentation officielle | 100 à 130 € |
| Câble Ethernet | La box se branche sur la box Internet | 5 € |
| Premiers appareils Wi-Fi | Prises ou ampoules compatibles **Tuya / Smart Life** (faciles à trouver), ou modules **Shelly** | 10 à 20 € pièce |
| *Plus tard* : clé Zigbee | **Home Assistant Connect ZBT-1** ou SONOFF ZBDongle‑E, puis ampoules/prises/capteurs Zigbee (IKEA, Sonoff, Aqara) | 25 à 40 € |

Conseil : commencez par la box et 2 prises Wi-Fi. Le Zigbee vient ensuite.

## 2. Installer Home Assistant (une fois)
- **Home Assistant Green** : brancher le câble Ethernet et l'alimentation, attendre 10 minutes.
- **Raspberry Pi** : sur un ordinateur, installer *Raspberry Pi Imager*, choisir
  *Other specific-purpose OS > Home assistants > Home Assistant OS*, écrire la carte,
  la mettre dans le Pi, brancher Ethernet + alimentation, attendre 20 minutes.

Puis, sur un ordinateur ou téléphone **connecté au même Wi-Fi**, ouvrir
http://homeassistant.local:8123 et créer le compte Home Assistant.

## 3. Ajouter les appareils dans Home Assistant
- **Tuya / Smart Life** : appairer d'abord les appareils dans l'appli *Smart Life*, puis dans
  Home Assistant : Paramètres > Appareils et services > Ajouter une intégration > **Tuya**.
- **Shelly** : souvent détectés tout seuls (Paramètres > Appareils et services > « Découvert »).
- **Zigbee** (avec la clé) : brancher la clé, puis ajouter l'intégration **Zigbee Home Automation (ZHA)**
  et appairer chaque appareil (« Ajouter un appareil »).

Vérifier que chaque appareil s'allume / s'éteint **depuis Home Assistant** avant de continuer.

## 4. Relier Home Assistant à FlowIT Smart
1. Dans l'application FlowIT Smart : créer son compte et sa maison si ce n'est pas fait, puis
   **Paramètres > Intégrations > Ajouter > Home Assistant**. Copier l'**identifiant** affiché.
2. Sur supabase.com, projet FlowIT : **Project Settings > API Keys**, copier la clé
   **service_role** (ou *secret*). Elle donne tous les droits : ne la donnez à personne,
   ne la collez que dans Home Assistant.
3. Dans Home Assistant, ouvrir ce lien (bouton « Ajouter le dépôt ») :
   https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2Fflowit-connect%2Fflowit-smart
   (ou : Paramètres > Modules complémentaires > Boutique > ⋮ > Dépôts > coller
   `https://github.com/flowit-connect/flowit-smart`).
4. Dans la boutique, ouvrir **FlowIT Bridge** > **Installer** (quelques minutes).
5. Onglet **Configuration** : coller la clé et l'identifiant, **Enregistrer**.
   Onglet **Info** : **Démarrer**.
6. Onglet **Journal** : la ligne `home_assistant.connected` doit apparaître.

Les appareils apparaissent alors dans l'application (rubrique Appareils). Rangez-les par pièce,
puis testez : allumer une prise depuis le téléphone, **même hors de la maison** (en 4G).

### Essayer avant d'acheter des appareils
Dans la configuration du module, activer **Mode simulateur** : 10 appareils fictifs
apparaissent dans l'application. Le désactiver ensuite pour piloter les vrais.

## En cas de problème
| Symptôme | Que faire |
|---|---|
| Journal : `Variable d'environnement manquante` | La clé ou l'identifiant n'est pas rempli dans Configuration |
| Journal : erreur 401 / `Invalid API key` | Mauvaise clé : recopier la clé **service_role** (pas la publishable) |
| Aucun appareil dans l'application | Vérifier que l'identifiant vient bien de la maison ouverte dans l'app |
| Commande « échouée » | L'appareil ne répond pas dans Home Assistant : le tester d'abord là-bas |

Installation avancée (Docker, sans Home Assistant OS) : voir [INSTALLATION.md](INSTALLATION.md).
