import XCTest
import IslamicCore
@testable import HisnReading

/// Phase 3B: the audio manifest and the bundled audio repository.
final class HisnAudioManifestTests: XCTestCase {
    private func assertInvalid(_ manifest: Data, audioDirectory: URL = Fixture.audioDirectory,
                               _ message: String, file: StaticString = #filePath, line: UInt = #line) async throws {
        let repository = try await Fixture.repository(manifest: manifest, audioDirectory: audioDirectory)
        do {
            _ = try await repository.audio(for: Fixture.itemId)
            XCTFail("expected the manifest to be rejected: \(message)", file: file, line: line)
        } catch let error as ContentError {
            switch error {
            case .invalidContent, .resourceMissing, .unsupportedFormatVersion: break
            default: XCTFail("\(message): unexpected \(error)", file: file, line: line)
            }
        }
    }

    // MARK: Production pack

    func testProductionManifestIsValidAndHoldsNoAssetsYet() async throws {
        let ids = try await HisnLibraryCache.itemIds()
        let repository = BundledHisnAudioRepository(knownItemIds: ids)
        let assets = try await repository.allAssets()
        XCTAssertEqual(assets, [], "no production recording is bundled until rights and files exist")
        for id in ids.sorted().prefix(20) {
            let audio = try await repository.audio(for: id)
            XCTAssertNil(audio, id)
        }
    }

    func testTestOnlyAssetsAreRefusedByTheAppRepository() async throws {
        let ids = try await HisnLibraryCache.itemIds()
        let repository = BundledHisnAudioRepository(knownItemIds: ids, manifest: .data(Fixture.manifestData),
                                                    audioDirectory: Fixture.audioDirectory)
        do {
            _ = try await repository.audio(for: Fixture.itemId)
            XCTFail("a TEST_ONLY asset must never pass as production audio")
        } catch ContentError.invalidContent(let message) {
            XCTAssertTrue(message.contains("TEST_ONLY"), message)
        }
    }

    // MARK: Valid fixture

    func testValidAssetLoads() async throws {
        let repository = try await Fixture.repository()
        let found = try await repository.audio(for: Fixture.itemId)
        let asset = try XCTUnwrap(found)
        XCTAssertEqual(asset.id, Fixture.assetId)
        XCTAssertEqual(asset.usage, .testOnly)
        XCTAssertEqual(asset.format, .wav)
        XCTAssertEqual(asset.source.rightsStatus, .pendingPreReleaseReview)
        XCTAssertNil(asset.source.sourceURL)
        let url = try await repository.resourceURL(for: asset)
        XCTAssertTrue(url.isFileURL)
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL.path,
                       Fixture.audioDirectory.standardizedFileURL.path, "inside the audio directory")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let all = try await repository.allAssets()
        XCTAssertEqual(all.map(\.id), [Fixture.assetId])
    }

    func testItemWithoutAudioIsNil() async throws {
        let repository = try await Fixture.repository()
        let none = try await repository.audio(for: "hisn-001-02")
        XCTAssertNil(none, "no recording is a normal state")
        let unknown = try await repository.audio(for: "not-an-item")
        XCTAssertNil(unknown)
    }

    func testForeignAssetHasNoURL() async throws {
        let repository = try await Fixture.repository()
        do {
            _ = try await repository.resourceURL(for: StubAudioRepository.asset(for: "hisn-001-02"))
            XCTFail("only manifest assets resolve")
        } catch ContentError.notFound {}
    }

    // MARK: Invalid manifests

    func testMissingAssetFile() async throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try await assertInvalid(Fixture.manifestData, audioDirectory: empty, "missing file")
    }

    func testEmptyFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent("test-silence-1s.wav"))
        try await assertInvalid(Fixture.manifestData, audioDirectory: directory, "empty file")
    }

    func testDuplicateId() async throws {
        var object = Fixture.manifestObject()
        var assets = object["assets"] as! [[String: Any]]
        var copy = assets[0]
        copy["itemId"] = "hisn-001-02"
        assets.append(copy)
        object["assets"] = assets
        try await assertInvalid(Fixture.data(object), "duplicate id")
    }

    func testTwoRecordingsForOneItem() async throws {
        var object = Fixture.manifestObject()
        var assets = object["assets"] as! [[String: Any]]
        var copy = assets[0]
        copy["id"] = "hisn-audio-test-second"
        assets.append(copy)
        object["assets"] = assets
        try await assertInvalid(Fixture.data(object), "one recording per item")
    }

    func testInvalidItemId() async throws {
        try await assertInvalid(Fixture.manifest { $0["itemId"] = "hisn-999-01" }, "unknown item")
    }

    func testChecksumMismatch() async throws {
        try await assertInvalid(Fixture.manifest { $0["sha256"] = String(repeating: "a", count: 64) }, "checksum")
        try await assertInvalid(Fixture.manifest { $0["sha256"] = "ABC" }, "checksum format")
        try await assertInvalid(Fixture.manifest { $0["byteCount"] = 16043 }, "byte count")
    }

    func testInvalidFormat() async throws {
        try await assertInvalid(Fixture.manifest { $0["format"] = "ogg" }, "unsupported format")
        try await assertInvalid(Fixture.manifest { $0["format"] = "mp3" }, "extension does not match the format")
    }

    func testMissingProvenance() async throws {
        try await assertInvalid(Fixture.manifest { $0["source"] = nil }, "no source")
        try await assertInvalid(Fixture.manifest {
            var source = $0["source"] as! [String: Any]
            source["sourceName"] = " "
            $0["source"] = source
        }, "empty source name")
        try await assertInvalid(Fixture.manifest {
            var source = $0["source"] as! [String: Any]
            source["rightsStatus"] = nil
            $0["source"] = source
        }, "no rights status")
        try await assertInvalid(Fixture.manifest {
            var source = $0["source"] as! [String: Any]
            source["reciter"] = ""
            $0["source"] = source
        }, "unknown values are null, not empty")
    }

    func testRightsCannotBeClaimed() async throws {
        for claim in ["LICENSED", "PUBLIC_DOMAIN", "ROYALTY_FREE", "PERMITTED_FOR_REDISTRIBUTION"] {
            try await assertInvalid(Fixture.manifest {
                var source = $0["source"] as! [String: Any]
                source["rightsStatus"] = claim
                $0["source"] = source
            }, claim)
        }
    }

    func testAssetCannotPointOutsideTheBundle() async throws {
        for name in ["../test-silence-1s.wav", "HisnAudio/test-silence-1s.wav", "/tmp/x.wav",
                     "https://example.com/x.wav", ".hidden.wav", ""] {
            try await assertInvalid(Fixture.manifest { $0["resourceName"] = name }, name)
        }
    }

    func testSourceURLIsMetadataOnly() async throws {
        try await assertInvalid(Fixture.manifest {
            var source = $0["source"] as! [String: Any]
            source["sourceURL"] = "http://example.com/a.mp3"
            $0["source"] = source
        }, "plain http")
        // An https source URL is accepted as a record; the file still comes from the bundle.
        let repository = try await Fixture.repository(manifest: Fixture.manifest {
            var source = $0["source"] as! [String: Any]
            source["sourceURL"] = "https://example.com/recording"
            $0["source"] = source
        })
        let found = try await repository.audio(for: Fixture.itemId)
        let asset = try XCTUnwrap(found)
        let url = try await repository.resourceURL(for: asset)
        XCTAssertTrue(url.isFileURL)
        XCTAssertFalse(url.absoluteString.contains("example.com"))
    }

    func testInvalidManifest() async throws {
        try await assertInvalid(Data("not json".utf8), "not JSON")
        var object = Fixture.manifestObject()
        object["formatVersion"] = 2
        try await assertInvalid(Fixture.data(object), "format version")
        object = Fixture.manifestObject()
        object["packStatus"] = ""
        try await assertInvalid(Fixture.data(object), "pack status")
        try await assertInvalid(Fixture.manifest { $0["durationMilliseconds"] = 0 }, "duration")
    }
}
