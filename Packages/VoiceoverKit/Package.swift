// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoiceoverKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "VoiceoverKit", targets: ["VoiceoverKit"]),
    ],
    targets: [
        .target(name: "VoiceoverKit", resources: [.process("Resources")]),
        .testTarget(
            name: "VoiceoverKitTests",
            dependencies: ["VoiceoverKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
