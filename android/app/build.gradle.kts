import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter plugin applies after Android + Kotlin.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing — reads from key.properties (gitignored).
// Generate a keystore:
//   keytool -genkey -v -keystore upload-keystore.jks \
//     -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 \
//     -alias upload
//
// Create android/key.properties:
//   storePassword=<password>
//   keyPassword=<password>
//   keyAlias=upload
//   storeFile=../upload-keystore.jks
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.crispstrobe.crisperweaver"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.crispstrobe.crisperweaver"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    // Pre-built libwhisper.so (+ sibling CrispASR backend libs) are dropped
    // into src/main/jniLibs/<abi>/ by CrispASR/build-android.sh.
    sourceSets {
        named("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    packaging {
        jniLibs {
            // Other plugins may ship libc++_shared; keep the first.
            pickFirsts += "**/libc++_shared.so"
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Fallback to debug signing for local development when
                // no keystore is configured. CI/release builds must
                // provide key.properties.
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
