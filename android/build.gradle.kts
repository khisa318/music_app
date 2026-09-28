allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Clamp plugin modules to the SDK platform Flutter itself defaults to.
//
// receive_sharing_intent 1.9.0 hardcodes `compileSdk 37` in its own
// android/build.gradle, but the Android SDK now publishes Platform 37 as
// `android-37.0` (AndroidVersion.ApiLevel=37.0) and there is no plain
// `android-37` package to install. AGP 8 matches platform hash strings
// literally, so the build fails with
// "Failed to find target with hash string 'android-37'".
//
// This block has to stay above the evaluationDependsOn block below: registering
// afterEvaluate before the module is evaluated makes this callback run before
// AGP's own, which is what reads compileSdk.
subprojects {
    afterEvaluate {
        val android = extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)
        if (android != null && android.compileSdk != null && android.compileSdk!! > 36) {
            android.compileSdk = 36
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
