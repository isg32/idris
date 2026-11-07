plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: set by build_signed.sh (from .env), never committed.
// Without them, release builds fall back to the debug key, so
// `flutter build apk --release` still works with no setup.
val releaseStoreFile = System.getenv("IDRIS_KEYSTORE_FILE")?.let { file(it) }
val releaseStorePassword = System.getenv("IDRIS_KEYSTORE_PASSWORD")?.takeIf { it.isNotEmpty() }
val releaseKeyPassword =
    System.getenv("IDRIS_KEY_PASSWORD")?.takeIf { it.isNotEmpty() } ?: releaseStorePassword
val releaseKeyAlias = System.getenv("IDRIS_KEY_ALIAS")?.takeIf { it.isNotEmpty() } ?: "upload"
val canSignRelease = releaseStorePassword != null && releaseStoreFile?.exists() == true

android {
    namespace = "com.isg32.idris"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // NewPipeExtractor uses newer Java APIs than Android 7 has.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.isg32.idris"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
            storeFile = releaseStoreFile
            storePassword = releaseStorePassword
        }
    }

    buildTypes {
        release {
            signingConfig = if (canSignRelease) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
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
    // NewPipe's extractor finds a stream when the Dart extractor can't
    // (see YouTubeChannel.kt).
    implementation("com.github.TeamNewPipe:NewPipeExtractor:v0.27.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
