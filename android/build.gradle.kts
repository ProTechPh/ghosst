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
subprojects {
    project.evaluationDependsOn(":app")
}

// file_picker 8.x declares compileSdk 34 in its own build.gradle, but
// flutter_plugin_android_lifecycle (transitive) requires consumers to compile
// against API 36, so :file_picker:checkDebugAarMetadata fails. Force only that
// module up to compileSdk 36 after its script runs (compiling against a higher
// SDK is always safe). Reflection is used so this root script does not need
// AGP classes on its own compile classpath.
subprojects {
    // Register only for file_picker: :app (and possibly others) may already be
    // evaluated here (evaluationDependsOn above), and calling afterEvaluate on
    // an evaluated project throws in Gradle 9.
    if (name == "file_picker") {
        val forceCompileSdk36: () -> Unit = {
            val ext = extensions.findByName("android")
            if (ext != null) {
                val setter = ext.javaClass.methods.firstOrNull {
                    (it.name == "setCompileSdk" || it.name == "compileSdkVersion") &&
                        it.parameterCount == 1
                }
                setter?.invoke(ext, 36)
            }
        }
        if (state.executed) {
            forceCompileSdk36()
        } else {
            afterEvaluate { forceCompileSdk36() }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
