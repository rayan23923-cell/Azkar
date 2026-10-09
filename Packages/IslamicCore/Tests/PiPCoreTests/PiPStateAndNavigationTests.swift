import XCTest
@testable import PiPCore

final class PiPStateTests: XCTestCase {
    func testFullLifecycle() {
        var state = PiPState.inactive
        state = state.applying(.startRequested)
        XCTAssertEqual(state, .starting)
        XCTAssertTrue(state.isRunning)
        XCTAssertFalse(state.isShowing)
        state = state.applying(.willStart)
        XCTAssertEqual(state, .starting)
        state = state.applying(.didStart(playing: false))
        XCTAssertEqual(state, .paused)
        XCTAssertTrue(state.isShowing)
        state = state.applying(.playingChanged(true))
        XCTAssertEqual(state, .active)
        state = state.applying(.playingChanged(false))
        XCTAssertEqual(state, .paused)
        state = state.applying(.willStop)
        XCTAssertEqual(state, .stopping)
        XCTAssertTrue(state.isRunning)
        state = state.applying(.didStop)
        XCTAssertEqual(state, .inactive)
        XCTAssertFalse(state.isRunning)
    }

    func testStartPlayingGoesStraightToActive() {
        XCTAssertEqual(PiPState.starting.applying(.didStart(playing: true)), .active)
    }

    func testFailureAndRetry() {
        let failed = PiPState.starting.applying(.failedToStart)
        XCTAssertEqual(failed, .error(.failedToStart))
        XCTAssertEqual(failed.error, .failedToStart)
        XCTAssertFalse(failed.isRunning)
        XCTAssertEqual(failed.applying(.startRequested), .starting)
    }

    func testPlayingChangesOnlyWhileShown() {
        XCTAssertEqual(PiPState.inactive.applying(.playingChanged(true)), .inactive)
        XCTAssertEqual(PiPState.starting.applying(.playingChanged(true)), .starting)
        XCTAssertEqual(PiPState.stopping.applying(.playingChanged(true)), .stopping)
    }

    func testRejectionNeverBreaksARunningSession() {
        XCTAssertEqual(PiPState.active.applying(.rejected(.noContent)), .active)
        XCTAssertEqual(PiPState.inactive.applying(.rejected(.disabled)), .error(.disabled))
        XCTAssertEqual(PiPState.error(.disabled).applying(.rejected(.notSupported)), .error(.notSupported))
    }

    func testStartWhileRunningIsIgnored() {
        XCTAssertEqual(PiPState.active.applying(.startRequested), .active)
        XCTAssertEqual(PiPState.paused.applying(.willStart), .paused)
        XCTAssertEqual(PiPState.inactive.applying(.willStop), .inactive)
    }
}

final class PiPPageModelTests: XCTestCase {
    func testSinglePageHasNoPageNavigation() {
        var model = PiPPageModel(contentID: "a", pagination: PiPPagination(fontSize: 84, pages: ["نص قصير"]))
        XCTAssertFalse(model.hasPages)
        XCTAssertEqual(model.totalPages, 1)
        XCTAssertTrue(model.isFirstPage)
        XCTAssertTrue(model.isLastPage)
        XCTAssertFalse(model.nextPage())
        XCTAssertFalse(model.previousPage())
        XCTAssertEqual(model.currentPage, 0)
        XCTAssertEqual(model.pageText, "نص قصير")
    }

    func testPagesStepWithinTheItem() {
        var model = PiPPageModel(contentID: "a", pagination: PiPPagination(fontSize: 54, pages: ["١ ", "٢ ", "٣"]))
        XCTAssertTrue(model.hasPages)
        XCTAssertTrue(model.nextPage())
        XCTAssertEqual(model.currentPage, 1)
        XCTAssertTrue(model.nextPage())
        XCTAssertTrue(model.isLastPage)
        XCTAssertFalse(model.nextPage())
        XCTAssertEqual(model.pageText, "٣")
        XCTAssertTrue(model.previousPage())
        XCTAssertEqual(model.currentPage, 1)
        XCTAssertEqual(model.contentID, "a")
    }

    func testStartPageIsClamped() {
        let pagination = PiPPagination(fontSize: 54, pages: ["a ", "b"])
        XCTAssertEqual(PiPPageModel(contentID: "x", pagination: pagination, currentPage: 9).currentPage, 1)
        XCTAssertEqual(PiPPageModel(contentID: "x", pagination: pagination, currentPage: -2).currentPage, 0)
    }

    func testEmptyPaginationHasOnePage() {
        XCTAssertEqual(PiPPagination(fontSize: 54, pages: []).pages, [""])
    }

    func testPaginatorKeepsTheTextExactly() {
        let text = "سُبْحَانَ اللَّهِ وَبِحَمْدِهِ سُبْحَانَ اللَّهِ الْعَظِيمِ  لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ"
        let pages = PiPTextPaginator.pages(text) { $0.split(whereSeparator: \.isWhitespace).count <= 3 }
        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertEqual(pages.joined(), text, "pages are exact slices")
        for page in pages {
            XCTAssertLessThanOrEqual(page.split(whereSeparator: \.isWhitespace).count, 3)
        }
        // Breaks only after whitespace: every page but the last ends with a space.
        for page in pages.dropLast() { XCTAssertTrue(page.last!.isWhitespace) }
    }

    func testAWordLongerThanAPageGetsItsOwnPage() {
        let pages = PiPTextPaginator.pages("قصير طويلجدا قصير") { $0.count <= 6 }
        XCTAssertEqual(pages.joined(), "قصير طويلجدا قصير")
        XCTAssertTrue(pages.contains("طويلجدا "))
    }

    func testEmptyTextHasNoPages() {
        XCTAssertEqual(PiPTextPaginator.pages("") { _ in true }, [])
    }
}

final class PiPNavigationTests: XCTestCase {
    private func content(_ index: Int, of total: Int, repetition: PiPRepetition? = nil) -> PiPContent {
        PiPContent(contentType: .dhikr, contentID: "\(index)", containerID: "c", title: "t", subtitle: "s",
                   text: "x", index: index, total: total, repetition: repetition)
    }

    private func pages(_ count: Int, at page: Int = 0) -> PiPPageModel {
        PiPPageModel(contentID: "x", pagination: PiPPagination(fontSize: 54, pages: Array(repeating: "p ", count: count)),
                     currentPage: page)
    }

    func testSkipMovesBetweenItems() {
        XCTAssertEqual(PiPNavigation.resolve(.next, content: content(1, of: 4)), .nextItem)
        XCTAssertEqual(PiPNavigation.resolve(.previous, content: content(1, of: 4)), .previousItem)
    }

    func testEndsDoNotMove() {
        XCTAssertEqual(PiPNavigation.resolve(.previous, content: content(0, of: 4)), .none)
        XCTAssertEqual(PiPNavigation.resolve(.next, content: content(3, of: 4)), .none)
        XCTAssertEqual(PiPNavigation.resolve(.next, content: content(0, of: 1)), .none)
    }

    func testPlayIsTheNextPageAndPauseThePrevious() {
        XCTAssertEqual(PiPNavigation.page(playing: true, pages: pages(3, at: 0)), .nextPage)
        XCTAssertEqual(PiPNavigation.page(playing: true, pages: pages(3, at: 1)), .nextPage)
        XCTAssertEqual(PiPNavigation.page(playing: true, pages: pages(3, at: 2)), .none, "no wrap")
        XCTAssertEqual(PiPNavigation.page(playing: false, pages: pages(3, at: 2)), .previousPage)
        XCTAssertEqual(PiPNavigation.page(playing: false, pages: pages(3, at: 1)), .previousPage)
        XCTAssertEqual(PiPNavigation.page(playing: false, pages: pages(3, at: 0)), .none, "no wrap")
        XCTAssertEqual(PiPNavigation.page(playing: true, pages: pages(1)), .none, "one page: nothing to turn")
        XCTAssertEqual(PiPNavigation.page(playing: false, pages: pages(1)), .none)
    }

    func testSkipForwardCountsBeforeMovingOn() {
        for total in [1, 3, 100, 101, 1000] {
            for completed in 0..<min(total, 3) {
                let item = content(1, of: 4, repetition: PiPRepetition(completed: completed, total: total))
                XCTAssertEqual(PiPNavigation.resolve(.next, content: item), .countRepetition, "\(completed)/\(total)")
                XCTAssertEqual(PiPNavigation.resolve(.previous, content: item), .previousItem, "back never counts")
            }
            let last = content(1, of: 4, repetition: PiPRepetition(completed: total - 1, total: total))
            XCTAssertEqual(PiPNavigation.resolve(.next, content: last), .countRepetition)
            let done = content(1, of: 4, repetition: PiPRepetition(completed: total, total: total))
            XCTAssertEqual(PiPNavigation.resolve(.next, content: done), .nextItem)
        }
        // The last item is counted too; the provider decides what follows.
        XCTAssertEqual(PiPNavigation.resolve(.next, content: content(3, of: 4, repetition: PiPRepetition(completed: 0, total: 3))),
                       .countRepetition)
    }

    func testRepetitionHasNoUpperLimit() {
        let large = PiPRepetition(completed: 136, total: 1000)
        XCTAssertEqual(large.current, 137)
        XCTAssertFalse(large.isComplete)
        XCTAssertEqual(PiPRepetition(completed: 101, total: 101).current, 101)
        XCTAssertTrue(PiPRepetition(completed: 101, total: 101).isComplete)
        XCTAssertEqual(PiPRepetition(completed: 500, total: 101).completed, 101, "never past the total")
        XCTAssertEqual(PiPRepetition(completed: -1, total: 3).completed, 0)
    }

    func testSkipSignGivesTheDirection() {
        XCTAssertEqual(PiPNavigation.Direction(skip: 15), .next)
        XCTAssertEqual(PiPNavigation.Direction(skip: -15), .previous)
        XCTAssertNil(PiPNavigation.Direction(skip: 0))
        XCTAssertNil(PiPNavigation.Direction(skip: .nan))
        XCTAssertNil(PiPNavigation.Direction(skip: .infinity))
    }
}

final class PiPSessionAndAvailabilityTests: XCTestCase {
    func testBackgroundModeIsReadFromInfoPlist() {
        XCTAssertTrue(PiPAvailability.backgroundModeDeclared(in: ["UIBackgroundModes": ["audio"]]))
        XCTAssertTrue(PiPAvailability.backgroundModeDeclared(in: ["UIBackgroundModes": ["fetch", "audio"]]))
        XCTAssertFalse(PiPAvailability.backgroundModeDeclared(in: ["UIBackgroundModes": ["fetch"]]))
        XCTAssertFalse(PiPAvailability.backgroundModeDeclared(in: [:]))
        XCTAssertFalse(PiPAvailability.backgroundModeDeclared(in: nil))
    }

    func testEnabledNeedsTheBuildAndTheSetting() {
        XCTAssertTrue(PiPAvailability(backgroundModeDeclared: true, userEnabled: true).isEnabled)
        XCTAssertFalse(PiPAvailability(backgroundModeDeclared: false, userEnabled: true).isEnabled)
        XCTAssertFalse(PiPAvailability(backgroundModeDeclared: true, userEnabled: false).isEnabled)
        XCTAssertFalse(PiPAvailability(backgroundModeDeclared: true, userEnabled: true).allowsAutomaticStart,
                       "manual PiP by default")
    }

    func testUserDefaultsStoreRoundTrip() throws {
        let suite = "pip.session.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsPiPSessionStore(defaults: defaults)
        XCTAssertNil(store.load())
        let session = PiPSession(domain: .hisn, contentID: "hisn-001-04", containerID: "hisn-ch-001", index: 3,
                                 page: 1, status: .paused, savedAt: Date(timeIntervalSince1970: 1000))
        store.save(session)
        XCTAssertEqual(UserDefaultsPiPSessionStore(defaults: defaults).load(), session)
        defaults.set(Data("nonsense".utf8), forKey: UserDefaultsPiPSessionStore.defaultKey)
        XCTAssertNil(store.load())
        XCTAssertNil(defaults.data(forKey: UserDefaultsPiPSessionStore.defaultKey), "unreadable data is removed")
        store.save(session)
        store.clear()
        XCTAssertNil(store.load())
    }

    func testFrameFooterAndProgress() {
        let content = PiPContent(contentType: .hisn, contentID: "i", containerID: "c", title: "أذكار الصباح",
                                 subtitle: "الذكر 4", text: "نص", index: 3, total: 10, detail: "التكرار 2 من 3")
        let text = PiPFrame(content: content, pageText: "نص", page: 1, pageCount: 3, fontSize: 54, mode: .text,
                            isPlaying: false, time: 3.5, duration: 10, rate: 0)
        XCTAssertEqual(text.footer, "التكرار 2 من 3  ·  4 من 10  ·  صفحة 2 من 3")
        XCTAssertEqual(text.progress, 0.35, accuracy: 0.0001)
        let audio = PiPFrame(content: content, pageText: "نص", page: 0, pageCount: 1, fontSize: 84, mode: .audio,
                             isPlaying: true, time: 40, duration: 20, rate: 1)
        XCTAssertEqual(audio.footer, "▶︎ يُشغَّل  ·  التكرار 2 من 3  ·  4 من 10")
        XCTAssertEqual(audio.progress, 1)
        let empty = PiPFrame(content: content, pageText: "", page: 0, pageCount: 0, fontSize: 84, mode: .audio,
                             isPlaying: false, time: 0, duration: 0, rate: 0)
        XCTAssertEqual(empty.pageCount, 1)
        XCTAssertEqual(empty.progress, 0)
    }
}
