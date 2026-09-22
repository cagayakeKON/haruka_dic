import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val buildTargets = JsonSlurper().parse(file("../../config/build_targets.json")) as Map<*, *>
val environmentTargets = buildTargets["environments"] as Map<*, *>
val platforms = buildTargets["platforms"] as Map<*, *>
val androidTargets = platforms["android"] as Map<*, *>

android {
    namespace = "app.haruka.dictionary"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        resValues = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
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

    flavorDimensions += "environment"
    productFlavors {
        for (environment in listOf("dev", "production")) {
            create(environment) {
                dimension = "environment"
                val identity = androidTargets[environment] as Map<*, *>
                val settings = environmentTargets[environment] as Map<*, *>
                applicationId = identity["application_id"] as String
                resValue("string", "app_name", settings["display_name"] as String)
                manifestPlaceholders["harukaCleartext"] = (environment == "dev").toString()
                if (environment == "dev") {
                    // Isolated release-mode development builds use only a development key.
                    signingConfig = signingConfigs.getByName("debug")
                }
            }
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
