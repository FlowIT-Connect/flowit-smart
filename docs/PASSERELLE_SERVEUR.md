# Une seule passerelle pour tous les logements (serveur ADEX)

Vos clients n'ont **jamais** de compte Tuya. C'est vous, l'installateur, qui ajoutez chaque
appareil Wi-Fi dans **votre** compte Smart Life (et chaque serrure dans votre compte TTLock).
La passerelle installée sur votre serveur voit tous ces appareils. Dans Solea, vous rangez
ensuite chacun dans le bon logement. Le résident le voit apparaître dans son application en
moins d'une minute.

```
Smart Life (votre compte)  ─┐
TTLock (votre compte)      ─┼─►  passerelle sur le serveur  ─►  Supabase  ─►  Solea du résident
                            │        (Docker, PLATFORM=true)
            vous, dans Solea : « Appareils à attribuer » › logement
```

## Installer un appareil chez un client

1. Chez le client, ajoutez l'appareil dans **votre** application Smart Life, sur le Wi-Fi du
   client, comme d'habitude.
2. Dans Solea : **Paramètres › Exploitant Solea › Appareils à attribuer**. L'appareil y
   apparaît moins d'une minute plus tard.
3. Appuyez sur **Attribuer**, tapez le nom du logement ou l'e-mail du résident, choisissez.

Un logement plein (5 appareils sans déblocage) est grisé : débloquez-le d'abord dans
**Paiements**. Pour déplacer ou retirer un appareil : menu **⋮** de l'appareil.

Dans un logement équipé ainsi, le bouton « Ajouter un appareil » du résident affiche
« Appareils installés par Solea » : il n'a rien à configurer.

## Installer la passerelle sur le serveur (une fois)

Il faut Docker sur le serveur (déjà le cas si ResidenceConnect y tourne en Docker).
Connectez-vous au serveur (SSH), puis :

```sh
git clone https://github.com/FlowIT-Connect/flowit-smart.git
cd flowit-smart/bridge
docker compose -f docker-compose.serveur.yml run --rm configurer
```

Aux questions :

- **1/5** : tapez `serveur`
- **2/5** : la clé `service_role` de Supabase (elle reste sur le serveur)
- **3/5 et 4/5** : l'Access ID et l'Access Secret de votre projet Tuya
- **5/5** : le data center (Central Europe)
- TTLock : `o` si vous gérez aussi des serrures

Puis démarrez :

```sh
docker compose -f docker-compose.serveur.yml up -d --build bridge
docker compose -f docker-compose.serveur.yml logs -f bridge     # Ctrl+C pour quitter le journal
```

Le journal doit afficher `platform.synced` avec le nombre d'appareils.

**Mettre à jour** plus tard : `git pull` puis la commande `up -d --build bridge`.

## Important

- **Arrêtez la passerelle de votre PC** avant de démarrer celle du serveur : deux passerelles
  sur le même compte se gêneraient. Vos appareils actuels restent dans votre logement, la
  passerelle du serveur les reprend sans doublon.
- **Tuya en version d'essai** : le projet gratuit est limité à 50 appareils et interdit l'usage
  commercial. Avant de vendre, passez à une offre payante sur platform.tuya.com (prix donné
  par Tuya après connexion).
- Comptez une passerelle **par compte installateur** : un seul compte Smart Life pour tous vos
  logements suffit.

Code : `bridge/src/platform.js`. Migration : `supabase/migrations/20261102000000_solea_platform_devices.sql`.
