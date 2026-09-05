import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// Resolve a signing value: key.properties first, then CI env vars, then null.
// Blank / whitespace-only values are treated as ABSENT (so an empty CI env var
// like STORE_FILE="" does not masquerade as a configured keystore).
fun signingVal(propKey: String, envKey: String): String? =
    (keystoreProperties.getProperty(propKey) ?: System.getenv(envKey))
        ?.trim()?.ifEmpty { null }

val hasKeystore = signingVal("storeFile", "STORE_FILE") != null &&
    signingVal("keyAlias", "KEY_ALIAS") != null

// Google Maps SDK key: a real key cannot be dart-define-injected the way
// other runtime config is — the native Maps SDK reads it from a manifest
// meta-data value at install time, so it has to be resolved here and injected
// as a manifest placeholder instead of ever being a literal in AndroidManifest.xml.
// Resolution order: MAPS_API_KEY env var (CI), then local.properties (each
// developer's own, git-ignored, per-checkout key) — never a repo default.
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}
val mapsApiKey: String? = (System.getenv("MAPS_API_KEY") ?: localProperties.getProperty("MAPS_API_KEY"))
    ?.trim()?.ifEmpty { null }
val hasMapsApiKey = mapsApiKey != null

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

android {
    namespace = "com.shauchmap.app"
    compileSdk = 36 // Keep this at 36 to satisfy the plugins!
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        if (hasKeystore) {
            create("release") {
                keyAlias = signingVal("keyAlias", "KEY_ALIAS")!!
                keyPassword = signingVal("keyPassword", "KEY_PASSWORD") ?: ""
                storeFile = file(signingVal("storeFile", "STORE_FILE")!!)
                storePassword = signingVal("storePassword", "STORE_PASSWORD") ?: ""
            }
        }
    }

    defaultConfig {
        applicationId = "com.shauchmap.app"
        minSdk = flutter.minSdkVersion
        targetSdk = 34 // Keep targetSdk at 34 so you don't inherit unneeded API 36 permission changes
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        // Debug builds and CI checks that never exercise live Maps rendering
        // get a harmless placeholder so they still compile without a real
        // key; a release build is blocked below if this is still the default.
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey ?: "MISSING_MAPS_API_KEY"
    }

    buildTypes {
        release {
            // FAIL CLOSED: never fall back to the debug certificate for a
            // release artifact. If the release keystore material is present we
            // use it; if not, we leave this null and the task-graph guard
            // below aborts any actual release assemble/bundle. (Previously this
            // silently used signingConfigs["debug"], so `flutter build apk
            // --release` with no key.properties produced a DEBUG-signed APK.)
            signingConfig = if (hasKeystore) signingConfigs.getByName("release") else null
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

// A real release build MUST be release-signed. If the release keystore is not
// configured (no key.properties and no STORE_FILE/KEY_ALIAS env), fail any
// build that assembles or bundles a release artifact — rather than emitting an
// APK/AAB signed with the debug certificate. Debug builds and Gradle sync are
// unaffected (they schedule no *Release assemble/bundle task).
gradle.taskGraph.whenReady {
    val assemblingRelease = allTasks.any { t ->
        val n = t.name
        n.contains("Release") &&
            (n.startsWith("assemble") || n.startsWith("bundle") || n.startsWith("package"))
    }
    if (assemblingRelease && !hasKeystore) {
        throw GradleException(
            "Release signing is not configured. `key.properties` (keyAlias + storeFile) " +
            "or the STORE_FILE/KEY_ALIAS environment variables are required for a release " +
            "build. A --release build must NOT fall back to the debug certificate. " +
            "Provide the release keystore material, or build with --debug."
        )
    }
    if (assemblingRelease && !hasMapsApiKey) {
        throw GradleException(
            "No Google Maps SDK key is configured. Set MAPS_API_KEY in " +
            "android/local.properties (git-ignored) or as an environment variable. " +
            "A --release build must NOT ship with the MISSING_MAPS_API_KEY placeholder — " +
            "the map screen would be blank/broken for every user. Provide your own " +
            "restricted key (package name + release-signing SHA-1), or build with --debug."
        )
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
