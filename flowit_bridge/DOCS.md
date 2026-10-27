# FlowIT Bridge

Relie cette box Home Assistant à l'application **FlowIT Smart** : les appareils de
Home Assistant apparaissent dans l'application et obéissent à ses commandes, scènes et
automatisations. Aucun port n'est ouvert vers Internet.

## Configuration
1. **Clé secrète Supabase** : supabase.com > projet FlowIT > Project Settings > API Keys >
   clé `service_role` (ou `secret`). Ne la partagez avec personne.
2. **Identifiant d'intégration** : dans l'application, Paramètres > Intégrations > Ajouter >
   Home Assistant, puis copier l'identifiant affiché.
3. Enregistrer, puis **Démarrer**. L'onglet **Journal** doit afficher `home_assistant.connected`.

Pour essayer sans matériel, activer **Mode simulateur** : 10 appareils fictifs apparaissent.

Guide complet : https://github.com/flowit-connect/flowit-smart/blob/main/docs/MAISON_REELLE.md
