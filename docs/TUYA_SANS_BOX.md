# Tester des appareils Tuya / Smart Life sans box

Pour commencer sans acheter de box Home Assistant : la passerelle **FlowIT Bridge** tourne
sur votre **PC Windows** et parle directement au **cloud Tuya**.

```
Téléphone (FlowIT Smart) ⇄ Supabase ⇄ PC (FlowIT Bridge) ⇄ cloud Tuya ⇄ prises, ampoules Wi-Fi
```

À savoir avant de commencer :
- Il faut **Internet** (tout passe par le cloud Tuya) et le **PC doit rester allumé**,
  avec la fenêtre FlowIT Bridge ouverte, pendant les tests.
- Un changement fait **à la main** ou dans Smart Life apparaît dans FlowIT Smart en **30 secondes**
  au plus. Une commande envoyée depuis FlowIT Smart est confirmée en 1 à 3 secondes.
- Plus tard, avec une box Home Assistant, on passe au mode décrit dans [MAISON_REELLE.md](MAISON_REELLE.md).

## 1. Les appareils à acheter

| Quoi | Conseil |
|---|---|
| Prises Wi-Fi | Logo **Tuya** ou **Smart Life**, si possible avec mesure de consommation (Nous A1T, Gosund, Avatto…) |
| Ampoules Wi-Fi | E27 « RGB + CCT » (couleur + blanc) compatibles **Smart Life** |
| À éviter pour l'instant | Produits **Zigbee** (ils demandent un hub) et **Bluetooth** seulement |

Le Wi-Fi de la maison doit proposer du **2,4 GHz** (presque toutes les box le font).

## 2. Ajouter les appareils dans Smart Life
1. Installer l'application **Smart Life** sur le téléphone et créer un compte.
2. Ajouter chaque prise / ampoule (bouton **+**), choisir le Wi-Fi 2,4 GHz.
3. Vérifier qu'elle s'allume et s'éteint **depuis Smart Life**.

## 3. Créer le projet cloud Tuya (une fois, gratuit)
1. Créer un compte sur **https://platform.tuya.com** (compte développeur, différent de Smart Life).
2. Menu **Cloud > Development > Create Cloud Project** :
   - *Industry* : Smart Home — *Development Method* : Smart Home
   - *Data Center* : **Central Europe Data Center** (celui des comptes Smart Life créés en Algérie)
3. À l'écran des services, garder ceux proposés (**IoT Core**, **Authorization Token Management**,
   **Smart Home Basic Service**) et valider.
4. Onglet **Devices > Link App Account > Add App Account** : un QR code s'affiche.
   Dans Smart Life : **Moi** > icône de scan en haut à droite > scanner le QR code > confirmer.
   Vos appareils apparaissent alors dans l'onglet Devices.
5. Onglet **Overview** : vous y voyez l'**Access ID** et l'**Access Secret**.
   **Ne les envoyez à personne** (ni par message ni par e-mail) : vous les taperez seulement sur votre PC à l'étape 5.

> L'essai gratuit d'« IoT Core » dure un mois. Avant la fin : **Cloud > Cloud Services > IoT Core >
> Extend Trial Period** (gratuit, à refaire quand Tuya le demande). Sinon la passerelle affiche
> « Abonnement IoT Core expiré ».

## 4. Créer l'intégration dans FlowIT Smart
Dans l'application : **Paramètres > Intégrations > Ajouter**, fournisseur **Tuya**, puis **Créer**.
Un **identifiant** s'affiche : copiez-le (vous le collerez à l'étape 5).

Vous aurez aussi besoin de la clé **service_role** de Supabase : supabase.com > projet FlowIT >
**Project Settings > API Keys** > clé *service_role* (ou *secret*). Elle donne tous les droits :
ne la collez que dans l'assistant, sur votre PC.

## 5. Lancer la passerelle sur le PC (Windows)
1. Installer **Node.js** version **LTS** : https://nodejs.org/fr/download (suivant, suivant, terminer).
2. Télécharger le code : https://github.com/FlowIT-Connect/flowit-smart > bouton vert **Code** >
   **Download ZIP**, puis clic droit sur le fichier > **Extraire tout**.
3. Ouvrir le dossier extrait, puis le dossier **bridge**, et double-cliquer sur
   **Demarrer-FlowIT-Tuya.cmd**. (Si Windows affiche « Windows a protégé votre ordinateur » :
   **Informations complémentaires > Exécuter quand même**.)
4. La première fois, l'assistant pose 5 questions. Pour coller : **clic droit** dans la fenêtre.
   Les clés restent cachées pendant la saisie, c'est normal.
   1. l'identifiant d'intégration (étape 4)
   2. la clé service_role de Supabase
   3. l'Access ID Tuya
   4. l'Access Secret Tuya
   5. le data center : tapez **1** (Central Europe)
5. L'assistant vérifie tout de suite et affiche la liste de vos appareils Tuya.
6. La passerelle démarre : la ligne `tuya.inventory` puis `bridge.inventory_synced` doit apparaître.
   **Laissez la fenêtre ouverte.**

Dans FlowIT Smart, les appareils apparaissent dans **Appareils**. Rangez-les par pièce,
puis testez : allumer une prise depuis le téléphone, même en 4G hors de la maison.

Pour changer une clé plus tard : fermer la fenêtre, double-cliquer sur
**Configurer-FlowIT-Tuya.cmd**, puis relancer **Demarrer-FlowIT-Tuya.cmd**.

*Mac / Linux* : dans le dossier `bridge`, `npm ci --omit=dev`, puis `npm run configurer`, puis `npm run local`.

## Ce qui est pris en charge
| Appareil Tuya | Dans FlowIT Smart |
|---|---|
| Prise, multiprise, interrupteur | marche / arrêt (une commande par prise), puissance (W), énergie (kWh) |
| Ampoule, ruban LED | marche / arrêt, luminosité, blanc chaud ↔ froid, couleur |
| Rideau / volet | boutons Ouvrir, Stop, Fermer, et position 0 à 100 % si le moteur la donne |
| Thermostat | consigne, température mesurée |
| Capteurs | température, humidité, batterie, porte (ouverte / fermée), mouvement |
| Serrure, coffre | visibles mais **bloquées** (sécurité) |

Les autres appareils (télécommande infrarouge, caméra…) sont ignorés pour l'instant.

## En cas de problème
| Message | Que faire |
|---|---|
| `Access ID ou Access Secret incorrect` | Relancer **Configurer-FlowIT-Tuya.cmd** et recopier les deux valeurs de l'onglet Overview |
| `Connexion OK mais aucun appareil` / `tuya.no_devices` | Refaire **Link App Account** (étape 3.4) ; vérifier que le data center est **Central Europe** |
| `Abonnement « IoT Core » expiré` | platform.tuya.com > Cloud Services > IoT Core > **Extend Trial Period** |
| `Intégration introuvable` | Recopier l'identifiant affiché dans FlowIT Smart (étape 4) |
| Commande « délai dépassé » | L'appareil est-il en ligne dans Smart Life ? Wi-Fi 2,4 GHz correct ? |
| `Node.js n'est pas installé` | Installer la version LTS (étape 5.1) puis relancer |
