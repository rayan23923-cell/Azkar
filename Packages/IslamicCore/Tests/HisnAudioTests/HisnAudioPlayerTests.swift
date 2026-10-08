import XCTest
import IslamicCore
@testable import HisnReading

/// Phase 3B: the playback state machine and the player, on a fake engine and session.
@MainActor
final class HisnAudioPlayerTests: XCTestCase {
    private var engine: FakeAudioEngine!
    private var session: FakeAudioSession!

    override func setUp() async throws {
        engine = FakeAudioEngine()
        session = FakeAudioSession()
    }

    private func makePlayer(_ repository: HisnAudioRepository = StubAudioRepository(
        assets: ["hisn-001-01": StubAudioRepository.asset(for: "hisn-001-01")])) -> HisnAudioPlayer {
        HisnAudioPlayer(repository: repository, engine: engine, session: session)
    }

    private func loadedPlayer() async -> HisnAudioPlayer {
        let player = makePlayer()
        await player.load(itemId: "hisn-001-01")
        return player
    }

    // MARK: State machine

    func testValidTransitions() {
        typealias S = HisnAudioPlaybackState
        XCTAssertEqual(S.idle.applying(.load), .loading)
        XCTAssertEqual(S.loading.applying(.loaded), .ready)
        XCTAssertEqual(S.ready.applying(.play), .playing)
        XCTAssertEqual(S.playing.applying(.pause), .paused)
        XCTAssertEqual(S.paused.applying(.resume), .playing)
        XCTAssertEqual(S.paused.applying(.play), .playing)
        XCTAssertEqual(S.playing.applying(.finish), .finished)
        XCTAssertEqual(S.finished.applying(.play), .playing)
        XCTAssertEqual(S.playing.applying(.stop), .ready)
        XCTAssertEqual(S.paused.applying(.stop), .ready)
        XCTAssertEqual(S.finished.applying(.stop), .ready)
        XCTAssertEqual(S.playing.applying(.seek), .playing)
        XCTAssertEqual(S.paused.applying(.seek), .paused)
        XCTAssertEqual(S.finished.applying(.seek), .paused)
        for state in [S.idle, .loading, .ready, .playing, .paused, .finished, .failed(.couldNotPlay)] {
            XCTAssertEqual(state.applying(.fail(.couldNotLoad)), .failed(.couldNotLoad), "\(state)")
            XCTAssertEqual(state.applying(.unload), .idle, "\(state)")
            XCTAssertEqual(state.applying(.load), .loading, "\(state)")
        }
    }

    func testInvalidTransitionsAreRefused() {
        typealias S = HisnAudioPlaybackState
        XCTAssertNil(S.idle.applying(.play))
        XCTAssertNil(S.idle.applying(.pause))
        XCTAssertNil(S.idle.applying(.stop))
        XCTAssertNil(S.idle.applying(.seek))
        XCTAssertNil(S.idle.applying(.finish))
        XCTAssertNil(S.loading.applying(.play))
        XCTAssertNil(S.ready.applying(.pause))
        XCTAssertNil(S.ready.applying(.resume))
        XCTAssertNil(S.ready.applying(.finish))
        XCTAssertNil(S.playing.applying(.play))
        XCTAssertNil(S.playing.applying(.resume))
        XCTAssertNil(S.paused.applying(.pause))
        XCTAssertNil(S.paused.applying(.finish))
        XCTAssertNil(S.finished.applying(.pause))
        XCTAssertNil(S.failed(.unavailable).applying(.play))
        XCTAssertNil(S.ready.applying(.loaded))
    }

    // MARK: Player

    func testInitialState() {
        let player = makePlayer()
        XCTAssertEqual(player.state, .idle)
        XCTAssertEqual(player.availability, .unknown)
        XCTAssertNil(player.currentAudioItemId)
        XCTAssertNil(player.duration)
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertEqual(session.activations, 0, "the session is not touched before playback")
    }

    func testLoadPreparesWithoutPlaying() async {
        let player = await loadedPlayer()
        XCTAssertEqual(player.state, .ready)
        XCTAssertEqual(player.availability, .available)
        XCTAssertEqual(player.currentAudioItemId, "hisn-001-01")
        XCTAssertEqual(player.currentAsset?.itemId, "hisn-001-01")
        XCTAssertEqual(player.duration, 1)
        XCTAssertFalse(engine.isPlaying, "no autoplay")
        XCTAssertEqual(session.activations, 0)
    }

    func testItemWithoutAudio() async {
        let player = makePlayer()
        await player.load(itemId: "hisn-001-02")
        XCTAssertEqual(player.state, .idle)
        XCTAssertEqual(player.availability, .unavailable)
        XCTAssertNil(player.currentAsset)
        player.play()
        XCTAssertEqual(player.state, .idle, "nothing to play")
        XCTAssertFalse(engine.calls.contains("play"))
    }

    func testPlayPauseResumeStop() async {
        let player = await loadedPlayer()
        player.play()
        XCTAssertEqual(player.state, .playing)
        XCTAssertTrue(engine.isPlaying)
        XCTAssertEqual(session.activations, 1, "the session is activated when playback starts")
        engine.currentTime = 0.4
        player.pause()
        XCTAssertEqual(player.state, .paused)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(player.currentTime, 0.4)
        player.resume()
        XCTAssertEqual(player.state, .playing)
        XCTAssertEqual(player.currentTime, 0.4, "resume continues where it paused")
        player.stop()
        XCTAssertEqual(player.state, .ready)
        XCTAssertEqual(player.currentTime, 0, "stop rewinds")
        XCTAssertFalse(engine.isPlaying)
    }

    func testToggle() async {
        let player = await loadedPlayer()
        player.togglePlayback()
        XCTAssertEqual(player.state, .playing)
        player.togglePlayback()
        XCTAssertEqual(player.state, .paused)
        player.togglePlayback()
        XCTAssertEqual(player.state, .playing)
    }

    func testSeekIsClamped() async {
        let player = await loadedPlayer()
        player.seek(to: 0.5)
        XCTAssertEqual(player.currentTime, 0.5)
        XCTAssertEqual(player.state, .ready)
        player.seek(to: 9)
        XCTAssertEqual(player.currentTime, 1)
        player.seek(to: -3)
        XCTAssertEqual(player.currentTime, 0)
        player.play()
        player.seek(to: 0.25)
        XCTAssertEqual(player.state, .playing)
        XCTAssertEqual(player.currentTime, 0.25)
    }

    func testFinishStopsAndReplayStartsOver() async {
        let player = await loadedPlayer()
        player.play()
        engine.finish()
        XCTAssertEqual(player.state, .finished)
        XCTAssertEqual(player.currentAudioItemId, "hisn-001-01", "stays on the same recording")
        player.play()
        XCTAssertEqual(player.state, .playing)
        XCTAssertEqual(player.currentTime, 0, "replay starts from the beginning")
    }

    func testFailures() async {
        var player = self.makePlayer(StubAudioRepository(failure: ContentError.invalidContent("bad pack")))
        await player.load(itemId: "hisn-001-01")
        XCTAssertEqual(player.state, .failed(.unavailable))

        engine.failLoad = true
        player = self.makePlayer()
        await player.load(itemId: "hisn-001-01")
        XCTAssertEqual(player.state, .failed(.couldNotLoad))

        engine = FakeAudioEngine()
        session.refuse = true
        player = self.makePlayer()
        await player.load(itemId: "hisn-001-01")
        player.play()
        XCTAssertEqual(player.state, .failed(.couldNotPlay), "session refused")

        engine = FakeAudioEngine()
        session.refuse = false
        engine.refusePlay = true
        player = self.makePlayer()
        await player.load(itemId: "hisn-001-01")
        player.play()
        XCTAssertEqual(player.state, .failed(.couldNotPlay), "engine refused")

        engine = FakeAudioEngine()
        player = self.makePlayer()
        await player.load(itemId: "hisn-001-01")
        player.play()
        engine.onFailure?()
        XCTAssertEqual(player.state, .failed(.couldNotPlay), "decode error while playing")
        await player.load(itemId: "hisn-001-01")
        XCTAssertEqual(player.state, .ready, "a new load recovers")
    }

    func testIllegalCallsDoNothing() async {
        let player = makePlayer()
        player.pause()
        player.resume()
        player.stop()
        player.seek(to: 1)
        XCTAssertEqual(player.state, .idle)
        XCTAssertTrue(engine.calls.isEmpty)
        await player.load(itemId: "hisn-001-01")
        player.resume()
        player.pause()
        XCTAssertEqual(player.state, .ready)
    }

    func testNewerLoadWins() async {
        let player = makePlayer(StubAudioRepository(assets: [
            "hisn-001-01": StubAudioRepository.asset(for: "hisn-001-01"),
            "hisn-001-02": StubAudioRepository.asset(for: "hisn-001-02"),
        ], slow: ["hisn-001-01"]))
        let slowLoad = Task { await player.load(itemId: "hisn-001-01") }
        while player.currentAudioItemId != "hisn-001-01" { await Task.yield() }
        await player.load(itemId: "hisn-001-02")
        await slowLoad.value
        XCTAssertEqual(player.currentAudioItemId, "hisn-001-02")
        XCTAssertEqual(player.currentAsset?.itemId, "hisn-001-02", "the older, slower lookup is discarded")
        XCTAssertEqual(player.state, .ready)
    }

    func testUnloadClears() async {
        let player = await loadedPlayer()
        player.play()
        await player.load(itemId: nil)
        XCTAssertEqual(player.state, .idle)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertNil(player.currentAudioItemId)
    }

    // MARK: Interruptions and routes

    func testInterruptionPausesAndStaysPaused() async {
        let player = await loadedPlayer()
        player.play()
        session.send(.interruptionBegan)
        XCTAssertEqual(player.state, .paused)
        XCTAssertTrue(player.pausedBySystem)
        XCTAssertFalse(engine.isPlaying)
        session.send(.interruptionEnded(shouldResume: true))
        XCTAssertEqual(player.state, .paused, "no automatic resume")
        XCTAssertFalse(engine.isPlaying)
        player.resume()
        XCTAssertEqual(player.state, .playing)
        XCTAssertFalse(player.pausedBySystem)
    }

    func testInterruptionWhileNotPlayingChangesNothing() async {
        let player = await loadedPlayer()
        session.send(.interruptionBegan)
        session.send(.interruptionEnded(shouldResume: false))
        XCTAssertEqual(player.state, .ready)
        XCTAssertFalse(player.pausedBySystem)
    }

    func testHeadphonesRemovedPauses() async {
        let player = await loadedPlayer()
        player.play()
        session.send(.routeChanged)
        XCTAssertEqual(player.state, .playing, "a new device does not stop playback")
        session.send(.outputDeviceUnavailable)
        XCTAssertEqual(player.state, .paused)
        XCTAssertTrue(player.pausedBySystem)
    }

    func testMediaServicesReset() async {
        let player = await loadedPlayer()
        player.play()
        session.send(.mediaServicesReset)
        XCTAssertEqual(player.state, .failed(.couldNotPlay))
        await player.load(itemId: "hisn-001-01")
        XCTAssertEqual(player.state, .ready)
    }
}
