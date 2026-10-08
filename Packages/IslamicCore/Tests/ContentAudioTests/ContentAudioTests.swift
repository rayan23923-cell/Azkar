import XCTest
import IslamicCore
import ContentKit
@testable import HisnReading
@testable import ContentAudio

@MainActor
final class FakeEngine: HisnAudioEngine {
    var onFinish: (() -> Void)?
    var onFailure: (() -> Void)?
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var loadedURL: URL?
    var isPlaying = false

    func load(url: URL) throws {
        loadedURL = url
        duration = 10
        currentTime = 0
    }

    func play() -> Bool {
        guard loadedURL != nil else { return false }
        isPlaying = true
        return true
    }

    func pause() { isPlaying = false }
    func stop() { isPlaying = false; currentTime = 0 }
    func seek(to time: TimeInterval) { currentTime = time }
    func unload() { loadedURL = nil; isPlaying = false; duration = 0; currentTime = 0 }

    func finish() {
        isPlaying = false
        currentTime = duration
        onFinish?()
    }
}

@MainActor
final class FakeSession: HisnAudioSessionControlling {
    var onEvent: ((HisnAudioSessionEvent) -> Void)?
    func activateForPlayback() throws {}
    func send(_ event: HisnAudioSessionEvent) { onEvent?(event) }
}

struct StubRepository: HisnAudioRepository {
    var ids: Set<String>

    func audio(for itemId: String) async throws -> HisnAudioAsset? {
        guard ids.contains(itemId) else { return nil }
        return HisnAudioAsset(id: "a-\(itemId)", itemId: itemId, usage: .testOnly, resourceName: "x.wav", format: .wav,
                              durationMilliseconds: 10_000, byteCount: 1, sha256: String(repeating: "0", count: 64),
                              source: HisnAudioSource(sourceName: "stub", sourceURL: nil, reciter: nil,
                                                      narrationStyle: nil, retrievalDate: nil,
                                                      licenseOrRightsStatement: nil,
                                                      rightsStatus: .pendingPreReleaseReview))
    }

    func resourceURL(for asset: HisnAudioAsset) async throws -> URL { URL(fileURLWithPath: "/stub/\(asset.itemId)") }
    func allAssets() async throws -> [HisnAudioAsset] { [] }
}

@MainActor
final class FakeSurface: HisnPiPSurface {
    var isSupported = true
    var isPossible = true
    var onEvent: ((HisnPiPSurfaceEvent) -> Void)?
    var contentProvider: (() -> HisnPiPContent?)?
    var started = 0
    var stopped = 0
    var refreshes = 0
    var heartbeat = false

    func start() {
        started += 1
        onEvent?(.willStart)
        onEvent?(.didStart)
    }

    func stop() {
        stopped += 1
        onEvent?(.willStop)
        onEvent?(.didStop)
    }

    func refresh() { refreshes += 1 }
    func setHeartbeat(_ running: Bool) { heartbeat = running }
}

@MainActor
final class AudioQueueTests: XCTestCase {
    private let items = (1...4).map { AudioQueueItem(ref: .quranVerse(surah: 1, ayah: $0), title: "الفاتحة", text: "آية \($0)") }

    private func makeQueue(recorded: [Int]) -> (AudioQueueController, FakeEngine, FakeSession) {
        let engine = FakeEngine()
        let session = FakeSession()
        let ids = Set(recorded.map { ContentRef.quranVerse(surah: 1, ayah: $0).string })
        let player = HisnAudioPlayer(repository: StubRepository(ids: ids), engine: engine, session: session)
        return (AudioQueueController(player: player), engine, session)
    }

    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    func testContinuousPlaySkipsItemsWithoutRecordingsAndStopsAtTheEnd() async {
        let (queue, engine, _) = makeQueue(recorded: [1, 3])
        await queue.load(items)
        XCTAssertEqual(queue.player.availability, .available)
        queue.play()
        XCTAssertEqual(queue.player.state, .playing)
        engine.finish()
        await settle()
        XCTAssertEqual(queue.index, 2)
        XCTAssertEqual(queue.player.state, .playing)
        engine.finish()
        await settle()
        XCTAssertTrue(queue.reachedEnd)
        XCTAssertNotEqual(queue.player.state, .playing)
    }

    func testNotContinuousStaysOnTheFinishedItem() async {
        let (queue, engine, _) = makeQueue(recorded: [1, 2])
        queue.continuous = false
        await queue.load(items)
        queue.play()
        engine.finish()
        await settle()
        XCTAssertEqual(queue.index, 0)
        XCTAssertEqual(queue.player.state, .finished)
    }

    func testNextAndPreviousKeepPlayingAndRestartFirst() async {
        let (queue, engine, _) = makeQueue(recorded: [1, 2, 3, 4])
        await queue.load(items, start: 1)
        queue.play()
        await queue.next()
        XCTAssertEqual(queue.index, 2)
        XCTAssertEqual(queue.player.state, .playing)
        engine.currentTime = 5
        await queue.previous()
        XCTAssertEqual(queue.index, 2)
        XCTAssertEqual(engine.currentTime, 0)
        await queue.previous()
        XCTAssertEqual(queue.index, 1)
        XCTAssertEqual(queue.player.state, .playing)
        await queue.jump(to: 9)
        XCTAssertEqual(queue.index, 1)
    }

    func testInterruptionPausesAndNothingResumesByItself() async {
        let (queue, _, session) = makeQueue(recorded: [1])
        await queue.load(items)
        queue.play()
        session.send(.interruptionBegan)
        XCTAssertEqual(queue.player.state, .paused)
        session.send(.interruptionEnded(shouldResume: true))
        XCTAssertEqual(queue.player.state, .paused)
        session.send(.outputDeviceUnavailable)
        XCTAssertEqual(queue.player.state, .paused)
    }

    func testSnapshotAndRestore() async {
        let (queue, engine, _) = makeQueue(recorded: [1, 2, 3, 4])
        await queue.load(items, start: 2)
        engine.currentTime = 4
        let snapshot = try! XCTUnwrap(queue.snapshot)
        XCTAssertEqual(snapshot.index, 2)
        let data = try! JSONEncoder().encode(snapshot)
        let decoded = try! JSONDecoder().decode(AudioQueueSnapshot.self, from: data)

        let (restored, restoredEngine, _) = makeQueue(recorded: [1, 2, 3, 4])
        // Item 2 no longer exists: dropped; the saved item is still found.
        await restored.restore(decoded) { ref in self.items.first { $0.ref == ref && $0.ref != self.items[1].ref } }
        XCTAssertEqual(restored.items.count, 3)
        XCTAssertEqual(restored.current?.ref, items[2].ref)
        XCTAssertEqual(restoredEngine.currentTime, 4)
        XCTAssertNotEqual(restored.player.state, .playing)
    }

    func testEmptyQueue() async {
        let (queue, _, _) = makeQueue(recorded: [])
        await queue.load([])
        XCTAssertNil(queue.current)
        XCTAssertNil(queue.snapshot)
        await queue.next()
        XCTAssertEqual(queue.index, 0)
    }
}

@MainActor
final class QueuePiPTests: XCTestCase {
    func testPiPFollowsTheQueue() async {
        let engine = FakeEngine()
        let ids: Set<String> = [ContentRef.quranVerse(surah: 1, ayah: 1).string]
        let player = HisnAudioPlayer(repository: StubRepository(ids: ids), engine: engine, session: FakeSession())
        let queue = AudioQueueController(player: player)
        let surface = FakeSurface()
        let pip = QueuePiPCoordinator(queue: queue, surface: surface)
        let items = [AudioQueueItem(ref: .quranVerse(surah: 1, ayah: 1), title: "الفاتحة", text: "نص الآية"),
                     AudioQueueItem(ref: .quranVerse(surah: 1, ayah: 2), title: "الفاتحة", text: "نص آخر")]

        pip.start()
        XCTAssertEqual(pip.failure, .notPossible)

        await queue.load(items)
        XCTAssertTrue(pip.isAvailable)
        XCTAssertEqual(pip.content?.itemText, "نص الآية")
        XCTAssertEqual(pip.content?.chapterTitle, "الفاتحة")
        pip.start()
        XCTAssertEqual(pip.status, .active)
        XCTAssertTrue(surface.heartbeat)

        pip.setPlaying(true)
        XCTAssertEqual(player.state, .playing)
        pip.skip(by: 100)
        XCTAssertEqual(engine.currentTime, 10)
        pip.skip(by: -100)
        XCTAssertEqual(engine.currentTime, 0)
        pip.setPlaying(false)
        XCTAssertEqual(player.state, .paused)

        // The next item has no recording: PiP does not pretend.
        await queue.next()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertFalse(pip.isAvailable)
        XCTAssertNil(pip.content)
        XCTAssertEqual(pip.status, .inactive)
        XCTAssertGreaterThanOrEqual(surface.stopped, 1)
        pip.close()
        XCTAssertFalse(surface.heartbeat)
    }
}

final class ContentAudioPackTests: XCTestCase {
    func testBundledPackIsEmptyAndPending() async throws {
        let repository = ContentAudioPack.repository(knownRefs: [.quranVerse(surah: 1, ayah: 1), .dhikr("dhikr-morning-001")])
        let manifest = try await repository.manifest()
        XCTAssertEqual(manifest.packStatus, "PENDING_RIGHTS_AND_ASSETS")
        XCTAssertTrue(manifest.assets.isEmpty)
        let none = try await repository.audio(for: ContentRef.quranVerse(surah: 1, ayah: 1).string)
        XCTAssertNil(none)
        XCTAssertEqual(ContentAudioPack.releaseBlockers(manifest),
                       ["packStatus is PENDING_RIGHTS_AND_ASSETS, not READY", "no recordings"])
    }

    func testThePackRefusesUnknownRefs() async throws {
        let manifest = """
        {"formatVersion":1,"packStatus":"PENDING_RIGHTS_AND_ASSETS","assets":[{"id":"a1","itemId":"quran:9:999",
        "usage":"PRODUCTION","resourceName":"a1.m4a","format":"m4a","durationMilliseconds":1000,"byteCount":1,
        "sha256":"\(String(repeating: "0", count: 64))","source":{"sourceName":"x","sourceURL":null,"reciter":null,
        "narrationStyle":null,"retrievalDate":null,"licenseOrRightsStatement":null,
        "rightsStatus":"PENDING_PRE_RELEASE_REVIEW"}}]}
        """
        let repository = ContentAudioPack.repository(knownRefs: [.quranVerse(surah: 1, ayah: 1)],
                                                     manifest: .data(Data(manifest.utf8)))
        do {
            _ = try await repository.allAssets()
            XCTFail("an asset for an unknown reference must be refused")
        } catch let error as ContentError {
            guard case .invalidContent = error else { return XCTFail("\(error)") }
        }
    }
}
