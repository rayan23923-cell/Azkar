// swift-tools-version: 5.9
import PackageDescription

// Pure Swift + Foundation: domain models, session cursor, state types, and
// offline content repositories. No UIKit, SwiftUI, AVKit or AVFoundation.
// HisnReading is the Hisn Al-Muslim reader state on top of IslamicCore
// (navigation, repetition, search, resume, the audio player state); the SwiftUI views
// live in the app. HisnAudioPlayback is the only target that imports AVFoundation.
// ContentKit is shared by every content type: Arabic search normalization, content
// references, and on-device progress stores.
// QuranReading is the Quran reader state (library with juz/page lookup, position, search);
// AdhkarReading is the adhkar and dua reader state (collections, counter, positions, search).
// GlobalSearch searches every section together on top of their own engines.
// ContentAudio is the listening queue and its PiP coordinator for the Quran, adhkar and duas,
// on the Hisn audio player and PiP surface protocols; its pack (content_audio.json) is empty.
// QuranText bundles the OFL Amiri Quran font and its Core Text layout checks.
// HisnShareCard draws the share image with Core Text / Core Graphics (testable here).
// Unified PiP: PiPCore is the engine, state, navigation, pages and session, free of AVKit;
// PiPRendering draws PiP frames with Core Text; PiPProviders adapts the Quran, Hisn, adhkar and
// dua readers to it. The AVKit controller lives in the app.
let package = Package(
    name: "IslamicCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "IslamicCore", targets: ["IslamicCore"]),
        .library(name: "HisnReading", targets: ["HisnReading"]),
        .library(name: "HisnAudioPlayback", targets: ["HisnAudioPlayback"]),
        .library(name: "HisnShareCard", targets: ["HisnShareCard"]),
        .library(name: "ContentKit", targets: ["ContentKit"]),
        .library(name: "QuranReading", targets: ["QuranReading"]),
        .library(name: "QuranText", targets: ["QuranText"]),
        .library(name: "AdhkarReading", targets: ["AdhkarReading"]),
        .library(name: "GlobalSearch", targets: ["GlobalSearch"]),
        .library(name: "ContentAudio", targets: ["ContentAudio"]),
        .library(name: "PiPCore", targets: ["PiPCore"]),
        .library(name: "PiPRendering", targets: ["PiPRendering"]),
        .library(name: "PiPProviders", targets: ["PiPProviders"]),
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
            name: "QuranReading",
            dependencies: ["IslamicCore", "ContentKit"]
        ),
        .target(
            name: "AdhkarReading",
            dependencies: ["IslamicCore", "ContentKit"]
        ),
        .target(
            name: "GlobalSearch",
            dependencies: ["IslamicCore", "ContentKit", "QuranReading", "HisnReading", "AdhkarReading"]
        ),
        .target(
            name: "ContentAudio",
            dependencies: ["IslamicCore", "ContentKit", "HisnReading"]
        ),
        .target(
            name: "QuranText",
            resources: [.copy("Resources/AmiriQuran-Regular.ttf"), .copy("Resources/AmiriQuran-OFL.txt")]
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
        .target(
            name: "PiPCore"
        ),
        .target(
            name: "PiPRendering",
            dependencies: ["PiPCore", "QuranText"]
        ),
        .target(
            name: "PiPProviders",
            dependencies: ["PiPCore", "IslamicCore", "QuranReading", "HisnReading", "AdhkarReading"]
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
            name: "QuranReadingTests",
            dependencies: ["QuranReading", "QuranText", "ContentKit", "IslamicCore"]
        ),
        .testTarget(
            name: "AdhkarReadingTests",
            dependencies: ["AdhkarReading", "ContentKit", "IslamicCore"]
        ),
        .testTarget(
            name: "GlobalSearchTests",
            dependencies: ["GlobalSearch", "QuranReading", "HisnReading", "AdhkarReading", "ContentKit", "IslamicCore"]
        ),
        .testTarget(
            name: "ContentAudioTests",
            dependencies: ["ContentAudio", "HisnReading", "ContentKit", "IslamicCore"]
        ),
        .testTarget(
            name: "HisnAudioTests",
            dependencies: ["HisnAudioPlayback", "HisnReading", "IslamicCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "HisnShareCardTests",
            dependencies: ["HisnShareCard", "HisnReading", "IslamicCore", "QuranText"]
        ),
        .testTarget(
            name: "PiPCoreTests",
            dependencies: ["PiPCore"]
        ),
        .testTarget(
            name: "PiPRenderingTests",
            dependencies: ["PiPRendering", "PiPCore", "QuranText", "IslamicCore", "HisnReading"]
        ),
        .testTarget(
            name: "PiPProvidersTests",
            dependencies: ["PiPProviders", "PiPCore", "PiPRendering", "QuranReading", "HisnReading",
                           "AdhkarReading", "ContentKit", "IslamicCore"]
        ),
    ]
)
