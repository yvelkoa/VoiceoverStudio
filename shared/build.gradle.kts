import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework

plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.kotlin.serialization)
}

// commonTest has no portable resource loading, so the Swift package's JSON fixtures are turned into string
// constants at build time. One copy of the fixtures, shared by both test suites.
val generateTestFixtures = tasks.register("generateTestFixtures") {
    val fixtures = rootProject.layout.projectDirectory.dir("Packages/VoiceoverKit/Tests/VoiceoverKitTests/Fixtures")
    val output = layout.buildDirectory.dir("generated/fixtures/kotlin")
    inputs.dir(fixtures)
    outputs.dir(output)
    doLast {
        val constants = fixtures.asFile.listFiles { file -> file.extension == "json" }!!.sortedBy { it.name }
            .joinToString("\n") { file ->
                val literal = file.readText().replace("$", "\${'$'}")
                "    const val ${file.nameWithoutExtension.uppercase()}: String = \"\"\"$literal\"\"\""
            }
        output.get().file("Fixtures.kt").asFile.apply { parentFile.mkdirs() }
            .writeText("package voiceover.shared\n\ninternal object Fixtures {\n$constants\n}\n")
    }
}

kotlin {
    explicitApi()
    jvmToolchain(17)

    jvm()

    val xcframework = XCFramework("Shared")
    listOf(iosArm64(), iosSimulatorArm64()).forEach { target ->
        target.binaries.framework {
            baseName = "Shared"
            // Static, so the Swift package that consumes it has nothing to embed.
            isStatic = true
            binaryOption("bundleId", "beav.dev.VoiceoverShared")
            xcframework.add(this)
        }
    }

    sourceSets {
        all {
            languageSettings.optIn("kotlin.uuid.ExperimentalUuidApi")
            languageSettings.optIn("kotlin.io.encoding.ExperimentalEncodingApi")
        }
        commonMain.dependencies {
            implementation(libs.ktor.client.core)
            implementation(libs.serialization.json)
            implementation(libs.coroutines.core)
        }
        commonTest {
            kotlin.srcDir(generateTestFixtures)
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
            implementation(libs.ktor.client.mock)
            implementation(libs.coroutines.test)
        }
        iosMain.dependencies {
            implementation(libs.ktor.client.darwin)
        }
        jvmMain.dependencies {
            implementation(libs.ktor.client.cio)
        }
    }
}
