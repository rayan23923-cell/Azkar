// swift-tools-version: 5.9
import PackageDescription

// Pure Swift + Foundation: domain models, session cursor, state types, and
// offline content repositories. No UIKit, SwiftUI, AVKit or AVFoundation.
// HisnReading is the Hisn Al-Muslim reader state on top of IslamicCore
// (navigation, repetition, search, resume); the SwiftUI views live in the app.
let package = Package(
    name: "IslamicCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "IslamicCore", targets: ["IslamicCore"]),
        .library(name: "HisnReading", targets: ["HisnReading"]),
    ],
    targets: [
        .target(
            name: "IslamicCore",
            resources: [.copy("Resources/Content")]
        ),
        .target(
            name: "HisnReading",
            dependencies: ["IslamicCore"]
        ),
        .testTarget(
            name: "IslamicCoreTests",
            dependencies: ["IslamicCore"]
        ),
        .testTarget(
            name: "HisnReadingTests",
            dependencies: ["HisnReading", "IslamicCore"]
        ),
    ]
)
