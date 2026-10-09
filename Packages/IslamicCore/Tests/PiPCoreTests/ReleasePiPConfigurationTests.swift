import Foundation
import XCTest
import PiPCore

/// The production PiP path ships in Release as it is: no Debug-only switch hides or changes it,
/// and the only gate is the platform one (the app's background mode, read from Info.plist).
final class ReleasePiPConfigurationTests: XCTestCase {
    private var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent() // PiPCoreTests
            .deletingLastPathComponent().deletingLastPathComponent() // Packages/IslamicCore
            .deletingLastPathComponent().deletingLastPathComponent() // repository
    }

    private func swiftFiles(_ path: String) throws -> [(String, String)] {
        let root = repository.appendingPathComponent(path)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), path)
        if !isDirectory.boolValue { return [(path, try String(contentsOf: root, encoding: .utf8))] }
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        return try files.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }.map {
            ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8))
        }
    }

    /// Every file the production PiP runs through, from the reader button to the frame.
    private func productionPiPFiles() throws -> [(String, String)] {
        try ["Packages/IslamicCore/Sources/PiPCore", "Packages/IslamicCore/Sources/PiPRendering",
             "Packages/IslamicCore/Sources/PiPProviders", "IslamicPiPPOC/PiP", "IslamicPiPPOC/App/AppServices.swift",
             "IslamicPiPPOC/Quran/QuranReaderView.swift", "IslamicPiPPOC/Hisn/HisnReaderView.swift",
             "IslamicPiPPOC/Adhkar/DevotionalReaderView.swift"]
            .flatMap(swiftFiles)
    }

    private func plist(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repository.appendingPathComponent(name))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    func testNoDebugSwitchOnTheProductionPath() throws {
        let files = try productionPiPFiles()
        XCTAssertGreaterThan(files.count, 10)
        for (name, source) in files {
            // The device-test IPA (HISN_AUDIO_FIXTURE) may mark itself; nothing else is conditional.
            let text = source.replacingOccurrences(of: #"#if HISN_AUDIO_FIXTURE[\s\S]*?#endif"#, with: "",
                                                   options: .regularExpression)
            XCTAssertFalse(text.contains("#if DEBUG"), "\(name) changes PiP in Debug only")
            XCTAssertFalse(text.contains("#if !DEBUG"), "\(name) changes PiP in Release only")
            for word in ["PiPTestEngine", "HisnAudioFixture", "PiP Technical Test", "synthetic", "chime"] {
                XCTAssertFalse(text.contains(word), "\(name) uses test-only \(word)")
            }
        }
    }

    func testTheOnlyBuildGateIsTheDeclaredBackgroundMode() throws {
        let services = try XCTUnwrap(try productionPiPFiles().first { $0.0 == "IslamicPiPPOC/App/AppServices.swift" }?.1)
        XCTAssertTrue(services.contains("PiPAvailability.backgroundModeDeclared(in: Bundle.main.infoDictionary)"))
        // Availability never depends on a recording: text PiP works without one.
        let availability = try XCTUnwrap(try swiftFiles("Packages/IslamicCore/Sources/PiPCore/PiPSession.swift").first?.1)
        for word in ["audio.availability", "recording", "hasAudio"] {
            XCTAssertFalse(availability.contains(word), "PiP availability depends on \(word)")
        }
    }

    func testEveryReaderOffersPiP() throws {
        let files = Dictionary(try productionPiPFiles(), uniquingKeysWith: { first, _ in first })
        for reader in ["IslamicPiPPOC/Quran/QuranReaderView.swift", "IslamicPiPPOC/Hisn/HisnReaderView.swift",
                       "IslamicPiPPOC/Adhkar/DevotionalReaderView.swift"] {
            XCTAssertTrue(files[reader]?.contains("PiPEntryView(") == true, "\(reader) has no PiP button")
        }
        XCTAssertTrue(files["IslamicPiPPOC/Quran/QuranReaderView.swift"]?.contains("تشغيل في نافذة عائمة") == true)
    }

    /// The background mode, if declared, is the PiP one and nothing else.
    func testDeclaredBackgroundModesAreOnlyThePiPOne() throws {
        for name in ["Info.plist", "Info-Debug.plist"] {
            let info = try plist(name)
            if let modes = info["UIBackgroundModes"] {
                XCTAssertEqual(modes as? [String], ["audio"], name)
            }
        }
        XCTAssertTrue(PiPAvailability.backgroundModeDeclared(in: try plist("Info-Debug.plist")))
    }
}
