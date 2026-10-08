import XCTest
import IslamicCore
@testable import HisnReading

/// Records what the coordinator asks of the platform PiP surface; the test drives its events.
@MainActor
final class FakePiPSurface: HisnPiPSurface {
    var isSupported = true
    var isPossible = true
    var onEvent: ((HisnPiPSurfaceEvent) -> Void)?
    var contentProvider: (() -> HisnPiPContent?)?
    var calls: [String] = []
    var heartbeat = false
    var refreshes = 0

    func start() { calls.append("start") }
    func stop() { calls.append("stop") }
    func refresh() { refreshes += 1 }
    func setHeartbeat(_ running: Bool) { heartbeat = running }

    func send(_ event: HisnPiPSurfaceEvent) {
        if case .possibleChanged(let possible) = event { isPossible = possible }
        onEvent?(event)
    }

    /// The system started PiP after `start()`.
    func systemStarts() {
        send(.willStart)
        send(.didStart)
    }

    func systemStops() {
        send(.willStop)
        send(.didStop)
    }
}

/// Phase 3C: Hisn PiP lifecycle and controls, on the real bundled book, the TEST_ONLY fixture
/// repository, a fake audio engine and a fake PiP surface.
@MainActor
final class HisnPiPCoordinatorTests: XCTestCase {
    private var engine: FakeAudioEngine!
    private var surface: FakePiPSurface!
    private var controller: HisnReaderController!

    private func makeCoordinator(_ chapterId: String = "hisn-ch-001", at index: Int = 0,
                                 repository: HisnAudioRepository? = nil) async throws -> HisnPiPCoordinator {
        engine = FakeAudioEngine()
        surface = FakePiPSurface()
        let library = try await HisnLibraryCache.library()
        let chapter = try XCTUnwrap(library.chapter(id: chapterId))
        let reader = try XCTUnwrap(HisnReader(chapter: chapter, itemIndex: index))
        var audioRepository: HisnAudioRepository
        if let repository {
            audioRepository = repository
        } else {
            audioRepository = try await Fixture.repository()
        }
        let audio = HisnAudioPlayer(repository: audioRepository, engine: engine, session: FakeAudioSession())
        controller = HisnReaderController(reader: reader, store: InMemoryHisnReadingPositionStore(), audio: audio)
        let pip = HisnPiPCoordinator(controller: controller, surface: surface)
        await controller.audioSettled()
        await settle()
        return pip
    }

    /// Lets the coordinator's main-queue state observation run.
    private func settle() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private var audio: HisnAudioPlayer { controller.audio! }

    // MARK: Availability

    func testAvailableOnlyWithALoadedRecording() async throws {
        let pip = try await makeCoordinator()
        XCTAssertTrue(pip.isAvailable)
        XCTAssertEqual(pip.status, .inactive)
        XCTAssertTrue(surface.calls.isEmpty, "PiP never starts by itself")

        controller.next()
        await controller.audioSettled()
        await settle()
        XCTAssertEqual(audio.availability, .unavailable)
        XCTAssertFalse(pip.isAvailable, "no recording, no PiP")
        XCTAssertNil(pip.content)
        pip.start()
        XCTAssertEqual(pip.failure, .notPossible)
        XCTAssertTrue(surface.calls.isEmpty, "no fake playback without audio")
    }

    func testProductionPackHasNoHisnPiP() async throws {
        let ids = try await HisnLibraryCache.itemIds()
        let pip = try await makeCoordinator(repository: BundledHisnAudioRepository(knownItemIds: ids))
        XCTAssertEqual(audio.availability, .unavailable, "the production pack is empty")
        XCTAssertFalse(pip.isAvailable)
        XCTAssertNil(pip.playbackDuration)
        pip.start()
        XCTAssertTrue(surface.calls.isEmpty)
    }

    func testUnsupportedDevice() async throws {
        let pip = try await makeCoordinator()
        surface.isSupported = false
        XCTAssertFalse(pip.isAvailable)
        pip.start()
        XCTAssertEqual(pip.failure, .notSupported)
        XCTAssertTrue(surface.calls.isEmpty)
    }

    func testNotPossibleYet() async throws {
        let pip = try await makeCoordinator()
        surface.send(.possibleChanged(false))
        XCTAssertFalse(pip.isPossible)
        pip.start()
        XCTAssertEqual(pip.failure, .notPossible)
        surface.send(.possibleChanged(true))
        XCTAssertTrue(pip.isPossible)
        pip.start()
        XCTAssertNil(pip.failure)
        XCTAssertEqual(surface.calls, ["start"])
    }

    // MARK: Lifecycle

    func testManualStartAndStopKeepReaderAndAudioState() async throws {
        let pip = try await makeCoordinator()
        audio.play()
        engine.currentTime = 0.4
        let item = controller.reader.currentItem.id
        let repetition = controller.reader.repetition

        pip.start()
        surface.systemStarts()
        XCTAssertEqual(pip.status, .active)
        XCTAssertTrue(surface.heartbeat, "frames are drawn while PiP is active")
        XCTAssertEqual(audio.state, .playing, "starting PiP does not restart audio")
        XCTAssertEqual(audio.currentTime, 0.4)

        pip.stop()
        XCTAssertEqual(surface.calls, ["start", "stop"])
        surface.systemStops()
        XCTAssertEqual(pip.status, .inactive)
        XCTAssertFalse(surface.heartbeat)
        XCTAssertEqual(audio.state, .playing, "leaving PiP keeps the recording playing")
        XCTAssertEqual(audio.currentTime, 0.4)
        XCTAssertEqual(controller.reader.currentItem.id, item)
        XCTAssertEqual(controller.reader.repetition, repetition)
    }

    func testStartFailureKeepsAudio() async throws {
        let pip = try await makeCoordinator()
        audio.play()
        pip.start()
        surface.send(.willStart)
        surface.send(.failedToStart)
        XCTAssertEqual(pip.status, .inactive)
        XCTAssertEqual(pip.failure, .failedToStart)
        XCTAssertEqual(audio.state, .playing, "a PiP failure is not an audio failure")
        pip.start()
        XCTAssertNil(pip.failure, "trying again clears the message")
    }

    func testStopWhenInactiveDoesNothing() async throws {
        let pip = try await makeCoordinator()
        pip.stop()
        XCTAssertTrue(surface.calls.isEmpty)
        pip.start()
        surface.systemStarts()
        pip.start()
        XCTAssertEqual(surface.calls, ["start"], "no second start while active")
    }

    func testHeartbeatOnlyWhileVisibleOrActive() async throws {
        let pip = try await makeCoordinator()
        XCTAssertFalse(surface.heartbeat)
        pip.setInlineVisible(true)
        XCTAssertTrue(surface.heartbeat)
        pip.setInlineVisible(false)
        XCTAssertFalse(surface.heartbeat)
        pip.start()
        surface.systemStarts()
        XCTAssertTrue(surface.heartbeat)
        pip.close()
        XCTAssertEqual(surface.calls, ["start", "stop"])
        XCTAssertFalse(surface.heartbeat)
    }

    func testNavigatingToAnItemWithoutAudioLeavesPiP() async throws {
        let pip = try await makeCoordinator()
        pip.start()
        surface.systemStarts()
        controller.next()
        await controller.audioSettled()
        await settle()
        XCTAssertEqual(surface.calls.last, "stop", "PiP does not show an item it cannot play")
    }

    func testCompletingTheChapterLeavesPiP() async throws {
        let pip = try await makeCoordinator("hisn-ch-001", at: 0)
        pip.start()
        surface.systemStarts()
        for _ in 0..<100 where !controller.reader.isCompleted { controller.next() }
        XCTAssertTrue(controller.reader.isCompleted)
        await controller.audioSettled()
        await settle()
        XCTAssertFalse(pip.isAvailable)
        XCTAssertEqual(surface.calls.last, "stop")
    }

    // MARK: System controls

    func testSetPlayingDrivesThePlayer() async throws {
        let pip = try await makeCoordinator()
        XCTAssertTrue(pip.isPlaybackPaused)
        pip.setPlaying(true)
        XCTAssertEqual(audio.state, .playing)
        XCTAssertFalse(pip.isPlaybackPaused)
        engine.currentTime = 0.6
        pip.setPlaying(false)
        XCTAssertEqual(audio.state, .paused)
        XCTAssertTrue(pip.isPlaybackPaused)
        pip.setPlaying(true)
        XCTAssertEqual(audio.state, .playing)
        XCTAssertEqual(audio.currentTime, 0.6, "play after pause resumes, it does not restart")
        XCTAssertGreaterThan(surface.refreshes, 0)
    }

    func testSkipSeeksWithinTheRecordingOnly() async throws {
        let pip = try await makeCoordinator()
        let item = controller.reader.currentItem.id
        XCTAssertEqual(pip.playbackDuration, 1)
        pip.skip(by: 0.3)
        XCTAssertEqual(audio.currentTime, 0.3, accuracy: 0.0001)
        pip.skip(by: 10)
        XCTAssertEqual(audio.currentTime, 1, "clamped to the end")
        pip.skip(by: -15)
        XCTAssertEqual(audio.currentTime, 0, "clamped to the start")
        XCTAssertEqual(controller.reader.currentItem.id, item, "skip never changes the dhikr")
    }

    func testRecordingEndDoesNotCountARepetition() async throws {
        let pip = try await makeCoordinator()
        let repetition = controller.reader.repetition
        pip.start()
        surface.systemStarts()
        pip.setPlaying(true)
        engine.finish()
        await settle()
        XCTAssertEqual(audio.state, .finished)
        XCTAssertEqual(controller.reader.repetition, repetition)
        XCTAssertEqual(controller.reader.currentItem.id, "hisn-001-01", "no automatic next")
        XCTAssertEqual(pip.status, .active, "PiP stays open on the finished recording")
        XCTAssertEqual(controller.recitations, 0)
    }

    func testContentIsTheBundledText() async throws {
        let pip = try await makeCoordinator()
        audio.play()
        engine.currentTime = 0.25
        let content = try XCTUnwrap(pip.content)
        XCTAssertEqual(content.itemText, controller.reader.currentItem.arabicText)
        XCTAssertEqual(content.chapterTitle, controller.reader.chapter.titleArabic)
        XCTAssertEqual(content.playback, .playing)
        XCTAssertEqual(content.currentTime, 0.25)
        XCTAssertEqual(content.duration, 1)
        XCTAssertEqual(content.progress ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertTrue(surface.contentProvider?() == content, "the surface reads the same content")
    }

    func testCoordinatorIsReleased() async throws {
        weak var released: HisnPiPCoordinator?
        do {
            let pip = try await makeCoordinator()
            pip.setInlineVisible(true)
            released = pip
        }
        XCTAssertNil(released, "no retain cycle through the surface callbacks")
        XCTAssertNil(surface.contentProvider?())
    }

    // MARK: Paging long text

    func testPagesCoverTheTextExactly() async throws {
        let library = try await HisnLibraryCache.library()
        let longest = try XCTUnwrap(library.book.allItems.max { $0.arabicText.count < $1.arabicText.count })
        XCTAssertGreaterThan(longest.arabicText.count, 1000)
        let text = longest.arabicText
        let pages = HisnPiPPaginator.pages(text) { $0.count <= 300 }
        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertEqual(pages.map { String(text[$0]) }.joined(), text, "nothing changed, dropped or added")
        for (index, page) in pages.enumerated() {
            XCTAssertLessThanOrEqual(text[page].count, 300)
            if index > 0 { XCTAssertEqual(pages[index - 1].upperBound, page.lowerBound, "contiguous") }
            if index < pages.count - 1 {
                XCTAssertTrue(text[text.index(before: page.upperBound)].isWhitespace, "breaks after a space")
            }
        }
    }

    func testShortTextIsOnePageAndOverlongWordsAreKept() {
        let text = "سبحان الله"
        XCTAssertEqual(HisnPiPPaginator.pages(text) { _ in true }.map { String(text[$0]) }, [text])
        XCTAssertEqual(HisnPiPPaginator.pages("") { _ in true }, [])
        let pages = HisnPiPPaginator.pages(text) { _ in false }
        XCTAssertEqual(pages.map { String(text[$0]) }, ["سبحان ", "الله"], "never drops text that does not fit")
    }

    // MARK: Device-test fixture

    func testDeviceTestManifestIsTestOnly() async throws {
        let manifest = try Data(contentsOf: Fixture.directory.appendingPathComponent("hisn_audio.device-test.json"))
        let ids = try await HisnLibraryCache.itemIds()
        let testRepository = BundledHisnAudioRepository(knownItemIds: ids, manifest: .data(manifest),
                                                        audioDirectory: Fixture.audioDirectory, allowedUsage: [.testOnly])
        let assets = try await testRepository.allAssets()
        XCTAssertEqual(assets.map(\.itemId), ["hisn-001-01", "hisn-001-04"])
        XCTAssertTrue(assets.allSatisfy { $0.usage == .testOnly && $0.source.reciter == nil })
        XCTAssertTrue(assets.allSatisfy { $0.source.rightsStatus == .pendingPreReleaseReview })
        let production = BundledHisnAudioRepository(knownItemIds: ids, manifest: .data(manifest),
                                                    audioDirectory: Fixture.audioDirectory)
        do {
            _ = try await production.allAssets()
            XCTFail("the production repository must reject TEST_ONLY assets")
        } catch {}
    }
}
