allprojects {
    repositories {
        google()
        mavenCentral()
    }
    extra.set("compileSdkVersion", 36)
    extra.set("targetSdkVersion", 34) // Keep targetSdk at 34 for safe behavioral compatibility
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

subprojects {
    val configureAndroid = {
        val android = project.extensions.findByName("android")
        if (android is com.android.build.gradle.BaseExtension) {
            android.compileSdkVersion(36)
        }
    }
    project.plugins.withId("com.android.library") {
        configureAndroid()
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
