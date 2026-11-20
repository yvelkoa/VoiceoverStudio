// Kotlin Multiplatform experiment, see docs/kmp-experiment.md. The iOS app does not depend on this build.
pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        mavenCentral()
    }
}

rootProject.name = "VoiceoverStudio"
include(":shared")
