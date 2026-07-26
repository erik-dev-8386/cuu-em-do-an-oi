plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.thanhdthaichink"
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
        applicationId = "com.example.thanhdthaichink"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a", "x86_64"))
        }
    }

    // XỬ LÝ TRÙNG THƯ VIỆN NATIVE (.SO):
    packaging {
        jniLibs {
            pickFirsts.add("**/libonnxruntime.so")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // No explicit onnxruntime-android Maven dependency: the `onnxruntime` Dart
    // plugin bundles its own (older) libonnxruntime.so via jniLibs, which only
    // supports ONNX opset <= 19 and fails to load best.onnx (opset 20). Adding
    // a newer Maven dependency here didn't help — pickFirsts kept resolving to
    // the plugin's bundled copy regardless. Fix: a newer libonnxruntime.so
    // (extracted from onnxruntime-android:1.22.0) is committed directly under
    // app/src/main/jniLibs/<abi>/, which takes priority over the plugin's copy.
}

flutter {
    source = "../.."
}
