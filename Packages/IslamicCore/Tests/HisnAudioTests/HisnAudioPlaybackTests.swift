import XCTest
import HisnAudioPlayback
@testable import HisnReading

/// Phase 3B: the AVFoundation engine on the TEST_ONLY fixture (no sound is played), and the
/// offline / separation guarantees of the audio sources.
@MainActor
final class HisnAudioPlaybackTests: XCTestCase {
    private var fixtureURL: URL { Fixture.audioDirectory.appendingPathComponent("test-silence-1s.wav") }

    func testEngineLoadsDurationAndSeeks() throws {
        let engine = AVHisnAudioEngine()
        XCTAssertEqual(engine.duration, 0)
        try engine.load(url: fixtureURL)
        XCTAssertEqual(engine.duration, 1, accuracy: 0.01)
        XCTAssertEqual(engine.currentTime, 0, accuracy: 0.01)
        engine.seek(to: 0.5)
        XCTAssertEqual(engine.currentTime, 0.5, accuracy: 0.01)
        engine.seek(to: 5)
        XCTAssertLessThanOrEqual(engine.currentTime, 1)
        engine.stop()
        XCTAssertEqual(engine.currentTime, 0, accuracy: 0.01)
        engine.unload()
        XCTAssertEqual(engine.duration, 0)
    }

    func testEngineRejectsNonFileAndBrokenFiles() throws {
        let engine = AVHisnAudioEngine()
        XCTAssertThrowsError(try engine.load(url: URL(string: "https://example.com/a.mp3")!))
        let broken = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        try Data("not audio".utf8).write(to: broken)
        XCTAssertThrowsError(try engine.load(url: broken))
        XCTAssertEqual(engine.duration, 0)
    }

    // MARK: Offline and separation

    private func sources(_ target: String) throws -> [(String, String)] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent() // Tests/HisnAudioTests
            .deletingLastPathComponent().deletingLastPathComponent()           // Packages/IslamicCore
            .appendingPathComponent("Sources/\(target)")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        return try files.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.map {
            ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8))
        }
    }

    func testAudioCodeHasNoNetworkPath() throws {
        let forbidden = ["URLSession", "URLRequest", "downloadTask", "dataTask", "AVPlayer(", "AVURLAsset",
                         "http://", "NWConnection"]
        for target in ["IslamicCore", "HisnReading", "HisnAudioPlayback"] {
            let files = try sources(target)
            XCTAssertFalse(files.isEmpty, target)
            for (name, text) in files {
                for word in forbidden {
                    XCTAssertFalse(text.contains(word), "\(target)/\(name) contains \(word)")
                }
            }
        }
    }

    func testAudioCodeDoesNotTouchPiP() throws {
        let forbidden = ["AVPictureInPicture", "AVSampleBufferDisplayLayer", "CMSampleBuffer", "PiPEngine", "AVKit"]
        for target in ["IslamicCore", "HisnReading", "HisnAudioPlayback"] {
            for (name, text) in try sources(target) {
                for word in forbidden {
                    XCTAssertFalse(text.contains(word), "\(target)/\(name) contains \(word)")
                }
            }
        }
    }

    func testOnlyThePlaybackTargetImportsAVFoundation() throws {
        for target in ["IslamicCore", "HisnReading"] {
            for (name, text) in try sources(target) {
                XCTAssertFalse(text.contains("import AVFoundation"), "\(target)/\(name)")
            }
        }
        let sessionOwners = try sources("HisnAudioPlayback").filter { $0.1.contains("AVAudioSession.sharedInstance()") }
        XCTAssertEqual(sessionOwners.map(\.0), ["AudioSessionCoordinator.swift"], "one audio session owner")
    }

    // MARK: App PiP regression (Phase 3C)

    private func appSources() throws -> [(String, String)] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent() // Packages/IslamicCore
            .deletingLastPathComponent().deletingLastPathComponent() // repository
            .appendingPathComponent("IslamicPiPPOC")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        return try files.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.map {
            ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8))
        }
    }

    func testAppHasOneAudioSessionOwner() throws {
        let files = try appSources()
        XCTAssertTrue(files.contains { $0.0 == "PiPEngine.swift" })
        for (name, text) in files {
            XCTAssertFalse(text.contains("setCategory("), "\(name) configures the audio session")
            XCTAssertFalse(text.contains("setActive("), "\(name) activates the audio session")
        }
        let engine = try XCTUnwrap(files.first { $0.0 == "PiPEngine.swift" }?.1)
        XCTAssertTrue(engine.contains("AudioSessionCoordinator.shared.activateForPlayback()"))
    }

    func testExistingPiPPathIsPreserved() throws {
        let files = try appSources()
        let engine = try XCTUnwrap(files.first { $0.0 == "PiPEngine.swift" }?.1)
        for proven in ["ContentSource(sampleBufferDisplayLayer:", "CMClockGetHostTimeClock()", "controlTimebase",
                       "canStartPictureInPictureAutomaticallyFromInline = autoStartEnabled", "skipByInterval"] {
            XCTAssertTrue(engine.contains(proven), "PiPEngine lost \(proven)")
        }
        let surface = try XCTUnwrap(files.first { $0.0 == "SampleBufferPiPSurface.swift" }?.1)
        for proven in ["ContentSource(sampleBufferDisplayLayer:", "CMClockGetHostTimeClock()", "controlTimebase",
                       "AzkarFrameRenderer.makeSampleBuffer"] {
            XCTAssertTrue(surface.contains(proven), "the Hisn surface does not use \(proven)")
        }
        XCTAssertTrue(surface.contains("canStartPictureInPictureAutomaticallyFromInline = false"),
                      "Hisn PiP starts manually")
        for (name, text) in files {
            for word in ["AVPlayerViewController", "import ReplayKit", "import WebKit", "WKWebView", "AVPlayerLayer"] {
                XCTAssertFalse(text.contains(word), "\(name) contains \(word)")
            }
        }
    }

    func testFixtureModeIsCompiledOutOfProduction() throws {
        let files = try appSources()
        let fixture = try XCTUnwrap(files.first { $0.0 == "HisnAudioFixture.swift" }?.1)
        XCTAssertTrue(fixture.hasPrefix("#if HISN_AUDIO_FIXTURE"))
        for (name, text) in files where name != "HisnAudioFixture.swift" {
            let uses = text.components(separatedBy: "HisnAudioFixture.").count - 1
            let guarded = text.components(separatedBy: "#if HISN_AUDIO_FIXTURE").count - 1
            XCTAssertLessThanOrEqual(uses, guarded, "\(name) uses the fixture outside #if HISN_AUDIO_FIXTURE")
            XCTAssertFalse(text.contains(".testOnly"), "\(name) allows TEST_ONLY assets in the app")
        }
    }
}
