import Combine
import XCTest
import AdhkarReading
import ContentKit
import HisnReading
import IslamicCore
import PiPCore
import PiPRendering
import QuranReading
@testable import PiPProviders

// MARK: - Support

@MainActor
final class StubPiPController: PiPController {
    var isSupported = true
    var isPossible = true
    var onEvent: ((PiPControllerEvent) -> Void)?
    var frameSource: (() -> PiPFrame?)?
    weak var commands: PiPCommandHandling?
    var calls: [String] = []

    func start() { calls.append("start") }
    func stop() { calls.append("stop") }
    func refresh() {}
    func setHeartbeat(_ running: Bool) {}
    func systemStarts() { onEvent?(.willStart); onEvent?(.didStart) }
    func systemStops() { onEvent?(.willStop); onEvent?(.didStop) }
    var frame: PiPFrame? { frameSource?() }
}

@MainActor
final class SilentAudioEngine: HisnAudioEngine {
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var onFinish: (() -> Void)?
    var onFailure: (() -> Void)?
    func load(url: URL) throws {}
    func play() -> Bool { false }
    func pause() {}
    func stop() {}
    func seek(to time: TimeInterval) {}
    func unload() {}
}

@MainActor
final class SilentAudioSession: HisnAudioSessionControlling {
    var onEvent: ((HisnAudioSessionEvent) -> Void)?
    func activateForPlayback() throws {}
}

enum Content {
    private static var quran: QuranLibrary?
    private static var hisn: HisnLibrary?
    private static var adhkar: AdhkarLibrary?

    static func quranLibrary() async throws -> QuranLibrary {
        if let quran { return quran }
        let loaded = try await QuranLibrary.load()
        quran = loaded
        return loaded
    }

    static func hisnLibrary() async throws -> HisnLibrary {
        if let hisn { return hisn }
        let loaded = HisnLibrary(book: try await BundledHisnRepository().loadBook())
        hisn = loaded
        return loaded
    }

    static func adhkarLibrary() async throws -> AdhkarLibrary {
        if let adhkar { return adhkar }
        let loaded = try await AdhkarLibrary.load()
        adhkar = loaded
        return loaded
    }
}

@MainActor
private func makeEngine() -> PiPEngine {
    PiPEngine(paginator: CoreTextPiPPaginator(), sessionStore: InMemoryPiPSessionStore(),
              availability: PiPAvailability(backgroundModeDeclared: true, userEnabled: true))
}

// MARK: - Quran

@MainActor
final class QuranPiPProviderTests: XCTestCase {
    private var store: InMemoryQuranPositionStore!

    private func provider(_ surah: Int, _ ayah: Int) async throws -> QuranPiPProvider {
        store = InMemoryQuranPositionStore()
        let library = try await Content.quranLibrary()
        let controller = try XCTUnwrap(QuranReaderController(library: library,
                                                             start: QuranVerseRef(surah: surah, ayah: ayah), store: store))
        return QuranPiPProvider(controller: controller)
    }

    func testMiddleAyahShowsSurahVerseAndText() async throws {
        let provider = try await self.provider(2, 10)
        let content = try XCTUnwrap(provider.current)
        let library = try await Content.quranLibrary()
        XCTAssertEqual(content.contentType, .quran)
        XCTAssertEqual(content.title, "سورة البقرة")
        XCTAssertEqual(content.subtitle, "الآية 10")
        XCTAssertEqual(content.text, library.verse(QuranVerseRef(surah: 2, ayah: 10))?.arabicText, "the stored verse")
        XCTAssertEqual(content.textStyle, .quran)
        XCTAssertEqual(content.index, 9)
        XCTAssertEqual(content.total, 286)
        XCTAssertNil(content.detail)
        XCTAssertNil(provider.playback, "no Quran recitation ships")
    }

    func testNextAndPreviousAyahMoveTheReaderAndSaveIt() async throws {
        let provider = try await self.provider(2, 10)
        provider.goToNext()
        XCTAssertEqual(provider.current?.subtitle, "الآية 11")
        XCTAssertEqual(provider.controller.currentAyah, 11)
        XCTAssertEqual(store.load()?.surah, 2)
        XCTAssertEqual(store.load()?.ayah, 11)
        provider.goToPrevious()
        provider.goToPrevious()
        XCTAssertEqual(provider.current?.subtitle, "الآية 9")
        XCTAssertEqual(store.load()?.ayah, 9)
    }

    func testFirstAndLastAyahStayInTheSurah() async throws {
        let first = try await provider(1, 1)
        XCTAssertTrue(try XCTUnwrap(first.current).isFirst)
        first.goToPrevious()
        XCTAssertEqual(first.current?.contentID, QuranVerseRef(surah: 1, ayah: 1).contentRef.string)
        let last = try await provider(2, 286)
        XCTAssertTrue(try XCTUnwrap(last.current).isLast)
        last.goToNext()
        XCTAssertEqual(last.controller.surah.id, 2, "never another surah")
        XCTAssertEqual(last.current?.subtitle, "الآية 286")
    }

    func testPlainScrollingDoesNotMovePiPButAJumpDoes() async throws {
        let provider = try await self.provider(2, 10)
        XCTAssertEqual(provider.current?.subtitle, "الآية 10")
        provider.controller.visible(ayah: 40)
        XCTAssertEqual(provider.current?.subtitle, "الآية 10")
        provider.controller.go(to: 100)
        XCTAssertEqual(provider.current?.subtitle, "الآية 100")
        provider.controller.open(surah: 3, ayah: 5)
        XCTAssertEqual(provider.current?.title, "سورة آل عمران")
        XCTAssertEqual(provider.current?.subtitle, "الآية 5")
    }

    func testLongAyahIsPagedInPiP() async throws {
        let provider = try await self.provider(2, 282)
        let engine = makeEngine()
        let controller = StubPiPController()
        engine.register(controller, provider: provider)
        engine.start(provider, on: controller)
        controller.systemStarts()
        let frame = try XCTUnwrap(controller.frame)
        XCTAssertGreaterThan(frame.pageCount, 1)
        engine.skip(by: 15)
        XCTAssertEqual(provider.current?.subtitle, "الآية 282", "next page first")
        XCTAssertEqual(controller.frame?.page, 1)
        for _ in 1..<frame.pageCount { engine.skip(by: 15) }
        XCTAssertEqual(provider.current?.subtitle, "الآية 283", "then the next ayah")
    }
}

// MARK: - Hisn

@MainActor
final class HisnPiPProviderTests: XCTestCase {
    private var store: InMemoryHisnReadingPositionStore!

    /// A chapter with an item said more than once, and that item's index.
    private func countedChapter() async throws -> (HisnChapter, Int) {
        let library = try await Content.hisnLibrary()
        for chapter in library.book.chapters {
            if let index = chapter.items.firstIndex(where: { ($0.repetition.count ?? 1) > 1 }) {
                return (chapter, index)
            }
        }
        throw XCTSkip("no counted item")
    }

    private func controller(_ chapter: HisnChapter, at index: Int, audio: HisnAudioPlayer? = nil) throws
        -> HisnReaderController {
        store = InMemoryHisnReadingPositionStore()
        let reader = try XCTUnwrap(HisnReader(chapter: chapter, itemIndex: index))
        return HisnReaderController(reader: reader, store: store, audio: audio)
    }

    func testShowsChapterTextAndRepetition() async throws {
        let (chapter, index) = try await countedChapter()
        let controller = try self.controller(chapter, at: index)
        let provider = HisnPiPProvider(controller: controller)
        let content = try XCTUnwrap(provider.current)
        let total = try XCTUnwrap(chapter.items[index].repetition.count)
        XCTAssertEqual(content.contentType, .hisn)
        XCTAssertEqual(content.title, chapter.titleArabic)
        XCTAssertEqual(content.subtitle, "الذكر \(index + 1)")
        XCTAssertEqual(content.text, chapter.items[index].arabicText, "the stored text")
        XCTAssertEqual(content.detail, "التكرار 1 من \(total)")
        controller.recite()
        XCTAssertEqual(provider.current?.detail, "التكرار 2 من \(total)", "the count comes from the reader's button")
    }

    func testPiPNeverCountsARepetition() async throws {
        let (chapter, index) = try await countedChapter()
        let controller = try self.controller(chapter, at: index)
        let provider = HisnPiPProvider(controller: controller)
        let engine = makeEngine()
        let pip = StubPiPController()
        engine.register(pip, provider: provider)
        engine.start(provider, on: pip)
        pip.systemStarts()
        XCTAssertEqual(controller.recitations, 0, "opening PiP changes nothing")
        XCTAssertEqual(controller.reader.completedRepetitions, 0)
        engine.setPlaying(true)
        engine.setPlaying(false)
        pip.systemStops()
        XCTAssertEqual(controller.recitations, 0)
        XCTAssertEqual(controller.reader.itemIndex, index)
    }

    func testFirstItemNextPreviousAndLastItem() async throws {
        let library = try await Content.hisnLibrary()
        let chapter = try XCTUnwrap(library.book.chapters.first { $0.items.count >= 3 })
        let controller = try self.controller(chapter, at: 0)
        let provider = HisnPiPProvider(controller: controller)
        XCTAssertTrue(try XCTUnwrap(provider.current).isFirst)
        provider.goToPrevious()
        XCTAssertEqual(controller.reader.itemIndex, 0)
        provider.goToNext()
        XCTAssertEqual(provider.current?.subtitle, "الذكر 2")
        XCTAssertEqual(store.position?.itemIndex, 1, "saved by the reader")
        provider.goToPrevious()
        XCTAssertEqual(controller.reader.itemIndex, 0)

        let last = try self.controller(chapter, at: chapter.items.count - 1)
        let lastProvider = HisnPiPProvider(controller: last)
        XCTAssertTrue(try XCTUnwrap(lastProvider.current).isLast)
        lastProvider.goToNext()
        XCTAssertFalse(last.reader.isCompleted, "PiP never completes the chapter")
        XCTAssertEqual(last.reader.itemIndex, chapter.items.count - 1)
    }

    func testCompletedChapterHasNothingToShow() async throws {
        let library = try await Content.hisnLibrary()
        let chapter = try XCTUnwrap(library.book.chapters.first { $0.items.count == 1 })
        let controller = try self.controller(chapter, at: 0)
        let provider = HisnPiPProvider(controller: controller)
        XCTAssertNotNil(provider.current)
        controller.next()
        XCTAssertTrue(controller.reader.isCompleted)
        XCTAssertNil(provider.current)
    }

    func testLongItemIsPaged() async throws {
        let library = try await Content.hisnLibrary()
        var longest: (HisnChapter, Int)?
        var length = 0
        for chapter in library.book.chapters {
            for (index, item) in chapter.items.enumerated() where item.arabicText.count > length {
                length = item.arabicText.count
                longest = (chapter, index)
            }
        }
        let (chapter, index) = try XCTUnwrap(longest)
        let provider = HisnPiPProvider(controller: try controller(chapter, at: index))
        let engine = makeEngine()
        let pip = StubPiPController()
        engine.register(pip, provider: provider)
        let frame = try XCTUnwrap(pip.frame)
        XCTAssertGreaterThan(frame.pageCount, 1)
        XCTAssertEqual(frame.page, 0)
    }

    func testWithoutProductionAudioPiPIsText() async throws {
        let library = try await Content.hisnLibrary()
        let chapter = library.book.chapters[0]
        let itemIds = Set(library.book.allItems.map(\.id))
        let player = HisnAudioPlayer(repository: BundledHisnAudioRepository(knownItemIds: itemIds),
                                     engine: SilentAudioEngine(), session: SilentAudioSession())
        let controller = try self.controller(chapter, at: 0, audio: player)
        await controller.audioSettled()
        let provider = HisnPiPProvider(controller: controller)
        XCTAssertEqual(provider.playback?.isAvailable, false, "the production pack has no recordings")
        let engine = makeEngine()
        let pip = StubPiPController()
        engine.register(pip, provider: provider)
        XCTAssertEqual(pip.frame?.mode, .text)
    }
}

// MARK: - Adhkar and duas

@MainActor
final class DevotionalPiPProviderTests: XCTestCase {
    private var store: InMemoryDevotionalPositionStore!

    private func controller(_ ref: ContentRef, start: Int = 0) async throws -> DevotionalReaderController {
        store = InMemoryDevotionalPositionStore()
        let library = try await Content.adhkarLibrary()
        let collection = try XCTUnwrap(library.collection(ref))
        let controller = try XCTUnwrap(DevotionalReaderController(collection: collection, store: store))
        controller.jump(to: start)
        return controller
    }

    func testAdhkarFirstMiddleLast() async throws {
        let controller = try await self.controller(.dhikrGroup("morning"))
        let provider = try XCTUnwrap(AdhkarPiPProvider(controller: controller))
        var content = try XCTUnwrap(provider.current)
        XCTAssertEqual(content.contentType, .dhikr)
        XCTAssertEqual(content.title, controller.collection.title)
        XCTAssertEqual(content.subtitle, "الذكر 1")
        XCTAssertEqual(content.total, 11)
        XCTAssertTrue(content.isFirst)
        XCTAssertEqual(content.text, controller.collection.items[0].text)
        provider.goToPrevious()
        XCTAssertEqual(controller.index, 0)
        provider.goToNext()
        content = try XCTUnwrap(provider.current)
        XCTAssertEqual(content.subtitle, "الذكر 2")
        XCTAssertEqual(store.position(in: controller.collection.ref)?.item, controller.collection.items[1].ref)
        controller.jump(to: 10)
        content = try XCTUnwrap(provider.current)
        XCTAssertTrue(content.isLast)
        provider.goToNext()
        XCTAssertEqual(controller.index, 10)
        XCTAssertFalse(controller.isComplete, "PiP never completes the collection")
    }

    func testCounterFollowsTheReaderOnly() async throws {
        let controller = try await self.controller(.dhikrGroup("morning"), start: 1)
        let provider = try XCTUnwrap(AdhkarPiPProvider(controller: controller))
        XCTAssertEqual(controller.remaining, 3)
        XCTAssertEqual(provider.current?.detail, "التكرار 1 من 3")
        controller.recite()
        XCTAssertEqual(provider.current?.detail, "التكرار 2 من 3")
        let engine = makeEngine()
        let pip = StubPiPController()
        engine.register(pip, provider: provider)
        engine.start(provider, on: pip)
        pip.systemStarts()
        engine.setPlaying(true)
        pip.systemStops()
        XCTAssertEqual(controller.cursor.completedRepetitions, 1, "PiP adds no repetition")
        XCTAssertEqual(store.position(in: controller.collection.ref)?.repetitions, 1, "and keeps the saved one")
    }

    func testQuranicDhikrUsesTheQuranFontStyle() async throws {
        let controller = try await self.controller(.dhikrGroup("morning"))
        let provider = try XCTUnwrap(AdhkarPiPProvider(controller: controller))
        for index in 0..<controller.count {
            controller.jump(to: index)
            let item = controller.current
            XCTAssertEqual(provider.current?.textStyle, item.reviewStatus == .quranVerbatimTanzil ? .quran : .standard)
        }
    }

    func testDuaFirstMiddleLast() async throws {
        let controller = try await self.controller(.duaCategory("prophetic"))
        let provider = try XCTUnwrap(DuaPiPProvider(controller: controller))
        var content = try XCTUnwrap(provider.current)
        XCTAssertEqual(content.contentType, .dua)
        XCTAssertEqual(content.subtitle, "الدعاء 1")
        XCTAssertNil(content.detail, "duas are said once")
        XCTAssertNil(provider.playback)
        provider.goToNext()
        provider.goToNext()
        content = try XCTUnwrap(provider.current)
        XCTAssertEqual(content.subtitle, "الدعاء 3")
        XCTAssertFalse(content.isFirst)
        XCTAssertFalse(content.isLast)
        controller.jump(to: controller.count - 1)
        XCTAssertTrue(try XCTUnwrap(provider.current).isLast)
        provider.goToNext()
        XCTAssertEqual(controller.index, controller.count - 1)
    }

    func testProviderMatchesTheCollectionKind() async throws {
        let dua = try await controller(.duaCategory("quranic"))
        XCTAssertNil(AdhkarPiPProvider(controller: dua))
        XCTAssertEqual(DevotionalPiPProvider.make(controller: dua).contentType, .dua)
        let adhkar = try await controller(.dhikrGroup("evening"))
        XCTAssertNil(DuaPiPProvider(controller: adhkar))
        XCTAssertEqual(DevotionalPiPProvider.make(controller: adhkar).contentType, .dhikr)
    }
}

// MARK: - Switching sections with real content

@MainActor
final class PiPDomainSwitchTests: XCTestCase {
    func testQuranThenHisnReplacesTheSession() async throws {
        let quranStore = InMemoryQuranPositionStore()
        let quranLibrary = try await Content.quranLibrary()
        let quranController = try XCTUnwrap(QuranReaderController(library: quranLibrary,
                                                                  start: QuranVerseRef(surah: 18, ayah: 10),
                                                                  store: quranStore))
        let quran = QuranPiPProvider(controller: quranController)
        let library = try await Content.hisnLibrary()
        let hisnReader = try XCTUnwrap(HisnReader(chapter: library.book.chapters[0], itemIndex: 0))
        let hisn = HisnPiPProvider(controller: HisnReaderController(reader: hisnReader,
                                                                    store: InMemoryHisnReadingPositionStore()))
        let sessions = InMemoryPiPSessionStore()
        let engine = PiPEngine(paginator: CoreTextPiPPaginator(), sessionStore: sessions,
                               availability: PiPAvailability(backgroundModeDeclared: true, userEnabled: true))
        let quranPiP = StubPiPController()
        let hisnPiP = StubPiPController()
        engine.register(quranPiP, provider: quran)
        engine.register(hisnPiP, provider: hisn)

        engine.start(quran, on: quranPiP)
        quranPiP.systemStarts()
        engine.skip(by: 15)
        XCTAssertEqual(quranController.currentAyah, 11)
        XCTAssertEqual(sessions.session?.domain, .quran)

        // The user opens the app, goes to Hisn and starts its PiP.
        engine.start(hisn, on: hisnPiP)
        XCTAssertEqual(quranPiP.calls, ["start", "stop"])
        quranPiP.systemStops()
        XCTAssertEqual(quranStore.load()?.ayah, 11, "the Quran position is kept")
        XCTAssertEqual(hisnPiP.calls, ["start"])
        hisnPiP.systemStarts()
        XCTAssertEqual(engine.activeContentType, .hisn)
        XCTAssertEqual(sessions.session?.domain, .hisn)
        engine.skip(by: 15)
        XCTAssertEqual(quranController.currentAyah, 11, "the old section no longer moves")
        XCTAssertEqual(hisnPiP.frame?.content.contentType, .hisn)
    }
}
