// swift-tools-version: 5.9
import PackageDescription

// Pure Swift + Foundation: domain models, session cursor, state types, and
// offline content repositories. No UIKit, SwiftUI, AVKit or AVFoundation.
// HisnReading is the Hisn Al-Muslim reader state on top of IslamicCore
// (navigation, repetition, search, resume, the audio player state); the SwiftUI views
// live in the app. HisnAudioPlayback is the only target that imports AVFoundation.
// ContentKit is shared by every content type: Arabic search normalization, content
// references, and on-device progress stores.
// HisnShareCard draws the share image with Core Text / Core Graphics (testable here).
let package = Package(
    name: "IslamicCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "IslamicCore", targets: ["IslamicCore"]),
        .library(name: "HisnReading", targets: ["HisnReading"]),
        .library(name: "HisnAudioPlayback", targets: ["HisnAudioPlayback"]),
        .library(name: "HisnShareCard", targets: ["HisnShareCard"]),
        .library(name: "ContentKit", targets: ["ContentKit"]),
    ],
    targets: [
        .target(
            name: "IslamicCore",
            resources: [.copy("Resources/Content")]
        ),
        .target(
            name: "ContentKit",
            dependencies: ["IslamicCore"]
        ),
        .target(
            name: "HisnReading",
            dependencies: ["IslamicCore", "ContentKit"]
        ),
        .target(
            name: "HisnAudioPlayback",
            dependencies: ["HisnReading"]
        ),
        .target(
            name: "HisnShareCard",
            dependencies: ["HisnReading"]
        ),
        .testTarget(
            name: "IslamicCoreTests",
            dependencies: ["IslamicCore"]
        ),
        .testTarget(
            name: "HisnReadingTests",
            dependencies: ["HisnReading", "IslamicCore", "ContentKit"]
        ),
        .testTarget(
            name: "ContentKitTests",
            dependencies: ["ContentKit", "IslamicCore"]
        ),
        .testTarget(
            name: "HisnAudioTests",
            dependencies: ["HisnAudioPlayback", "HisnReading", "IslamicCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "HisnShareCardTests",
            dependencies: ["HisnShareCard", "HisnReading", "IslamicCore"]
        ),
    ]
)
