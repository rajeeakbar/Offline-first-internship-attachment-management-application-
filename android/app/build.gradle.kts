import java.util.properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val localproperties = properties().apply{
    val file = rootProject.file("local.properties")
    if (file.exists()) load(file.inputStream())
}

android {
    namespace = "com.example.internship.internship_app"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.internship.internship_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        buildConfigField("String","https://pbxumeocnpqqtiwlvrhm.supabase.co","\"${localproperties.getProperty("supabase.url")}\"")
        buildConfigField("String","eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBieHVtZW9jbnBxcXRpd2x2cmhtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODMxNzM4MzYsImV4cCI6MjA5ODc0OTgzNn0.IZhJoMKUUYTnUuUCnJOnQiyhSUGcTSnExLWeqoC1NMc","\"${localproperties.getProperty("supabase.anon_key")}\"")
    }

    buildFeatures{
        buildConfig = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
dependencies {
    // ... your existing dependencies

    // Supabase BOM (manages versions for all supabase modules)
    implementation(platform("io.github.jan-tennert.supabase:bom:3.0.0")) // Check for latest version on GitHub

    // Core Postgrest (for Database operations)
    implementation("io.github.jan-tennert.supabase:postgrest-kt")

    // Optional: Add these if you need them
    // implementation("io.github.jan-tennert.supabase:auth-kt") // For Authentication
    // implementation("io.github.jan-tennert.supabase:realtime-kt") // For Realtime subscriptions
    // implementation("io.github.jan-tennert.supabase:storage-kt") // For File storage
}
