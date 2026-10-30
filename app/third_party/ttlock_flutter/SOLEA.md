# ttlock_flutter 0.3.8 (copie locale)

Module Bluetooth officiel TTLock (licence MIT, https://github.com/ttlock/ttlock_flutter),
copié tel quel depuis pub.dev avec une seule correction : `lib/ttremotekey.dart` est renommé
`lib/ttremoteKey.dart`. `ttlock.dart` l'importe sous ce nom, et la version publiée ne
compile donc pas sous Linux, dont les noms de fichiers sont sensibles à la casse.

`android/build.gradle` est aussi réécrit pour Gradle 9 et AGP 9, utilisés par l'application.
La version d'origine utilisait `jcenter()`, `lintOptions` et AGP 4.
