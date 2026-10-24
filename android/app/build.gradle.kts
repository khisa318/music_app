
import java.io.File
import java.util.Base64
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Load release signing properties from android/key.properties.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

fun signingValue(property: String): String? =
    (
        keystoreProperties.getProperty(property)
            ?: System.getenv(
                when (property) {
                    "storePassword" -> "MUSIX_KEYSTORE_PASSWORD"
                    "keyAlias" -> "MUSIX_KEY_ALIAS"
                    "keyPassword" -> "MUSIX_KEY_PASSWORD"
                    else -> ""
                }
            )
    )?.takeIf { it.isNotBlank() }

val resolvedStoreFilePath =
    keystoreProperties.getProperty("storeFile")
        ?.takeIf { it.isNotBlank() }

val resolvedStoreBase64 =
    System.getenv("MUSIX_KEYSTORE_BASE64")
        ?.takeIf { it.isNotBlank() }

val resolvedStorePassword =
    signingValue("storePassword")

val resolvedKeyAlias =
    signingValue("keyAlias")

val resolvedKeyPassword =
    signingValue("keyPassword")

// Resolve the local keystore relative to the Android project root.
// In CI, restore the keystore from the Base64 GitHub secret.
val resolvedKeystore: File? = when {
    resolvedStoreFilePath != null ->
        rootProject.file(resolvedStoreFilePath)

    resolvedStoreBase64 != null -> {
        val tempDir = System.getenv("RUNNER_TEMP")
            ?: gradle.gradleUserHomeDir.absolutePath

        val target = File(tempDir, "musix-release.jks")
        target.parentFile.mkdirs()
        target.writeBytes(
            Base64.getDecoder().decode(resolvedStoreBase64)
        )
        target
    }

    else -> null
}

val releaseSigningUsable =
    resolvedKeystore != null &&
        resolvedKeystore.isFile &&
        !resolvedStorePassword.isNullOrBlank() &&
        !resolvedKeyAlias.isNullOrBlank() &&
        !resolvedKeyPassword.isNullOrBlank()

android {
    namespace = "com.khisa318.musiX"
    compileSdk = flutter.compileSdkVersion

    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    defaultConfig {
        applicationId = "com.khisa318.musiX"
        multiDexEnabled = true
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningUsable) {
            create("release") {
                storeFile = resolvedKeystore!!
                storePassword = resolvedStorePassword!!
                keyAlias = resolvedKeyAlias!!
                keyPassword = resolvedKeyPassword!!

                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
                enableV4Signing = false
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningUsable) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

gradle.taskGraph.whenReady {
    val releaseBuildRequested = allTasks.any { task ->
        task.project == project &&
            task.name.contains("release", ignoreCase = true)
    }
    if (releaseBuildRequested && !releaseSigningUsable) {
        throw GradleException(
            "MusiX release signing credentials are missing or the " +
                "keystore file does not exist. Refusing to build a " +
                "release without valid release signing configuration."
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_11
    }
}

dependencies {
    coreLibraryDesugaring(
        "com.android.tools:desugar_jdk_libs:2.1.4"
    )

    implementation(
        platform("com.google.guava:guava-bom:33.0.0-android")
    )
    implementation("com.google.guava:guava")

    implementation(
        "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3"
    )
}

flutter {
    source = "../.."
}
