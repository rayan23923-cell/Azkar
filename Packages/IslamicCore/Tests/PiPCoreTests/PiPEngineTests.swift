import XCTest
@testable import PiPCore

@MainActor
final class PiPEngineTests: XCTestCase {
    private var clock: TestClock!
    private var store: InMemoryPiPSessionStore!

    private func makeEngine(enabled: Bool = true, declared: Bool = true, wordsPerPage: Int = 3) -> PiPEngine {
        clock = TestClock()
        store = InMemoryPiPSessionStore()
        let clock = clock!
        return PiPEngine(paginator: FakePaginator(wordsPerPage: wordsPerPage), sessionStore: store,
                         availability: PiPAvailability(backgroundModeDeclared: declared, userEnabled: enabled),
                         pageTurnInterval: 8, now: { clock.date })
    }

    /// Engine, a registered controller and provider, PiP started and shown by the system.
    private func running(_ provider: FakeProvider = FakeProvider())
        -> (PiPEngine, FakePiPController, FakeProvider) {
        let engine = makeEngine()
        let controller = FakePiPController()
        engine.register(controller, provider: provider)
        engine.start(provider, on: controller)
        controller.systemStarts()
        return (engine, controller, provider)
    }

    // MARK: Start

    func testManualStartRunsTheSystemPiP() {
        let engine = makeEngine()
        let controller = FakePiPController()
        let provider = FakeProvider(index: 1)
        engine.register(controller, provider: provider)
        XCTAssertEqual(engine.state, .inactive)
        XCTAssertTrue(controller.calls.isEmpty, "nothing starts by itself")
        engine.start(provider, on: controller)
        XCTAssertEqual(controller.calls, ["start"])
        XCTAssertEqual(engine.state, .starting)
        XCTAssertTrue(controller.heartbeat)
        controller.systemStarts()
        XCTAssertEqual(engine.state, .paused, "text without a recording starts paused")
        XCTAssertEqual(engine.activeContentType, .dhikr)
        XCTAssertTrue(engine.isRunning(provider))
    }

    func testOpeningPiPChangesNoProgress() {
        let provider = FakeProvider(index: 2)
        let (_, _, _) = running(provider)
        XCTAssertEqual(provider.index, 2)
        XCTAssertTrue(provider.navigations.isEmpty)
        XCTAssertEqual(provider.persists, 0)
    }

    func testStartIsRefusedWhenNotPossible() {
        let disabled = makeEngine(enabled: false)
        let controller = FakePiPController()
        let provider = FakeProvider()
        disabled.start(provider, on: controller)
        XCTAssertEqual(disabled.state, .error(.disabled))
        XCTAssertEqual(disabled.failure(for: provider), .disabled)
        XCTAssertTrue(controller.calls.isEmpty)

        let undeclared = makeEngine(declared: false)
        undeclared.start(provider, on: controller)
        XCTAssertEqual(undeclared.state, .error(.disabled), "no PiP without the background mode")
        XCTAssertFalse(undeclared.canOffer(on: controller))

        let engine = makeEngine()
        controller.isSupported = false
        engine.start(provider, on: controller)
        XCTAssertEqual(engine.state, .error(.notSupported))
        XCTAssertFalse(engine.canOffer(on: controller))

        controller.isSupported = true
        provider.completed = true
        engine.start(provider, on: controller)
        XCTAssertEqual(engine.state, .error(.noContent))
        XCTAssertTrue(controller.calls.isEmpty)
    }

    func testFailureShowsOnlyOnTheRequestingScreen() {
        let engine = makeEngine()
        let controller = FakePiPController()
        let provider = FakeProvider()
        let other = FakeProvider(.dua)
        engine.register(controller, provider: provider)
        engine.start(provider, on: controller)
        controller.send(.failedToStart)
        XCTAssertEqual(engine.state, .error(.failedToStart))
        XCTAssertEqual(engine.failure(for: provider), .failedToStart)
        XCTAssertNil(engine.failure(for: other))
        XCTAssertFalse(engine.isRunning(provider))
    }

    func testStartingTheRunningSessionAgainDoesNothing() {
        let (engine, controller, provider) = running()
        engine.start(provider, on: controller)
        XCTAssertEqual(controller.calls, ["start"])
    }

    // MARK: Navigation

    func testSkipMovesBetweenItems() {
        let (engine, controller, provider) = running(FakeProvider(index: 1))
        engine.skip(by: 15)
        XCTAssertEqual(provider.index, 2)
        engine.skip(by: -15)
        engine.skip(by: -15)
        XCTAssertEqual(provider.index, 0)
        engine.skip(by: -15)
        XCTAssertEqual(provider.index, 0, "nothing before the first item")
        XCTAssertEqual(provider.navigations, ["next", "previous", "previous"])
        XCTAssertGreaterThan(controller.refreshes, 0)
    }

    func testNextStopsAtTheLastItem() {
        let (engine, _, provider) = running(FakeProvider(index: 3))
        engine.skip(by: 15)
        XCTAssertEqual(provider.index, 3)
        XCTAssertTrue(provider.navigations.isEmpty)
    }

    func testLongTextTurnsPagesBeforeItems() {
        let long = "واحد اثنان ثلاثة أربعة خمسة ستة سبعة"
        let (engine, controller, provider) = running(FakeProvider(texts: ["أ", long, "ج"], index: 1))
        XCTAssertEqual(controller.frame?.pageCount, 3)
        XCTAssertEqual(controller.frame?.page, 0)
        engine.skip(by: 15)
        XCTAssertEqual(provider.index, 1, "next page, same item")
        XCTAssertEqual(engine.currentPage?.page, 1)
        engine.skip(by: 15)
        XCTAssertEqual(engine.currentPage?.page, 2)
        XCTAssertEqual(controller.frame?.pageText, "سبعة")
        engine.skip(by: 15)
        XCTAssertEqual(provider.index, 2, "past the last page: the next item")
        XCTAssertEqual(engine.currentPage?.page, 0)
        XCTAssertEqual(engine.currentPage?.total, 1)
        engine.skip(by: -15)
        XCTAssertEqual(provider.index, 1)
        XCTAssertEqual(engine.currentPage?.page, 0, "an item opens on its first page")
        engine.skip(by: 15)
        engine.skip(by: -15)
        XCTAssertEqual(engine.currentPage?.page, 0)
        XCTAssertEqual(provider.index, 1)
        XCTAssertEqual(controller.frame?.pageText, "واحد اثنان ثلاثة ")
    }

    func testItemChangedOnScreenResetsThePage() async {
        let long = "واحد اثنان ثلاثة أربعة خمسة ستة سبعة"
        let (engine, controller, provider) = running(FakeProvider(texts: [long, "ب"], index: 0))
        engine.skip(by: 15)
        XCTAssertEqual(engine.currentPage?.page, 1)
        provider.index = 1
        provider.subject.send()
        await settle()
        XCTAssertEqual(engine.currentPage?.page, 0)
        XCTAssertEqual(controller.frame?.content.index, 1)
    }

    // MARK: Play / pause

    func testPlayDoesNothingForAOnePageText() {
        let (engine, _, provider) = running()
        engine.setPlaying(true)
        XCTAssertEqual(engine.state, .paused, "nothing to play")
        XCTAssertEqual(provider.index, 0)
    }

    func testPlayTurnsPagesButNeverTheItem() {
        let long = "واحد اثنان ثلاثة أربعة خمسة ستة سبعة"
        let (engine, controller, provider) = running(FakeProvider(texts: [long, "ب"], index: 0))
        engine.setPlaying(true)
        XCTAssertEqual(engine.state, .active)
        XCTAssertEqual(controller.frame?.isPlaying, true)
        clock.advance(4)
        XCTAssertEqual(controller.frame?.page, 0)
        clock.advance(4)
        XCTAssertEqual(controller.frame?.page, 1)
        clock.advance(8)
        XCTAssertEqual(controller.frame?.page, 2)
        XCTAssertEqual(engine.state, .paused, "stops on the last page")
        clock.advance(60)
        XCTAssertEqual(controller.frame?.page, 2)
        XCTAssertEqual(provider.index, 0, "never the next item")
        engine.setPlaying(true)
        XCTAssertEqual(engine.state, .paused, "nothing left to turn")
    }

    func testPauseStopsPageTurning() {
        let long = "واحد اثنان ثلاثة أربعة خمسة ستة سبعة"
        let (engine, controller, _) = running(FakeProvider(texts: [long], index: 0))
        engine.setPlaying(true)
        engine.setPlaying(false)
        XCTAssertEqual(engine.state, .paused)
        clock.advance(30)
        XCTAssertEqual(controller.frame?.page, 0)
    }

    func testRecordingPlaysAndPauses() {
        let provider = FakeProvider(.hisn)
        let playback = FakePlayback()
        provider.playback = playback
        let (engine, controller, _) = running(provider)
        XCTAssertEqual(engine.state, .paused)
        engine.setPlaying(true)
        XCTAssertEqual(playback.calls, ["play"])
        XCTAssertEqual(engine.state, .active)
        let frame = controller.frame
        XCTAssertEqual(frame?.mode, .audio)
        XCTAssertEqual(frame?.rate, 1)
        XCTAssertEqual(frame?.duration, 30)
        engine.setPlaying(false)
        XCTAssertEqual(playback.calls, ["play", "pause"])
        XCTAssertEqual(engine.state, .paused)
    }

    func testRecordingThatEndsStaysOnItsItem() async {
        let provider = FakeProvider(.hisn, index: 1)
        let playback = FakePlayback()
        provider.playback = playback
        let (engine, _, _) = running(provider)
        engine.setPlaying(true)
        // The recording finishes.
        playback.isPlaying = false
        playback.currentTime = 30
        provider.subject.send()
        await settle()
        XCTAssertEqual(engine.state, .paused)
        XCTAssertEqual(provider.index, 1, "audio completion is not Next")
        XCTAssertTrue(provider.navigations.isEmpty)
    }

    func testSkipWithARecordingStillNavigates() {
        let provider = FakeProvider(.hisn, index: 1)
        let playback = FakePlayback()
        provider.playback = playback
        let (engine, _, _) = running(provider)
        engine.skip(by: 15)
        XCTAssertEqual(provider.index, 2)
        XCTAssertFalse(playback.calls.contains("seek"), "skip is navigation, not a seek")
    }

    func testUnavailableRecordingIsTextMode() {
        let provider = FakeProvider(.hisn)
        let playback = FakePlayback()
        playback.isAvailable = false
        provider.playback = playback
        let (engine, controller, _) = running(provider)
        engine.setPlaying(true)
        XCTAssertTrue(playback.calls.isEmpty)
        XCTAssertEqual(controller.frame?.mode, .text)
    }

    // MARK: Frames

    func testTextFrameShowsThePlaceInTheContainer() {
        let (_, controller, _) = running(FakeProvider(index: 1))
        let frame = controller.frame
        XCTAssertEqual(frame?.mode, .text)
        XCTAssertEqual(frame?.time, 2)
        XCTAssertEqual(frame?.duration, 4)
        XCTAssertEqual(frame?.rate, 0)
        XCTAssertEqual(frame?.content.subtitle, "العنصر 2")
    }

    func testPreviewOfAnotherScreenIsItsFirstPageNotPlaying() {
        let long = "واحد اثنان ثلاثة أربعة خمسة ستة سبعة"
        let (engine, _, _) = running(FakeProvider(texts: [long], index: 0))
        engine.skip(by: 15)
        let other = FakeProvider(.quran, texts: [long])
        let otherController = FakePiPController()
        engine.register(otherController, provider: other)
        XCTAssertEqual(otherController.frame?.page, 0)
        XCTAssertEqual(otherController.frame?.isPlaying, false)
        XCTAssertEqual(otherController.frame?.content.contentType, .quran)
    }

    func testNoFrameWithoutContent() {
        let engine = makeEngine()
        let controller = FakePiPController()
        let provider = FakeProvider()
        provider.completed = true
        engine.register(controller, provider: provider)
        XCTAssertNil(controller.frame)
    }

    // MARK: Close, session

    func testClosingKeepsProgressAndSavesTheSession() {
        let (engine, controller, provider) = running(FakeProvider(index: 1))
        engine.skip(by: 15)
        XCTAssertEqual(store.session?.index, 2)
        XCTAssertEqual(store.session?.domain, .dhikr)
        XCTAssertEqual(store.session?.status, .paused)
        engine.stop()
        XCTAssertEqual(controller.calls, ["start", "stop"])
        controller.systemStops()
        XCTAssertEqual(engine.state, .inactive)
        XCTAssertEqual(provider.persists, 1)
        XCTAssertEqual(provider.index, 2, "the reader stays on the item")
        XCTAssertEqual(store.session?.status, .closed)
        XCTAssertEqual(store.session?.contentID, "dhikr:2")
        XCTAssertEqual(store.session?.page, 0)
        XCTAssertNil(engine.activeContentType)
        XCTAssertFalse(engine.isRunning(provider))
    }

    func testSessionRecordsThePage() {
        let long = "واحد اثنان ثلاثة أربعة خمسة ستة سبعة"
        let (engine, _, _) = running(FakeProvider(texts: [long], index: 0))
        engine.skip(by: 15)
        XCTAssertEqual(store.session?.page, 1)
        XCTAssertEqual(store.session?.containerID, "dhikr:list")
    }

    func testClosedByTheUserInTheWindow() {
        let (engine, controller, provider) = running()
        controller.systemStops()
        XCTAssertEqual(engine.state, .inactive)
        XCTAssertEqual(provider.persists, 1)
    }

    func testContentGoneClosesTheWindow() async {
        let (_, controller, provider) = running()
        provider.completed = true
        provider.subject.send()
        await settle()
        XCTAssertEqual(controller.calls, ["start", "stop"])
        controller.systemStops()
        XCTAssertEqual(store.session?.status, .closed)
    }

    func testStopIfShowingOnlyStopsItsOwnSession() {
        let (engine, controller, provider) = running()
        engine.stop(ifShowing: FakeProvider(.dua))
        XCTAssertEqual(controller.calls, ["start"])
        engine.stop(ifShowing: provider)
        XCTAssertEqual(controller.calls, ["start", "stop"])
    }

    func testTurningTheSettingOffClosesPiP() {
        let (engine, controller, _) = running()
        engine.setUserEnabled(false)
        XCTAssertEqual(controller.calls, ["start", "stop"])
        XCTAssertFalse(engine.availability.isEnabled)
    }

    // MARK: Switching sections

    func testStartingAnotherSectionReplacesTheSession() {
        let (engine, quranController, quran) = running(FakeProvider(.quran, index: 2))
        let hisn = FakeProvider(.hisn, index: 0)
        let hisnController = FakePiPController()
        engine.register(hisnController, provider: hisn)
        engine.start(hisn, on: hisnController)
        XCTAssertEqual(quranController.calls, ["start", "stop"], "the old window closes first")
        XCTAssertTrue(hisnController.calls.isEmpty, "one PiP at a time")
        XCTAssertEqual(engine.activeContentType, .quran)
        quranController.systemStops()
        XCTAssertEqual(quran.persists, 1)
        XCTAssertEqual(hisnController.calls, ["start"])
        XCTAssertEqual(engine.activeContentType, .hisn)
        XCTAssertEqual(engine.state, .starting)
        hisnController.systemStarts()
        XCTAssertEqual(engine.state, .paused)
        XCTAssertTrue(engine.isRunning(hisn))
        XCTAssertFalse(engine.isRunning(quran))

        // The old controller no longer controls anything.
        quranController.send(.didStop)
        quranController.send(.didStart)
        XCTAssertEqual(engine.state, .paused)
        XCTAssertTrue(engine.isRunning(hisn))
        engine.skip(by: 15)
        XCTAssertEqual(hisn.index, 1)
        XCTAssertEqual(quran.index, 2)
        XCTAssertEqual(store.session?.domain, .hisn)
        XCTAssertFalse(quranController.heartbeat)
    }

    func testStopCancelsAPendingSwitch() {
        let (engine, quranController, _) = running(FakeProvider(.quran))
        let hisn = FakeProvider(.hisn)
        let hisnController = FakePiPController()
        engine.register(hisnController, provider: hisn)
        engine.start(hisn, on: hisnController)
        engine.stop()
        quranController.systemStops()
        XCTAssertTrue(hisnController.calls.isEmpty)
        XCTAssertEqual(engine.state, .inactive)
    }

    // MARK: Heartbeat, return to app

    func testHeartbeatRunsWhileVisibleOrRunning() {
        let engine = makeEngine()
        let controller = FakePiPController()
        let provider = FakeProvider()
        engine.register(controller, provider: provider)
        engine.setInlineVisible(true, for: controller)
        XCTAssertTrue(controller.heartbeat)
        XCTAssertEqual(controller.refreshes, 1)
        engine.start(provider, on: controller)
        controller.systemStarts()
        engine.setInlineVisible(false, for: controller)
        XCTAssertTrue(controller.heartbeat, "PiP runs in the background")
        controller.systemStops()
        XCTAssertFalse(controller.heartbeat)
    }

    func testReturnToAppReportsTheSection() {
        let (engine, controller, _) = running(FakeProvider(.dua))
        var restored: PiPContentType?
        engine.onRestoreUserInterface = { restored = $0 }
        controller.send(.restoreUserInterface)
        XCTAssertEqual(restored, .dua)
    }

    func testSystemButtonsReachTheEngine() {
        let (engine, controller, provider) = running(FakeProvider(index: 0))
        XCTAssertTrue(controller.commands === engine)
        controller.commands?.skip(by: 10)
        XCTAssertEqual(provider.index, 1)
    }
}
