# Limites connues et suites

- **Clé service_role sur la passerelle** : elle donne tous les droits sur la base. Elle reste
  sur une machine du réseau local, jamais dans l'application. Évolution prévue : jetons de
  passerelle limités à une maison (Edge Function + JWT dédié).
- **Une seule passerelle par maison** doit avoir `RUN_AUTOMATIONS=true`, sinon les
  automatisations s'exécuteraient deux fois (les commandes, elles, ne peuvent pas être
  exécutées deux fois grâce à la réclamation atomique).
- **Couleur des lumières** : la confirmation tolère un petit écart, certaines ampoules
  arrondissent fortement les couleurs.
- **Liens e-mail sur mobile** : confirmation et mot de passe oublié ouvrent la version web ;
  le lien profond vers l'app mobile reste à configurer.
- **Invitations** : pas d'e-mail envoyé, l'administrateur partage le code d'invitation.
- **Notifications push, BLE, Matter direct, appairage depuis l'app** : non couverts ;
  l'appairage se fait dans Home Assistant / Zigbee2MQTT.
- **Appareils sensibles** (serrures, alarmes) : affichés mais commandes bloquées tant
  qu'une validation renforcée (code, biométrie) n'est pas développée.
- **Historique de capteurs** : seul l'état courant est stocké (pas de graphes).
