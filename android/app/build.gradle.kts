plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "de.insulink"
    compileSdk = flutter.compileSdkVersion
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
        // 26 (Android 8.0) ist die Untergrenze von Health Connect (health-Plugin).
        // Muss mit rust_builder/android/build.gradle übereinstimmen.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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

    // liblibre3bridge.so — the dlopen shim to Abbott's Libre 3 crypto blob. The
    // Abbott .so is resolved at runtime, so this compiles without it (see
    // src/main/cpp/libre3bridge.cpp and jniLibs/README.md).
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
