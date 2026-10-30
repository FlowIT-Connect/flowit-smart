# Ajouter un appareil depuis Solea

Onglet **Appareils** → bouton **Ajouter un appareil** (propriétaire ou administrateur).
Vous choisissez un nom et une pièce : l'appareil arrive dans Solea déjà rangé.

La passerelle Solea doit tourner sur le PC (`bridge\Lancer-Passerelle.cmd`) : c'est elle
qui parle aux clouds Tuya et TTLock, l'application ne connaît aucun de leurs mots de passe.

## Serrure TTLock (app Android)

1. Devant la serrure, Bluetooth activé, touchez **Rechercher la serrure** et réveillez la
   serrure en touchant son clavier.
2. Touchez la serrure trouvée. Le téléphone l'installe en Bluetooth, puis la passerelle
   l'enregistre sur votre compte TTLock (celui de `ttlock.txt`).
3. Ouvrez sa fiche et activez-la (propriétaire) pour l'ouvrir et créer des codes.

Seule une serrure **neuve ou réinitialisée** apparaît dans la recherche. Une serrure déjà
installée dans l'app TTLock reste visible dans Solea sans rien faire (la passerelle relit le
compte TTLock toutes les 5 minutes). Si l'enregistrement échoue, Solea remet la serrure en
mode installation pour pouvoir réessayer.

## Appareil Tuya / Smart Life

Tuya ne permet le couplage Wi-Fi ou Bluetooth que dans ses propres applications. Solea
vous guide :

1. Touchez **Ouvrir Smart Life** : Solea prévient la passerelle, puis ouvre Smart Life.
2. Ajoutez l'appareil comme d'habitude (bouton **+**).
3. Revenez dans Solea : pendant 5 minutes, la passerelle relit Smart Life toutes les
   10 secondes. Le premier appareil apparu reçoit le nom et la pièce choisis.

Smart Life doit être le compte lié au projet Tuya (voir [TUYA_SANS_BOX.md](TUYA_SANS_BOX.md),
« Link App Account »), sinon la passerelle ne voit pas le nouvel appareil.

## Réglages de la passerelle (facultatifs, dans `.env`)

| Variable | Défaut | Rôle |
|---|---|---|
| `PAIRING_SCAN_SECONDS` | 300 | Durée de recherche d'un nouvel appareil Smart Life |
| `PAIRING_RETRY_SECONDS` | 10 | Intervalle entre deux relectures pendant la recherche |

## Base de données

Migration `supabase/migrations/20261031000000_solea_pairing.sql` : table `pairing_requests`
(demandes d'ajout, clé de serrure illisible depuis l'application et effacée après
traitement) et fonction `request_pairing()` (propriétaire ou administrateur, journalisée).
