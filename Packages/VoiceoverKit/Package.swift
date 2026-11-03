// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoiceoverKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
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
