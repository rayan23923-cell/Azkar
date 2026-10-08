import Foundation
import XCTest
import IslamicCore
@testable import HisnReading

enum Fixture {
    static var directory: URL { Bundle.module.url(forResource: "Fixtures", withExtension: nil)! }
    static var audioDirectory: URL { directory.appendingPathComponent("HisnAudio", isDirectory: true) }
    static var manifestData: Data { try! Data(contentsOf: directory.appendingPathComponent("hisn_audio.test.json")) }
    static let assetId = "hisn-audio-test-001-01"
    static let itemId = "hisn-001-01"

    /// The fixture manifest as a mutable JSON object, for building invalid variants.
    static func manifestObject() -> [String: Any] {
        try! JSONSerialization.jsonObject(with: manifestData) as! [String: Any]
    }

    static func data(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    /// The manifest with its first asset changed by `edit`.
    static func manifest(editingAsset edit: (inout [String: Any]) -> Void) -> Data {
        var object = manifestObject()
        var assets = object["assets"] as! [[String: Any]]
        edit(&assets[0])
        object["assets"] = assets
        return data(object)
    }

    static func repository(manifest: Data = manifestData, audioDirectory: URL = audioDirectory,
                           knownItemIds: Set<String>? = nil) async throws -> BundledHisnAudioRepository {
        var ids = knownItemIds ?? []
        if knownItemIds == nil { ids = try await HisnLibraryCache.itemIds() }
        return BundledHisnAudioRepository(knownItemIds: ids, manifest: .data(manifest),
                                          audioDirectory: audioDirectory, allowedUsage: [.testOnly])
    }
}

enum HisnLibraryCache {
    private static var cached: HisnLibrary?

    static func library() async throws -> HisnLibrary {
        if let cached { return cached }
        let library = HisnLibrary(book: try await BundledHisnRepository().loadBook())
        cached = library
        return library
    }

    static func itemIds() async throws -> Set<String> {
        Set(try await library().book.allItems.map(\.id))
    }
}

/// Records what the player asks of the low-level engine; no real audio.
@MainActor
final class FakeAudioEngine: HisnAudioEngine {
    var onFinish: (() -> Void)?
    var onFailure: (() -> Void)?
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var loadedURL: URL?
    var isPlaying = false
    var failLoad = false
    var refusePlay = false
    var calls: [String] = []

    func load(url: URL) throws {
        calls.append("load")
        if failLoad { throw CocoaError(.fileReadCorruptFile) }
        loadedURL = url
        duration = 1
        currentTime = 0
    }

    func play() -> Bool {
        calls.append("play")
        guard !refusePlay, loadedURL != nil else { return false }
        isPlaying = true
        return true
    }

    func pause() {
        calls.append("pause")
        isPlaying = false
    }

    func stop() {
        calls.append("stop")
        isPlaying = false
        currentTime = 0
    }

    func seek(to time: TimeInterval) {
        calls.append("seek")
        currentTime = time
    }

    func unload() {
        calls.append("unload")
        loadedURL = nil
        isPlaying = false
        duration = 0
        currentTime = 0
    }

    /// The file played to its end.
    func finish() {
        isPlaying = false
        currentTime = duration
        onFinish?()
    }
}

@MainActor
final class FakeAudioSession: HisnAudioSessionControlling {
    var onEvent: ((HisnAudioSessionEvent) -> Void)?
    var activations = 0
    var refuse = false

    func activateForPlayback() throws {
        if refuse { throw CocoaError(.featureUnsupported) }
        activations += 1
    }

    func send(_ event: HisnAudioSessionEvent) {
        onEvent?(event)
    }
}

/// An in-memory repository: item id → asset, or a failure for every lookup.
struct StubAudioRepository: HisnAudioRepository {
    var assets: [String: HisnAudioAsset] = [:]
    var failure: Error?
    /// Item ids whose lookup is slow, to test that a newer load wins.
    var slow: Set<String> = []

    func audio(for itemId: String) async throws -> HisnAudioAsset? {
        if let failure { throw failure }
        if slow.contains(itemId) { try await Task.sleep(nanoseconds: 200_000_000) }
        return assets[itemId]
    }

    func resourceURL(for asset: HisnAudioAsset) async throws -> URL {
        URL(fileURLWithPath: "/fixtures/\(asset.resourceName)")
    }

    func allAssets() async throws -> [HisnAudioAsset] { Array(assets.values) }

    static func asset(for itemId: String) -> HisnAudioAsset {
        HisnAudioAsset(id: "audio-\(itemId)", itemId: itemId, usage: .testOnly, resourceName: "\(itemId).wav",
                       format: .wav, durationMilliseconds: 1000, byteCount: 1, sha256: String(repeating: "0", count: 64),
                       source: HisnAudioSource(sourceName: "stub", sourceURL: nil, reciter: nil, narrationStyle: nil,
                                               retrievalDate: nil, licenseOrRightsStatement: nil,
                                               rightsStatus: .pendingPreReleaseReview))
    }
}
