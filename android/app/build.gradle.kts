plugins {
    id("com.android.application")
    // Flutter Gradle 插件必须在 Android 和 Kotlin Gradle 插件之后应用。
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.cloudmusic.cloud_music"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: 指定自己的唯一应用 ID（https://developer.android.com/studio/build/application-id.html）。
        applicationId = "dev.cloudmusic.cloud_music"
        // 可根据应用需求调整以下值。
        // 更多说明见 https://flutter.dev/to/review-gradle-config。
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        // 使用 pubspec.yaml 中的版本代码。按架构拆分 APK 时，Flutter 会自动加上
        // 1000 * ABI_VERSION（https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions）。
        // 构建时可指定 `-P force-version-code-ignoring-abi=true`，
        // 强制使用 versionCode 的值。
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: 为发布构建添加自己的签名配置。
            // 暂时使用调试密钥签名，以便运行 `flutter run --release`。
            signingConfig = signingConfigs.getByName("debug")
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
