import java.io.File
import java.util.Base64
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// ─────────────────────────────────────────────────────────────────────────────
// Release signing
//
// Signatures must stay identical across every machine that produces a shipped
// APK, otherwise Android refuses the update with INSTALL_FAILED_UPDATE_
// INCOMPATIBLE and users cannot upgrade in place.
//
// Credentials are read from android/key.properties when it exists (local
// builds), otherwise from environment variables, which is how the release
// workflow injects GitHub Secrets:
//
//   MUSIX_KEYSTORE_BASE64  base64 of the .jks / .keystore
//   MUSIX_KEYSTORE_PASSWORD keystore password
//   MUSIX_KEY_ALIAS        signing key alias
//   MUSIX_KEY_PASSWORD     key password
//
// If none of that is present the release build falls back to the Android debug
// key so `flutter run` and local `flutter build apk --release` still work.
// That is a development convenience ONLY - a debug-signed APK must never be
// published, because every developer machine has a different debug key and
// users would be unable to install updates over one another.
//
// Never commit key.properties, a .jks, a .keystore or a password. See
// android/key.properties.template and CONTRIBUTING.md.
// ─────────────────────────────────────────────────────────────────────────────
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

fun signingValue(property: String, env: String): String? =
    (keystoreProperties.getProperty(property) ?: System.getenv(env))?.takeIf { it.isNotBlank() }

// Named `resolved*` rather than the obvious `storePassword`, `keyAlias` and
// `keyPassword`, and the naming is the fix rather than a style choice.
//
// Inside `signingConfigs { create("release") { ... } }` the receiver is the
// signing config itself, so a bare `storePassword = storePassword` resolves the
// right-hand side to the receiver's own property rather than to the value above:
// it is a self-assignment of null. AGP accepts it at configuration time - which
// is why `releaseSigningUsable` below says the credentials are present - and
// then fails at `packageRelease`:
//
//   SigningConfig "release" is missing required property "storePassword"
//
// storeFile was the one assignment that worked, because `SigningConfig` has no
// `releaseKeystore` property for the name to collide with. So the keystore was
// found and handed over, three credentials were silently thrown away, and the
// error named a property the script believed it had just set. Only reachable by
// running the release: nothing reads this file until Gradle does.
val resolvedStoreFilePath = keystoreProperties.getProperty("storeFile")?.takeIf { it.isNotBlank() }
val resolvedStoreBase64 = System.getenv("MUSIX_KEYSTORE_BASE64")?.takeIf { it.isNotBlank() }
val resolvedStorePassword = signingValue("storePassword", "MUSIX_KEYSTORE_PASSWORD")
val resolvedKeyAlias = signingValue("keyAlias", "MUSIX_KEY_ALIAS")
val resolvedKeyPassword = signingValue("keyPassword", "MUSIX_KEY_PASSWORD")

val hasReleaseSigning = resolvedStoreFilePath != null || resolvedStoreBase64 != null

// A keystore supplied as base64 (the CI path) is decoded into the Gradle user
// home for the duration of the build, so it is never written inside the
// repository. A keystore referenced by key.properties is used where it is.
val resolvedKeystore: File? = when {
    resolvedStoreFilePath != null -> File(resolvedStoreFilePath)
    resolvedStoreBase64 != null -> {
        val tempDir = System.getenv("RUNNER_TEMP")
            ?: gradle.gradleUserHomeDir.absolutePath
        val target = File(tempDir, "musix-release.jks")
        target.parentFile.mkdirs()
// The name `java` resolves to Gradle's own `java` extension inside a script
    // body, shadowing the package, hence the Base64 import at the top.
    target.writeBytes(Base64.getDecoder().decode(resolvedStoreBase64))
        target
    }
    else -> null
}

val releaseSigningUsable =
    hasReleaseSigning &&
        resolvedKeystore != null &&
        !resolvedStorePassword.isNullOrBlank() &&
        !resolvedKeyAlias.isNullOrBlank() &&
        !resolvedKeyPassword.isNullOrBlank()

android {
    namespace = "com.khisa318.musiX"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

// `kotlinOptions` is deprecated and now fails script compilation; the
// `compilerOptions` DSL is its replacement and takes the same value.
kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_11
    }
}

    defaultConfig {
        applicationId = "com.khisa318.musiX"
        multiDexEnabled = true
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Both come straight from `version: 1.2.0+12` in pubspec.yaml, so
        // pubspec is the single source of truth for versioning.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningUsable) {
            create("release") {
                // `resolved*` on the right: see the note above. Bare names here
                // would assign each property to itself.
                storeFile = resolvedKeystore
                storePassword = resolvedStorePassword
                keyAlias = resolvedKeyAlias
                keyPassword = resolvedKeyPassword
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
                enableV4Signing = false
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseSigningUsable) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "MusiX: no release signing credentials found " +
                        "(android/key.properties or MUSIX_KEYSTORE_* env vars). " +
                        "Falling back to the Android debug key. Do NOT publish " +
                        "this build."
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation(platform("com.google.guava:guava-bom:33.0.0-android"))
    implementation("com.google.guava:guava")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}

flutter {
    source = "../.."
}
