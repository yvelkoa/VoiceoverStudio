// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceoverKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "VoiceoverKit", targets: ["VoiceoverKit"]),
    ],
    targets: [
        .target(name: "VoiceoverKit"),
        .testTarget(
            name: "VoiceoverKitTests",
            dependencies: ["VoiceoverKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
