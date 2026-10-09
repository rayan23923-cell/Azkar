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
        engine.setPlaying(true)
        XCTAssertEqual(provider.current?.subtitle, "الآية 282", "play: the next page of the ayah")
        XCTAssertEqual(controller.frame?.page, 1)
        for _ in 0..<(frame.pageCount + 2) { engine.setPlaying(true) }
        XCTAssertEqual(controller.frame?.page, frame.pageCount - 1, "stops on the last page")
        XCTAssertEqual(provider.current?.subtitle, "الآية 282", "pages never change the ayah")
        engine.setPlaying(false)
        XCTAssertEqual(controller.frame?.page, frame.pageCount - 2, "pause: the previous page")
        engine.skip(by: 15)
        XCTAssertEqual(provider.current?.subtitle, "الآية 283", "skip: the next ayah")
        XCTAssertEqual(controller.frame?.page, 0)
        XCTAssertNil(controller.frame?.content.repetition, "an ayah is never counted")
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

    /// A real chapter with its first items' counts set for the test (the bundled book is not
    /// changed; it has no count above 100). Every other field is the stored one.
    private func chapter(counts: [Int?]) async throws -> HisnChapter {
        let library = try await Content.hisnLibrary()
        let source = try XCTUnwrap(library.book.chapters.first { $0.items.count >= max(counts.count, 3) })
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
        var items = try XCTUnwrap(json["items"] as? [[String: Any]])
        for (index, count) in counts.enumerated() {
            var repetition = try XCTUnwrap(items[index]["repetition"] as? [String: Any])
            repetition["count"] = count ?? NSNull()
            items[index]["repetition"] = repetition
        }
        json["items"] = items
        let chapter = try JSONDecoder().decode(HisnChapter.self, from: JSONSerialization.data(withJSONObject: json))
        for index in chapter.items.indices {
            XCTAssertEqual(chapter.items[index].arabicText, source.items[index].arabicText)
            XCTAssertEqual(chapter.items[index].id, source.items[index].id)
            XCTAssertEqual(chapter.items[index].reviewStatus, source.items[index].reviewStatus)
        }
        return chapter
    }

    /// PiP running on a Hisn reader, as the app runs it.
    private func running(_ controller: HisnReaderController)
        -> (PiPEngine, StubPiPController, HisnPiPProvider) {
        let provider = HisnPiPProvider(controller: controller)
        let engine = makeEngine()
        let pip = StubPiPController()
        engine.register(pip, provider: provider)
        engine.start(provider, on: pip)
        pip.systemStarts()
        return (engine, pip, provider)
    }

    func testOnlySkipForwardCounts() async throws {
        let (chapter, index) = try await countedChapter()
        let controller = try self.controller(chapter, at: index)
        let total = try XCTUnwrap(chapter.items[index].repetition.count)
        let (engine, pip, _) = running(controller)
        XCTAssertEqual(controller.recitations, 0, "opening PiP changes nothing")
        XCTAssertEqual(controller.reader.completedRepetitions, 0)
        engine.setPlaying(true)
        engine.setPlaying(false)
        XCTAssertEqual(controller.recitations, 0, "play / pause never counts")
        engine.skip(by: 15)
        XCTAssertEqual(controller.recitations, 1)
        XCTAssertEqual(controller.reader.completedRepetitions, 1)
        XCTAssertEqual(store.position?.completedRepetitions, 1, "saved by the reader at once")
        XCTAssertEqual(pip.frame?.content.detail, "التكرار 2 من \(total)", "drawn at once")
        XCTAssertEqual(pip.frame?.content.repetition, PiPRepetition(completed: 1, total: total))
        XCTAssertEqual(controller.reader.itemIndex, index)
        pip.systemStops()
        XCTAssertEqual(controller.recitations, 1, "closing does not count")
        XCTAssertEqual(store.position?.completedRepetitions, 1)
    }

    /// 1, 3, 100 and above 100: each skip forward is one recitation, the display follows the
    /// reader's count, and the full count moves the reader on (its own behaviour) while the
    /// window keeps the finished item until the next skip.
    func testCountsOfAnySize() async throws {
        for total in [1, 3, 100, 101, 250] {
            let chapter = try await self.chapter(counts: [total, 3])
            let controller = try self.controller(chapter, at: 0)
            let (engine, pip, _) = running(controller)
            for done in 0..<(total - 1) {
                XCTAssertEqual(pip.frame?.content.detail, "التكرار \(done + 1) من \(total)")
                engine.skip(by: 15)
                XCTAssertEqual(controller.reader.completedRepetitions, done + 1, "\(total)")
                XCTAssertEqual(pip.frame?.content.repetition?.completed, done + 1)
            }
            XCTAssertEqual(pip.frame?.content.detail, "التكرار \(total) من \(total)")
            XCTAssertEqual(controller.reader.itemIndex, 0, "nothing moves before the count")
            XCTAssertEqual(controller.recitations, total - 1)

            engine.skip(by: 15) // the last recitation
            XCTAssertEqual(controller.recitations, total)
            XCTAssertEqual(controller.reader.itemIndex, 1, "the reader moves on, as on the screen")
            XCTAssertEqual(store.position?.itemIndex, 1)
            XCTAssertEqual(pip.frame?.content.contentID, chapter.items[0].id, "the finished item stays in view")
            XCTAssertEqual(pip.frame?.content.detail, "اكتمل ✓ \(total) من \(total)")
            XCTAssertEqual(pip.frame?.content.text, chapter.items[0].arabicText)
            XCTAssertTrue(pip.frame?.footer.contains("⏩ التالي") == true)
            XCTAssertEqual(pip.calls, ["start"], "the window stays open")

            engine.skip(by: 15) // on to the next item, nothing counted
            XCTAssertEqual(controller.recitations, total)
            XCTAssertEqual(pip.frame?.content.contentID, chapter.items[1].id)
            XCTAssertEqual(pip.frame?.content.detail, "التكرار 1 من 3")
            XCTAssertEqual(controller.reader.completedRepetitions, 0)
            pip.systemStops()
        }
    }

    func testCountIsKeptAcrossPauseCloseAndReopen() async throws {
        let chapter = try await self.chapter(counts: [100, 3])
        let controller = try self.controller(chapter, at: 0)
        let (engine, pip, provider) = running(controller)
        for _ in 0..<37 { engine.skip(by: 15) }
        XCTAssertEqual(pip.frame?.content.detail, "التكرار 38 من 100")
        engine.setPlaying(false)
        engine.setPlaying(true)
        XCTAssertEqual(controller.reader.completedRepetitions, 37)
        pip.systemStops()
        XCTAssertEqual(store.position?.completedRepetitions, 37)

        // Reopened on the same screen.
        engine.start(provider, on: pip)
        pip.systemStarts()
        XCTAssertEqual(pip.frame?.content.detail, "التكرار 38 من 100")
        pip.systemStops()

        // The app relaunched: the reader comes back from its saved position.
        let saved = try XCTUnwrap(store.position)
        let book = try await Content.hisnLibrary().book
        let library = HisnLibrary(book: HisnBook(id: book.id, titleArabic: book.titleArabic, author: book.author,
                                                 provenance: book.provenance, attribution: book.attribution,
                                                 chapters: [chapter]))
        let reader = try XCTUnwrap(HisnResume.reader(for: saved, in: library))
        let relaunched = HisnReaderController(reader: reader, store: InMemoryHisnReadingPositionStore())
        let (again, pipAgain, _) = running(relaunched)
        XCTAssertEqual(pipAgain.frame?.content.detail, "التكرار 38 من 100")
        again.skip(by: 15)
        XCTAssertEqual(relaunched.reader.completedRepetitions, 38)
    }

    func testTheLastItemCompletesTheChapterAndStaysInView() async throws {
        let library = try await Content.hisnLibrary()
        let source = try XCTUnwrap(library.book.chapters.first { $0.items.count >= 3 })
        var counts: [Int?] = source.items.map(\.repetition.count)
        counts[counts.count - 1] = 3
        let chapter = try await self.chapter(counts: counts)
        let last = chapter.items.count - 1
        let controller = try self.controller(chapter, at: last)
        let (engine, pip, _) = running(controller)
        for _ in 0..<3 { engine.skip(by: 15) }
        XCTAssertTrue(controller.reader.isCompleted, "the full count completes the chapter, as on the screen")
        XCTAssertNil(store.position, "a completed chapter has no resume point")
        XCTAssertEqual(pip.frame?.content.contentID, chapter.items[last].id)
        XCTAssertEqual(pip.frame?.content.detail, "اكتمل ✓ 3 من 3  ·  اكتمل الباب")
        XCTAssertFalse(pip.frame?.footer.contains("⏩") == true, "nothing left to count or open")
        engine.skip(by: 15)
        XCTAssertEqual(pip.calls, ["start"], "the window stays until the user closes it")
        XCTAssertEqual(controller.recitations, 3)
        XCTAssertTrue(controller.reader.isCompleted, "never another chapter")
        engine.skip(by: -15)
        XCTAssertFalse(controller.reader.isCompleted, "back to the last item")
        XCTAssertEqual(controller.reader.itemIndex, last)
    }

    func testAChangeOnTheScreenReplacesTheFinishedItem() async throws {
        let chapter = try await self.chapter(counts: [1, 3, 3])
        let controller = try self.controller(chapter, at: 0)
        let (engine, pip, provider) = running(controller)
        engine.skip(by: 15)
        XCTAssertEqual(provider.current?.contentID, chapter.items[0].id)
        controller.recite() // the reader's own count button
        XCTAssertEqual(provider.current?.contentID, chapter.items[1].id)
        XCTAssertEqual(provider.current?.detail, "التكرار 2 من 3")
        XCTAssertEqual(pip.frame?.content.detail, "التكرار 2 من 3")
    }

    func testSkipBackFromTheFinishedItem() async throws {
        let chapter = try await self.chapter(counts: [nil, 1, 3])
        let controller = try self.controller(chapter, at: 1)
        let (engine, pip, _) = running(controller)
        engine.skip(by: 15)
        XCTAssertEqual(controller.reader.itemIndex, 2)
        XCTAssertEqual(pip.frame?.content.contentID, chapter.items[1].id)
        engine.skip(by: -15)
        XCTAssertEqual(controller.reader.itemIndex, 1, "back to the item shown")
        XCTAssertEqual(pip.frame?.content.contentID, chapter.items[1].id)
        XCTAssertEqual(pip.frame?.content.detail, "اكتمل ✓ 1 من 1", "the finished item keeps its count")
        engine.skip(by: -15)
        XCTAssertEqual(controller.reader.itemIndex, 0)
        XCTAssertNil(pip.frame?.content.repetition, "no stated count: nothing to count")
        engine.skip(by: 15)
        XCTAssertEqual(controller.reader.itemIndex, 1, "an item without a count moves on")
        XCTAssertEqual(controller.recitations, 1)
        engine.skip(by: 15)
        XCTAssertEqual(controller.reader.itemIndex, 2, "the finished item is not counted again")
        XCTAssertEqual(controller.recitations, 1)
    }

    /// The owner's report (2026-10-09): count an item to the end, go on, skip back: PiP and the
    /// reader showed zero. Now both show the finished count, skip forward moves on without
    /// counting, and a partial count on the next item is kept too.
    func testGoingBackToAFinishedItemKeepsItsCount() async throws {
        let chapter = try await self.chapter(counts: [3, 3])
        let controller = try self.controller(chapter, at: 0)
        let (engine, pip, _) = running(controller)
        engine.skip(by: 15); engine.skip(by: 15); engine.skip(by: 15)
        XCTAssertEqual(pip.frame?.content.detail, "اكتمل ✓ 3 من 3")
        engine.skip(by: 15)
        XCTAssertEqual(controller.reader.itemIndex, 1)
        engine.skip(by: 15)
        XCTAssertEqual(pip.frame?.content.detail, "التكرار 2 من 3")
        engine.skip(by: -15)
        XCTAssertEqual(controller.reader.itemIndex, 0)
        XCTAssertEqual(controller.reader.repetition, .counted(completed: 3, total: 3), "the reader screen")
        XCTAssertEqual(pip.frame?.content.detail, "اكتمل ✓ 3 من 3", "the window")
        XCTAssertEqual(pip.frame?.content.repetition, PiPRepetition(completed: 3, total: 3))
        let recitations = controller.recitations
        engine.skip(by: 15)
        XCTAssertEqual(controller.recitations, recitations, "not counted again")
        XCTAssertEqual(controller.reader.itemIndex, 1)
        XCTAssertEqual(pip.frame?.content.detail, "التكرار 2 من 3", "the partial count is kept")
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
        XCTAssertNil(pip.frame?.content.repetition, "PiP counts only Hisn items")
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
