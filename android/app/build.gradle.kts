import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The gitignored vendor keys (docs/VENDOR_KEYS.md): the Libre 3 section is baked
// into BuildConfig, the Libre 3 blob is packaged from jniLibs/ next to it. Missing
// → empty strings and no blob → the app builds, Libre 3 just can't pair.
val vendorKeysDir = rootProject.file("../assets/vendor_keys")
@Suppress("UNCHECKED_CAST")
val libre3Keys = vendorKeysDir.resolve("vendor_keys.json").takeIf { it.exists() }
    ?.let { (JsonSlurper().parse(it) as Map<String, Any?>)["libre3"] as? Map<String, Any?> }
    .orEmpty()

/** One Libre 3 key list from the vendor keys, comma-joined for BuildConfig. */
fun libre3KeyList(name: String) = (libre3Keys[name] as? List<*>).orEmpty().joinToString(",")

android {
    namespace = "de.insulink"

    buildFeatures {
        buildConfig = true
    }
    // Pinned ahead of `flutter.compileSdkVersion` (36): permission_handler_android
    // declares an AAR metadata minimum of 37, and the build fails the check
    // without it. Independent of targetSdk, which still follows Flutter.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "de.insulink"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // 26 (Android 8.0) is the floor Health Connect imposes (health plugin).
        // Must match rust_builder/android/build.gradle.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField("String", "LIBRE3_CERTIFICATES", "\"${libre3KeyList("app_certificates")}\"")
        buildConfigField("String", "LIBRE3_PRIVATE_KEYS", "\"${libre3KeyList("app_private_keys")}\"")
        buildConfigField("boolean", "LIBRE3_BLOB", "${vendorKeysDir.resolve("jniLibs/arm64-v8a/liblibre3extension.so").exists()}")
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Flutter enables R8 for release; feed it our MLKit keep rules so the
            // barcode scanner (mobile_scanner) isn't stripped — see proguard-rules.pro.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    sourceSets["main"].jniLibs.srcDir(vendorKeysDir.resolve("jniLibs"))

    // liblibre3bridge.so — the dlopen shim to Abbott's Libre 3 crypto blob. The
    // Abbott .so is resolved at runtime, so this compiles without it (see
    // src/main/cpp/libre3bridge.cpp and docs/LIBRE3_BLOB.md).
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    // The prebuilt Libre 3 blobs are WhiteCryption-protected/packed — don't let
    // the NDK strip them (it corrupts them and errors on the non-standard ELF).
    packaging {
        jniLibs {
            keepDebugSymbols += "**/liblibre3extension.so"
            keepDebugSymbols += "**/libinit.so"
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
