# Serrures et contrôles d'accès TTLock dans Solea

La passerelle Solea (FlowIT Bridge, sur votre PC) parle au **cloud TTLock** avec votre
compte développeur. Elle s'ajoute au mode Tuya : vos prises, rideaux et serrures
apparaissent dans la même application.

```
Téléphone (Solea) ⇄ Supabase ⇄ PC (FlowIT Bridge) ⇄ cloud TTLock ⇄ (passerelle G2/G3) ⇄ serrure
```

## Ce qui marche, avec ou sans passerelle TTLock

| Fonction | Sans passerelle G2/G3 | Avec passerelle G2/G3 |
|---|---|---|
| Voir le boîtier, sa batterie | Oui (mise à jour quand l'app TTLock se connecte en Bluetooth) | Oui |
| **Créer un code d'accès** (unique, période, permanent) | **Oui** : le code est calculé par TTLock et la serrure le reconnaît hors ligne | Oui |
| Historique des passages | Oui, mis à jour quand l'app TTLock se connecte à la serrure | Oui, en direct |
| **Partager l'accès** avec une personne (clé électronique), pour toujours ou entre deux dates | **Oui** : elle ouvre avec l'app TTLock en Bluetooth | Oui |
| **Désactiver / réactiver** un accès partagé, changer ses dates, le supprimer | **Oui** | Oui |
| Ouvrir / fermer **devant la porte** (Bluetooth, app Android Solea) | **Oui** | Oui |
| Ouvrir la porte à distance | Non | **Oui**, avec confirmation |
| État ouvert / fermé | Non | Oui |

La passerelle Solea détecte toute seule si la serrure a une passerelle TTLock : le bouton
« Ouvrir à distance » n'apparaît que dans ce cas.

## Sécurité (à lire)
- Une serrure est **bloquée par défaut** dans Solea. Seul le **propriétaire** de la maison
  peut l'activer (fiche de l'appareil > **Activer le contrôle d'accès**).
- Une fois activée, seuls le propriétaire et les **administrateurs** peuvent créer des codes
  ou ouvrir, et **toujours à la main** : jamais par une scène ni une automatisation.
- Chaque activation et chaque commande sont inscrites au **journal** avec leur auteur.
- Les codes ne sont visibles que par le propriétaire et les administrateurs. Ils
  n'apparaissent jamais dans les journaux de la passerelle.
- Un code créé reste valable dans la serrure même si vous bloquez à nouveau l'appareil
  dans Solea. Pour supprimer un code avant sa fin, passez par l'app TTLock
  (Codes > le code > Supprimer), près de la serrure.

## Ouvrir devant la porte (Bluetooth, app Android)
Sans passerelle TTLock, seul un téléphone tout proche peut ouvrir, en Bluetooth. La version
web de Solea ne le peut pas : il faut l'**app Android Solea** (fichier `Solea.apk`, compilé
par GitHub Actions, workflow « Construire l'app Android »).
1. Fiche de la serrure > carte **Devant la porte (Bluetooth)** > **Ouvrir** ou **Fermer**.
2. Le téléphone doit être à moins de 2 mètres, Bluetooth activé. Android demande une fois
   l'autorisation « Appareils à proximité ».

Sécurité : l'app reçoit la **clé Bluetooth** de la serrure (celle du compte administrateur
TTLock de la passerelle). Elle n'est donnée qu'au propriétaire et aux administrateurs, une
fois la serrure activée. Chaque lecture de la clé et chaque ouverture sont inscrites au
journal. Elle reste en mémoire seulement jusqu'à la déconnexion, et n'est jamais écrite sur
le téléphone. Ne nommez administrateurs que des personnes de confiance.

## 1. Vérifier le compte TTLock (une fois)
1. Dans l'**app TTLock** du téléphone, le boîtier doit apparaître et vous devez en être
   **administrateur** (c'est vous qui l'avez ajouté).
2. Sur **open.ttlock.com** (votre compte développeur) > **Application** : votre application doit
   être **approuvée** (statut « Approved »). Vous y voyez le **Client ID** et le **Client Secret**.
   **Ne les envoyez à personne** : vous les taperez seulement sur votre PC à l'étape 3.

## 2. Mettre à jour la base Solea (une fois)
La migration `supabase/migrations/20261030000000_solea_access_control.sql` ajoute l'activation
des serrures et la table des codes. Elle doit être appliquée sur Supabase avant le premier test
(Claude peut le faire avec votre accord).

## 3. Ajouter TTLock à la passerelle du PC
1. Télécharger la nouvelle version du code (bouton vert **Code > Download ZIP** sur GitHub),
   l'extraire, et recopier votre ancien fichier `bridge\.env` dans le nouveau dossier `bridge`.
2. Double-cliquer sur **`bridge\Configurer-FlowIT-Tuya.cmd`**. Gardez les réponses Tuya
   (appuyez sur Entrée), puis à la question **« Serrures / contrôles d'accès TTLock »** tapez `o` :
   - **Client ID** et **Client Secret** : ceux d'open.ttlock.com ;
   - **Identifiant** et **mot de passe** de l'**app TTLock** (le compte qui gère la serrure).
     Le mot de passe n'est pas enregistré en clair : seule son empreinte MD5 l'est, comme
     l'exige TTLock.
3. L'assistant vérifie tout de suite et affiche vos serrures, par exemple :
   `Boîtier entrée (batterie 82 %, sans passerelle : codes d'accès seulement)`.
4. Relancer **`Demarrer-FlowIT-Tuya.cmd`**. Dans la fenêtre, une ligne `ttlock.inventory`
   indique le nombre de serrures trouvées.

## 4. Tester dans l'application
1. Recharger Solea : le boîtier apparaît dans **Appareils** (« Sans pièce » au début).
2. Ouvrir sa fiche > **Activer le contrôle d'accès** > confirmer.
3. **Créer un code** > choisir **Unique** > **Créer le code**. Le code s'affiche en grand
   après 1 à 3 secondes.
4. Sur le clavier du boîtier : taper le code puis valider (touche **#** ou **cadenas**,
   selon le modèle). La porte doit s'ouvrir.
5. Ouvrir l'app TTLock près du boîtier : l'historique se synchronise, puis apparaît dans
   Solea au plus tard 5 minutes après (« Derniers passages »).

### Partager l'accès avec quelqu'un
1. La personne installe l'**app TTLock** et crée son compte (téléphone ou e-mail).
2. Dans Solea, fiche du boîtier > **Accès partagés** > **Partager l'accès** : tapez son compte
   TTLock, un nom (ex. « Karim »), et activez **Programmer** pour limiter l'accès entre deux dates.
3. La personne reçoit l'accès dans son app TTLock et ouvre en Bluetooth devant la porte.
4. Le bouton **⋮** à côté de son nom permet de **Désactiver** (pause), **Réactiver**,
   **Programmer les dates** ou **Supprimer l'accès**. La désactivation prend effet dès que son
   app TTLock se connecte à Internet.

À savoir sur les types de codes TTLock :
- **Unique** : une seule fois, dans les **6 heures**.
- **Période** : entre deux dates, à l'heure près.
- **Permanent** : toujours, mais il faut le taper **une première fois dans les 24 heures**.

## En cas de problème
| Message dans la fenêtre de la passerelle | Que faire |
|---|---|
| `Identifiant ou mot de passe TTLock incorrect` | Relancer l'assistant, retaper l'identifiant de l'app TTLock (téléphone avec indicatif ou e-mail) |
| `l'application TTLock Open Platform n'est pas encore approuvée` | Attendre l'approbation sur open.ttlock.com |
| `L'heure de ce PC est fausse` | Paramètres Windows > Heure > « Régler l'heure automatiquement » |
| `Aucune serrure` | Le compte saisi n'est pas celui qui a ajouté la serrure dans l'app TTLock |
| `Ce compte TTLock n'a pas les droits d'administrateur` | Créer les codes avec le compte administrateur de la serrure |
| Code refusé par la serrure | Vérifier l'heure de la serrure dans l'app TTLock (Paramètres > Heure de la serrure) |

Réglage facultatif dans `bridge\.env` : `TTLOCK_POLL_SECONDS` (relecture du cloud TTLock,
300 s par défaut) et `TTLOCK_API_URL` (par défaut `https://euapi.ttlock.com`).
