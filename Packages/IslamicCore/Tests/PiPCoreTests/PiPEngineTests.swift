import XCTest
@testable import PiPCore

@MainActor
final class PiPEngineTests: XCTestCase {
    private var clock: TestClock!
    private var store: InMemoryPiPSessionStore!
    /// The test owns the engine, as the app does: providers and controllers only hold it weakly.
    private var engine: PiPEngine?

    private func makeEngine(enabled: Bool = true, declared: Bool = true, wordsPerPage: Int = 3) -> PiPEngine {
        clock = TestClock()
        store = InMemoryPiPSessionStore()
        let clock = clock!
        return PiPEngine(paginator: FakePaginator(wordsPerPage: wordsPerPage), sessionStore: store,
                         availability: PiPAvailability(backgroundModeDeclared: declared, userEnabled: enabled),
                         now: { clock.date })
    }

    /// Engine, a registered controller and provider, PiP started and shown by the system.
    private func running(_ given: FakeProvider? = nil) -> (PiPEngine, FakePiPController, FakeProvider) {
        let provider = given ?? FakeProvider()
        let engine = makeEngine()
        self.engine = engine
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

    func testSkipChangesTheItemEvenOnALongText() {
        let long = "واحد اثنان ثلاثة أربعة خمسة ستة سبعة"
        let (engine, controller, provider) = running(FakeProvider(texts: ["أ", long, "ج"], index: 1))
        XCTAssertEqual(controller.frame?.pageCount, 3)
        engine.setPlaying(true)
        XCTAssertEqual(engine.currentPage?.page, 1)
        engine.skip(by: 15)
        XCTAssertEqual(provider.index, 2, "skip is the item, never the page")
        XCTAssertEqual(engine.currentPage?.page, 0)
        engine.skip(by: -15)
        XCTAssertEqual(provider.index, 1)
        XCTAssertEqual(engine.currentPage?.page, 0, "an item opens on its first page")
        XCTAssertEqual(controller.frame?.pageText, "واحد اثنان ثلاثة ")
        XCTAssertEqual(provider.navigations, ["next", "previous"])
    }

    func testItemChangedOnScreenResetsThePage() async {
        let long = "واحد اثنان ثلاثة أربعة خمسة ستة سبعة"
        let (engine, controller, provider) = running(FakeProvider(texts: [long, "ب"], index: 0))
        engine.setPlaying(true)
        XCTAssertEqual(engine.currentPage?.page, 1)
        provider.index = 1
        provider.subject.send()
        await settle()
        XCTAssertEqual(engine.currentPage?.page, 0)
        XCTAssertEqual(controller.frame?.content.index, 1)
    }

    // MARK: Play / pause

    func testPlayAndPauseDoNothingForAOnePageText() {
        let (engine, controller, provider) = running()
        let refreshes = controller.refreshes
        engine.setPlaying(true)
        XCTAssertEqual(engine.state, .paused, "nothing to play")
        XCTAssertEqual(engine.currentPage?.page, 0)
        XCTAssertEqual(controller.frame?.isPlaying, false, "the button stays play: no page was turned")
        XCTAssertEqual(controller.frame?.footer.contains("الصفحة"), false, "no page hint on a one-page text")
        engine.setPlaying(false)
        XCTAssertEqual(engine.currentPage?.page, 0)
        XCTAssertEqual(provider.index, 0)
        XCTAssertTrue(provider.navigations.isEmpty)
        XCTAssertEqual(controller.refreshes, refreshes + 2, "the system button is corrected at once")
    }

    func testPlayShowsTheNextPageAtOnce() {
        let long = "واحد اثنان ثلاثة أربعة خمسة ستة سبعة"
        let (engine, controller, provider) = running(FakeProvider(texts: [long, "ب"], index: 0))
        XCTAssertEqual(controller.frame?.page, 0)
        XCTAssertEqual(controller.frame?.isPlaying, false)
        XCTAssertTrue(controller.frame?.footer.contains("▶︎ الصفحة التالية") == true)
        let refreshes = controller.refreshes
        engine.setPlaying(true)
        XCTAssertEqual(controller.refreshes, refreshes + 1, "drawn at once")
        XCTAssertEqual(controller.frame?.page, 1, "no timer: the page turns on the tap")
        XCTAssertEqual(controller.frame?.pageText, "أربعة خمسة ستة ")
        XCTAssertEqual(store.session?.page, 1)
        XCTAssertEqual(engine.state, .paused, "text never plays")
        XCTAssertEqual(provider.index, 0, "never the next item")
        XCTAssertTrue(provider.navigations.isEmpty)
    }

    func testPauseShowsThePreviousPage() {
        let long = "واحد اثنان ثلاثة أربعة خمسة ستة سبعة"
        let (engine, controller, _) = running(FakeProvider(texts: [long], index: 0))
        engine.setPlaying(true)
        engine.setPlaying(true)
        XCTAssertEqual(controller.frame?.page, 2)
        engine.setPlaying(false)
        XCTAssertEqual(controller.frame?.page, 1)
        engine.setPlaying(false)
        XCTAssertEqual(controller.frame?.page, 0)
    }

    func testPagesStopAtTheFirstAndLastPage() {
        let long = "واحد اثنان ثلاثة أربعة خمسة ستة سبعة"
        let (engine, controller, provider) = running(FakeProvider(texts: [long, "ب"], index: 0))
        engine.setPlaying(false)
        XCTAssertEqual(controller.frame?.page, 0, "nothing before the first page")
        for _ in 0..<5 { engine.setPlaying(true) }
        XCTAssertEqual(controller.frame?.page, 2, "nothing after the last page")
        XCTAssertEqual(controller.frame?.pageText, "سبعة")
        XCTAssertEqual(provider.index, 0, "no wrap into the next item")
        XCTAssertTrue(provider.navigations.isEmpty)
        clock.advance(600)
        XCTAssertEqual(controller.frame?.page, 2, "nothing turns by itself")
    }

    /// The system button always means its next tap: play (forward) until the last page, then
    /// pause (back) until the first, so every tap turns a page.
    func testTheButtonShowsWhichWayItsNextTapGoes() {
        let long = "واحد اثنان ثلاثة أربعة خمسة ستة سبعة"
        let (engine, controller, _) = running(FakeProvider(texts: [long], index: 0))
        XCTAssertEqual(controller.frame?.isPlaying, false)
        engine.setPlaying(true)
        XCTAssertEqual(controller.frame?.isPlaying, false, "still play: more pages ahead")
        engine.setPlaying(true)
        XCTAssertEqual(controller.frame?.page, 2)
        XCTAssertEqual(controller.frame?.isPlaying, true, "last page: the button shows pause, back")
        XCTAssertTrue(controller.frame?.footer.contains("⏸ الصفحة السابقة") == true)
        engine.setPlaying(false)
        XCTAssertEqual(controller.frame?.page, 1)
        XCTAssertEqual(controller.frame?.isPlaying, true, "still back")
        engine.setPlaying(false)
        XCTAssertEqual(controller.frame?.page, 0)
        XCTAssertEqual(controller.frame?.isPlaying, false, "first page: play again")
        XCTAssertEqual(engine.state, .paused)
    }

    func testANewItemOpensOnItsFirstPageWithPlay() {
        let long = "واحد اثنان ثلاثة أربعة خمسة ستة سبعة"
        let (engine, controller, provider) = running(FakeProvider(texts: [long, long], index: 0))
        engine.setPlaying(true)
        engine.setPlaying(true)
        XCTAssertEqual(controller.frame?.isPlaying, true)
        engine.skip(by: 15)
        XCTAssertEqual(provider.index, 1)
        XCTAssertEqual(controller.frame?.page, 0)
        XCTAssertEqual(controller.frame?.isPlaying, false)
        engine.setPlaying(true)
        XCTAssertEqual(controller.frame?.page, 1, "pages of the new item")
    }

    func testPagesSurviveAnUnrelatedRefresh() async {
        let long = "واحد اثنان ثلاثة أربعة خمسة ستة سبعة"
        let (engine, controller, provider) = running(FakeProvider(texts: [long], index: 0))
        engine.setPlaying(true)
        provider.subject.send() // the same item changed (e.g. its counter)
        await settle()
        XCTAssertEqual(controller.frame?.page, 1)
        XCTAssertEqual(engine.currentPage?.page, 1)
    }

    func testReopeningStartsOnTheFirstPage() {
        let long = "واحد اثنان ثلاثة أربعة خمسة ستة سبعة"
        let (engine, controller, provider) = running(FakeProvider(texts: [long], index: 0))
        engine.setPlaying(true)
        engine.setPlaying(true)
        engine.stop()
        controller.systemStops()
        XCTAssertEqual(store.session?.page, 2)
        engine.start(provider, on: controller)
        controller.systemStarts()
        XCTAssertEqual(controller.frame?.page, 0)
        XCTAssertEqual(controller.frame?.isPlaying, false)
        engine.setPlaying(true)
        XCTAssertEqual(controller.frame?.page, 1)
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

    // MARK: Counting

    func testSkipForwardCountsUntilTheCountIsDone() {
        let provider = FakeProvider(.hisn, texts: ["أ", "ب"], index: 0)
        provider.counts = [3, nil]
        let (engine, controller, _) = running(provider)
        XCTAssertEqual(controller.frame?.content.repetition, PiPRepetition(completed: 0, total: 3))
        XCTAssertTrue(controller.frame?.footer.contains("⏩ عُدّ") == true)
        engine.skip(by: 15)
        XCTAssertEqual(provider.recitations, 1)
        XCTAssertEqual(controller.frame?.content.repetition?.completed, 1, "drawn at once")
        engine.skip(by: 15)
        engine.skip(by: 15)
        XCTAssertEqual(provider.recitations, 3)
        XCTAssertEqual(provider.index, 0, "the engine never moves on by itself")
        XCTAssertTrue(provider.navigations.isEmpty)
        XCTAssertTrue(controller.frame?.footer.contains("⏩ التالي") == true)
        engine.skip(by: 15)
        XCTAssertEqual(provider.recitations, 3, "a complete count is not counted again")
        XCTAssertEqual(provider.navigations, ["next"])
        XCTAssertEqual(provider.index, 1)
    }

    func testPlayAndPauseNeverCount() {
        let provider = FakeProvider(.hisn, texts: ["واحد اثنان ثلاثة أربعة خمسة ستة سبعة"], index: 0)
        provider.counts = [3]
        let (engine, controller, _) = running(provider)
        engine.setPlaying(true)
        engine.setPlaying(false)
        XCTAssertEqual(provider.recitations, 0)
        XCTAssertEqual(controller.frame?.content.repetition?.completed, 0)
    }

    func testSkipBackNeverCounts() {
        let provider = FakeProvider(.hisn, texts: ["أ", "ب"], index: 1)
        provider.counts = [nil, 3]
        let (engine, _, _) = running(provider)
        engine.skip(by: -15)
        XCTAssertEqual(provider.recitations, 0)
        XCTAssertEqual(provider.index, 0)
    }

    func testCountingKeepsThePage() {
        let long = "واحد اثنان ثلاثة أربعة خمسة ستة سبعة"
        let provider = FakeProvider(.hisn, texts: [long], index: 0)
        provider.counts = [100]
        let (engine, controller, _) = running(provider)
        engine.setPlaying(true)
        engine.skip(by: 15)
        XCTAssertEqual(controller.frame?.page, 1, "the same item: its page stays")
        XCTAssertEqual(provider.recitations, 1)
    }

    /// What each system button does, per section: play / pause = page, skip = item, and on a
    /// Hisn item with a count skip forward = one recitation.
    func testControlToActionMapForEverySection() {
        let long = "واحد اثنان ثلاثة أربعة خمسة ستة سبعة"
        for type in PiPContentType.allCases {
            let provider = FakeProvider(type, texts: [long, long, long], index: 1)
            if type == .hisn { provider.counts = [nil, 2, nil] }
            let (engine, controller, _) = running(provider)
            engine.setPlaying(true)
            XCTAssertEqual(controller.frame?.page, 1, "\(type): play is the next page")
            engine.setPlaying(false)
            XCTAssertEqual(controller.frame?.page, 0, "\(type): pause is the previous page")
            XCTAssertEqual(provider.index, 1, "\(type): pages never change the item")
            engine.skip(by: 15)
            if type == .hisn {
                XCTAssertEqual(provider.recitations, 1, "Hisn: skip forward counts")
                XCTAssertEqual(provider.index, 1)
                engine.skip(by: 15)
                engine.skip(by: 15)
                XCTAssertEqual(provider.recitations, 2, "only up to the count")
            } else {
                XCTAssertEqual(provider.recitations, 0, "\(type): never counts")
            }
            XCTAssertEqual(provider.index, 2, "\(type): skip forward is the next item")
            engine.skip(by: -15)
            XCTAssertEqual(provider.index, 1, "\(type): skip back is the previous item")
            engine.stop()
            controller.systemStops()
        }
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
        engine.setPlaying(true)
        engine.setPlaying(true)
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
        engine.setPlaying(true)
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
