# Solea Boîtier vidéo

Fait tourner le boîtier vidéo de Solea sur la box Home Assistant : vos caméras et visiophones
marchent dans Solea même quand le PC est éteint (direct, son, micro, orientation, carte mémoire).

## Installation
1. Boutique des modules complémentaires : le dépôt FlowIT Smart est déjà ajouté (module
   FlowIT Bridge). Rechargez, puis installez « Solea Boîtier vidéo ».
2. Onglet Configuration : collez la clé secrète Supabase et l'identifiant du « Boîtier vidéo »
   (Solea > Paramètres > Intégrations).
3. Démarrez le module, puis regardez l'onglet Journal : `udi.online` = caméra trouvée.

## Important
- Un seul boîtier vidéo à la fois par logement : si le module tourne, fermez le boîtier du PC
  et retirez son raccourci du dossier « Démarrage » de Windows.
- Le relais vidéo n'écoute que sur la box (aucun port à ouvrir sur la box Internet).
