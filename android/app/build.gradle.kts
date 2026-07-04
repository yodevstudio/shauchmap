import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

// Resolve a signing value: key.properties first, then CI env vars, then null.
fun signingVal(propKey: String, envKey: String): String? =
    keystoreProperties.getProperty(propKey) ?: System.getenv(envKey)

val hasKeystore = signingVal("storeFile", "STORE_FILE") != null &&
    signingVal("keyAlias", "KEY_ALIAS") != null

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
    }

    buildTypes {
        release {
            signingConfig = if (hasKeystore) signingConfigs.getByName("release")
                            else signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
