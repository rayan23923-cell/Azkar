import XCTest
import IslamicCore
@testable import HisnReading

/// Phase 3I: Hisn PiP checks beyond Phase 3C, run on the TEST_ONLY fixture, a fake engine,
/// a fake audio session and a fake PiP surface (no device in CI).
@MainActor
final class HisnPiPValidationTests: XCTestCase {
    private var engine: FakeAudioEngine!
    private var session: FakeAudioSession!
    private var surface: FakePiPSurface!
    private var controller: HisnReaderController!

    private func make() async throws -> HisnPiPCoordinator {
        engine = FakeAudioEngine()
        session = FakeAudioSession()
        surface = FakePiPSurface()
        let library = try await HisnLibraryCache.library()
        let chapter = try XCTUnwrap(library.chapter(id: "hisn-ch-001"))
        let reader = try XCTUnwrap(HisnReader(chapter: chapter))
        let audio = HisnAudioPlayer(repository: try await Fixture.repository(), engine: engine, session: session)
        controller = HisnReaderController(reader: reader, store: InMemoryHisnReadingPositionStore(), audio: audio)
        let pip = HisnPiPCoordinator(controller: controller, surface: surface)
        await controller.audioSettled()
        await settle()
        return pip
    }

    private func settle() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private var audio: HisnAudioPlayer { controller.audio! }

    private func startPlayingInPiP(_ pip: HisnPiPCoordinator) {
        pip.start()
        surface.systemStarts()
        pip.setPlaying(true)
    }

    func testInterruptionPausesAndPiPStays() async throws {
        let pip = try await make()
        startPlayingInPiP(pip)
        XCTAssertEqual(pip.status, .active)
        XCTAssertFalse(pip.isPlaybackPaused)
        session.send(.interruptionBegan)
        await settle()
        XCTAssertEqual(audio.state, .paused)
        XCTAssertTrue(audio.pausedBySystem)
        XCTAssertTrue(pip.isPlaybackPaused, "the system controls show paused")
        XCTAssertEqual(pip.status, .active, "the window stays; the user decides")
        session.send(.interruptionEnded(shouldResume: true))
        await settle()
        XCTAssertEqual(audio.state, .paused, "never resumes by itself")
        pip.setPlaying(true)
        XCTAssertEqual(audio.state, .playing)
    }

    func testHeadphonesRemovedPausesPlayback() async throws {
        let pip = try await make()
        startPlayingInPiP(pip)
        session.send(.outputDeviceUnavailable)
        await settle()
        XCTAssertEqual(audio.state, .paused)
        XCTAssertTrue(pip.isPlaybackPaused)
        XCTAssertEqual(pip.status, .active)
        session.send(.routeChanged)
        XCTAssertEqual(audio.state, .paused, "a new route does not resume")
    }

    func testSeekIsClampedToTheRecording() async throws {
        let pip = try await make()
        startPlayingInPiP(pip)
        let duration = try XCTUnwrap(pip.playbackDuration)
        pip.skip(by: 1_000)
        XCTAssertEqual(engine.currentTime, duration, accuracy: 0.001)
        pip.skip(by: -1_000)
        XCTAssertEqual(engine.currentTime, 0, accuracy: 0.001)
        XCTAssertEqual(controller.reader.itemIndex, 0, "seeking never changes the dhikr")
    }

    func testRepeatedStartStopCycles() async throws {
        let pip = try await make()
        for _ in 0..<3 {
            pip.start()
            surface.systemStarts()
            XCTAssertEqual(pip.status, .active)
            XCTAssertTrue(surface.heartbeat)
            pip.stop()
            surface.systemStops()
            XCTAssertEqual(pip.status, .inactive)
            XCTAssertFalse(surface.heartbeat, "no drawing once PiP is gone and the preview is hidden")
        }
        XCTAssertEqual(surface.calls, ["start", "stop", "start", "stop", "start", "stop"])
        XCTAssertNil(pip.failure)
    }

    func testPauseAndPlayFromTheSystemControls() async throws {
        let pip = try await make()
        startPlayingInPiP(pip)
        pip.setPlaying(false)
        XCTAssertEqual(audio.state, .paused)
        XCTAssertTrue(pip.isPlaybackPaused)
        pip.setPlaying(true)
        XCTAssertEqual(audio.state, .playing)
        XCTAssertEqual(pip.content?.playback, .playing)
    }

    /// Every display item splits into PiP pages that give back its text exactly, in order,
    /// breaking only after whitespace (long Arabic text, multiple pages, RTL text untouched).
    func testEveryItemPaginatesWithoutChangingTheText() async throws {
        let library = try await HisnLibraryCache.library()
        var multiPage = 0
        for item in library.book.allItems {
            let text = item.arabicText
            let pages = HisnPiPPaginator.pages(text) { $0.count <= 120 }
            XCTAssertEqual(pages.map { String(text[$0]) }.joined(), text, item.id)
            for (previous, next) in zip(pages, pages.dropFirst()) {
                XCTAssertEqual(previous.upperBound, next.lowerBound, item.id)
            }
            if pages.count > 1 { multiPage += 1 }
        }
        XCTAssertGreaterThan(multiPage, 20, "long items really span several pages")
    }
}
