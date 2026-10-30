import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dz.flowit.flowit_smart"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Identifiant définitif sur Google Play : ne plus le changer après la 1re publication.
        applicationId = "com.soleadz.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Clé de publication (upload key Google Play), lue dans android/key.properties
    // ou dans les variables ANDROID_KEYSTORE_* (GitHub Actions). Voir docs/PUBLIER_SUR_LES_STORES.md.
    // Sans clé, la version release reste signée avec la clé debug (APK de test seulement).
    val keyProps = Properties().apply {
        val f = rootProject.file("key.properties")
        if (f.exists()) f.inputStream().use { load(it) }
    }
    fun keyValue(prop: String, env: String): String? =
        keyProps.getProperty(prop) ?: System.getenv(env)?.takeIf { it.isNotEmpty() }
    val storeFilePath = keyValue("storeFile", "ANDROID_KEYSTORE_PATH")

    signingConfigs {
        if (storeFilePath != null) {
            create("release") {
                storeFile = file(storeFilePath)
                storePassword = keyValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
                keyAlias = keyValue("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = keyValue("keyPassword", "ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
            // Le SDK Bluetooth TTLock ne supporte pas l'obfuscation R8.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
