# Solea pour plusieurs logements : 5 appareils gratuits, puis déblocage payant

Chaque logement (appartement) a son propre compte Solea. L'inscription est obligatoire et
l'adresse e-mail doit être confirmée avant la première connexion (réglage Supabase
**Authentication › Sign In / Providers › Email › Confirm email** activé). L'écran de connexion
propose « Renvoyer l'e-mail de confirmation » si le message n'est pas arrivé.

## Ce que voit le résident

- Dans **Paramètres** et dans **Ajouter un appareil** : « Appareils : 3 / 5 ».
- À 5 / 5, l'ajout d'appareils est bloqué et le bouton **Débloquer plus d'appareils** envoie
  une demande à l'exploitant.
- Les appareils déjà installés continuent de marcher, même si un abonnement arrive à son terme.

La limite est vérifiée par la base de données (trigger `devices_limit_check`) : ni l'application
ni la passerelle ne peuvent la dépasser. Un appareil couplé alors que le logement est plein est
compté « en attente » par la passerelle et apparaît tout seul dès le déblocage.

## Ce que voit l'exploitant (vous)

**Paramètres › Exploitant Solea › Paiements** liste les demandes. Après avoir reçu le paiement
(versement, espèces…), appuyez sur **Paiement reçu**, choisissez le nombre d'appareils
(10, 20, 50, 100) et la durée (1, 3, 12 mois ou sans fin). Un renouvellement prolonge la date
de fin en cours. Le paiement en ligne (Chargily : CIB / Edahabia) viendra plus tard.

Pour donner l'accès « Paiements » à un compte, en SQL :

```sql
insert into public.platform_admins (user_id)
select id from auth.users where lower(email) = lower('adresse@exemple.dz');
```

Migration : `supabase/migrations/20261101000000_solea_plans.sql`.
