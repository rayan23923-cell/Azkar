// swift-tools-version: 5.9
import PackageDescription

// Pure Swift + Foundation: domain models, session cursor, state types, and
// offline content repositories. No UIKit, SwiftUI, AVKit or AVFoundation.
let package = Package(
    name: "IslamicCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "IslamicCore", targets: ["IslamicCore"]),
    ],
    targets: [
        .target(
            name: "IslamicCore",
            resources: [.copy("Resources/Content")]
        ),
        .testTarget(
            name: "IslamicCoreTests",
            dependencies: ["IslamicCore"]
        ),
    ]
)
