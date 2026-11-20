// swift-tools-version: 6.2
import PackageDescription

// Side-by-side check of the Kotlin Multiplatform port against the Swift reference, see docs/kmp-experiment.md.
// Not part of the app or of Scripts/check.sh: the binary target only exists after
// `./gradlew :shared:assembleSharedReleaseXCFramework`. Run it with Scripts/kmp-compare.sh.
let package = Package(
    name: "KMPComparison",
    platforms: [.iOS(.v26)],
    dependencies: [
        .package(path: "../VoiceoverKit"),
    ],
    targets: [
        .binaryTarget(name: "Shared", path: "../../shared/build/XCFrameworks/release/Shared.xcframework"),
        .testTarget(name: "KMPComparisonTests", dependencies: ["VoiceoverKit", "Shared"]),
    ]
)
