import XCTest
import IslamicCore
import ContentKit
@testable import QuranReading

enum QuranFixture {
    private static var cached: QuranLibrary?
    private static var cachedIndex: QuranSearchIndex?

    static func library() async throws -> QuranLibrary {
        if let cached { return cached }
        let library = try await QuranLibrary.load()
        cached = library
        return library
    }

    static func engine() async throws -> QuranSearchEngine {
        if let cachedIndex { return QuranSearchEngine(index: cachedIndex) }
        let index = QuranSearchIndex(library: try await library())
        cachedIndex = index
        return QuranSearchEngine(index: index)
    }

    /// Tanzil metadata (`Upstream/tanzil/quran-data.xml`), read straight from the repository.
    static func metadataXML() throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Upstream/tanzil/quran-data.xml")
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func starts(_ element: String, in xml: String) throws -> [QuranVerseRef] {
        let pattern = try NSRegularExpression(pattern: "<\(element) index=\"\\d+\" sura=\"(\\d+)\" aya=\"(\\d+)\"")
        let range = NSRange(xml.startIndex..., in: xml)
        return pattern.matches(in: xml, range: range).map { match in
            let surah = Int(xml[Range(match.range(at: 1), in: xml)!])!
            let ayah = Int(xml[Range(match.range(at: 2), in: xml)!])!
            return QuranVerseRef(surah: surah, ayah: ayah)
        }
    }
}

final class QuranLibraryTests: XCTestCase {
    func testWholeQuranLoads() async throws {
        let library = try await QuranFixture.library()
        XCTAssertEqual(library.surahs.count, 114)
        XCTAssertEqual(library.totalVerses, 6236)
        XCTAssertEqual(library.surah(2)?.nameArabic, "البقرة")
        XCTAssertEqual(library.verses(of: 2).count, 286)
        XCTAssertNil(library.surah(0))
        XCTAssertNil(library.surah(115))
        XCTAssertNil(library.verse(QuranVerseRef(surah: 1, ayah: 8)))
        XCTAssertTrue(library.verses(of: 115).isEmpty)
    }

    func testJuzAndPageTablesMatchTanzilMetadata() throws {
        let xml = try QuranFixture.metadataXML()
        XCTAssertEqual(QuranMetadata.juzStarts, try QuranFixture.starts("juz", in: xml))
        XCTAssertEqual(QuranMetadata.pageStarts, try QuranFixture.starts("page", in: xml))
        XCTAssertEqual(QuranMetadata.juzStarts.count, 30)
        XCTAssertEqual(QuranMetadata.pageStarts.count, 604)
        XCTAssertEqual(QuranMetadata.juzStarts, QuranMetadata.juzStarts.sorted())
        XCTAssertEqual(QuranMetadata.pageStarts, QuranMetadata.pageStarts.sorted())
    }

    func testJuzAndPageLookup() async throws {
        let library = try await QuranFixture.library()
        XCTAssertEqual(library.juz(of: QuranVerseRef(surah: 1, ayah: 1)), 1)
        XCTAssertEqual(library.juz(of: QuranVerseRef(surah: 2, ayah: 141)), 1)
        XCTAssertEqual(library.juz(of: QuranVerseRef(surah: 2, ayah: 142)), 2)
        XCTAssertEqual(library.juz(of: QuranVerseRef(surah: 2, ayah: 255)), 3)
        XCTAssertEqual(library.juz(of: QuranVerseRef(surah: 114, ayah: 6)), 30)
        XCTAssertEqual(library.page(of: QuranVerseRef(surah: 1, ayah: 1)), 1)
        XCTAssertEqual(library.page(of: QuranVerseRef(surah: 2, ayah: 1)), 2)
        XCTAssertEqual(library.page(of: QuranVerseRef(surah: 114, ayah: 6)), 604)
        XCTAssertEqual(library.juzStart(30), QuranVerseRef(surah: 78, ayah: 1))
        XCTAssertNil(library.juzStart(31))
        // Every juz and page start is a real verse.
        for start in QuranMetadata.juzStarts + QuranMetadata.pageStarts {
            XCTAssertTrue(library.contains(start), "\(start)")
        }
    }

    func testVerseNeighboursCrossSurahs() async throws {
        let library = try await QuranFixture.library()
        XCTAssertEqual(library.verse(after: QuranVerseRef(surah: 1, ayah: 7)), QuranVerseRef(surah: 2, ayah: 1))
        XCTAssertEqual(library.verse(before: QuranVerseRef(surah: 2, ayah: 1)), QuranVerseRef(surah: 1, ayah: 7))
        XCTAssertNil(library.verse(after: QuranVerseRef(surah: 114, ayah: 6)))
        XCTAssertNil(library.verse(before: QuranVerseRef(surah: 1, ayah: 1)))
        var count = 1
        var ref = QuranVerseRef(surah: 1, ayah: 1)
        while let next = library.verse(after: ref) { ref = next; count += 1 }
        XCTAssertEqual(count, 6236)
    }

    func testIncompleteContentIsRefused() async throws {
        let library = try await QuranFixture.library()
        XCTAssertNil(QuranLibrary(surahs: Array(library.surahs.dropLast()), verses: []))
        var verses = (1...114).map { library.verses(of: $0) }
        verses[0] = Array(verses[0].dropLast())
        XCTAssertNil(QuranLibrary(surahs: library.surahs, verses: verses))
    }

    func testVerseRefs() {
        let ref = QuranVerseRef(surah: 2, ayah: 255)
        XCTAssertEqual(ref.contentRef.string, "quran:2:255")
        XCTAssertEqual(QuranVerseRef(ContentRef(.quran, "2:255")), ref)
        XCTAssertNil(QuranVerseRef(ContentRef(.quran, "2")))
        XCTAssertNil(QuranVerseRef(ContentRef(.hisn, "2:255")))
    }
}

final class QuranPositionTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "QuranPositionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testRoundTripAndFormat() throws {
        let defaults = defaults()
        let store = UserDefaultsQuranPositionStore(defaults: defaults)
        XCTAssertNil(store.load())
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        store.save(QuranReadingPosition(QuranVerseRef(surah: 2, ayah: 255), savedAt: date))
        XCTAssertEqual(UserDefaultsQuranPositionStore(defaults: defaults).load()?.ref, QuranVerseRef(surah: 2, ayah: 255))
        let data = try XCTUnwrap(defaults.data(forKey: UserDefaultsQuranPositionStore.defaultKey))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"ayah":255,"savedAt":800000000,"surah":2,"version":1}"#)
    }

    func testBadDataIsRemoved() {
        let defaults = defaults()
        let key = UserDefaultsQuranPositionStore.defaultKey
        let store = UserDefaultsQuranPositionStore(defaults: defaults)
        for bad in ["nope", #"{"ayah":1,"savedAt":0,"surah":2,"version":2}"#, #"{"ayah":0,"savedAt":0,"surah":2,"version":1}"#] {
            defaults.set(Data(bad.utf8), forKey: key)
            XCTAssertNil(store.load(), bad)
            XCTAssertNil(defaults.data(forKey: key), bad)
        }
    }

    func testPositionOutsideTheQuranIsCleared() async throws {
        let library = try await QuranFixture.library()
        let store = InMemoryQuranPositionStore(QuranReadingPosition(QuranVerseRef(surah: 1, ayah: 9), savedAt: Date()))
        XCTAssertNil(store.validPosition(in: library))
        XCTAssertNil(store.position)
        store.save(QuranReadingPosition(QuranVerseRef(surah: 18, ayah: 10), savedAt: Date()))
        XCTAssertEqual(store.validPosition(in: library)?.ref, QuranVerseRef(surah: 18, ayah: 10))
    }
}

@MainActor
final class QuranReaderControllerTests: XCTestCase {
    func testOpenSavesAndScrollingDoesNot() async throws {
        let library = try await QuranFixture.library()
        let store = InMemoryQuranPositionStore()
        let controller = try XCTUnwrap(QuranReaderController(library: library, start: QuranVerseRef(surah: 18, ayah: 10),
                                                             store: store))
        XCTAssertEqual(store.position?.ref, QuranVerseRef(surah: 18, ayah: 10))
        controller.visible(ayah: 20)
        XCTAssertEqual(controller.currentAyah, 20)
        XCTAssertEqual(store.position?.ref, QuranVerseRef(surah: 18, ayah: 10), "scrolling alone does not write")
        controller.persist()
        XCTAssertEqual(store.position?.ref, QuranVerseRef(surah: 18, ayah: 20))
        controller.visible(ayah: 500)
        XCTAssertEqual(controller.currentAyah, 20, "out of range is ignored")
    }

    func testJumpAndChangeSurah() async throws {
        let library = try await QuranFixture.library()
        let store = InMemoryQuranPositionStore()
        let controller = try XCTUnwrap(QuranReaderController(library: library, start: QuranVerseRef(surah: 1, ayah: 1),
                                                             store: store))
        let requests = controller.scrollRequest
        XCTAssertTrue(controller.go(to: 7))
        XCTAssertFalse(controller.go(to: 8))
        XCTAssertEqual(controller.scrollRequest, requests + 1)
        XCTAssertEqual(store.position?.ref, QuranVerseRef(surah: 1, ayah: 7))
        XCTAssertNil(controller.previousSurah)
        XCTAssertEqual(controller.nextSurah?.id, 2)
        XCTAssertTrue(controller.open(surah: 2, ayah: 255))
        XCTAssertEqual(controller.juz, 3)
        XCTAssertEqual(controller.page, 42)
        XCTAssertEqual(store.position?.ref, QuranVerseRef(surah: 2, ayah: 255))
        XCTAssertFalse(controller.open(surah: 2, ayah: 287))
        XCTAssertFalse(controller.open(surah: 115))
        XCTAssertEqual(controller.progress, 255.0 / 286.0, accuracy: 1e-9)
        XCTAssertEqual(QuranAccessibility.position(controller), "الآية 255 من 286، الجزء 3، الصفحة 42")
    }

    func testReachingTheEndRecordsTheSurahForToday() async throws {
        let library = try await QuranFixture.library()
        let daily = InMemoryDailyProgressStore()
        let now = Date()
        let controller = try XCTUnwrap(QuranReaderController(library: library, start: QuranVerseRef(surah: 112, ayah: 1),
                                                             store: InMemoryQuranPositionStore(), dailyProgress: daily,
                                                             now: { now }))
        XCTAssertTrue(daily.days.isEmpty)
        controller.reachedEnd()
        XCTAssertEqual(daily.completed(on: DayKey(date: now)), [.quranSurah(112)])
    }

    func testInvalidStartIsRefused() async throws {
        let library = try await QuranFixture.library()
        XCTAssertNil(QuranReaderController(library: library, start: QuranVerseRef(surah: 1, ayah: 8),
                                           store: InMemoryQuranPositionStore()))
    }
}

final class QuranSearchTests: XCTestCase {
    func testIndexCoversEverything() async throws {
        let engine = try await QuranFixture.engine()
        XCTAssertEqual(engine.index.surahEntryCount, 114)
        XCTAssertEqual(engine.index.verseEntryCount, 6236)
    }

    func testSurahNameComesFirst() async throws {
        let results = try await QuranFixture.engine().search("البقرة")
        let first = try XCTUnwrap(results.first)
        XCTAssertEqual(first.kind, .surah)
        XCTAssertEqual(first.surah, 2)
        XCTAssertEqual(first.rank, .surahExact)
    }

    func testStandardSpellingFindsUthmaniVerses() async throws {
        let engine = try await QuranFixture.engine()
        let fatiha = engine.search("الحمد لله رب العالمين")
        XCTAssertEqual(fatiha.first?.ref, QuranVerseRef(surah: 1, ayah: 2))
        XCTAssertEqual(fatiha.first?.rank, .verseExact)
        let rahman = engine.search("الرحمن")
        XCTAssertTrue(rahman.contains { $0.ref == QuranVerseRef(surah: 55, ayah: 1) && $0.rank == .verseExact })
        XCTAssertTrue(rahman.contains { $0.kind == .surah && $0.surah == 55 })
        let kursi = engine.search("الله لا اله الا هو الحي القيوم")
        XCTAssertTrue(kursi.prefix(3).contains { $0.ref == QuranVerseRef(surah: 2, ayah: 255) })
    }

    func testRankingAndOrderAreDeterministic() async throws {
        let engine = try await QuranFixture.engine()
        let results = engine.search("الله")
        XCTAssertGreaterThan(results.count, 1000)
        for (a, b) in zip(results, results.dropFirst()) {
            XCTAssertTrue((a.rank, a.order) < (b.rank, b.order))
        }
        XCTAssertEqual(results, engine.search("اللَّه"))
        XCTAssertTrue(engine.search("").isEmpty)
        XCTAssertTrue(engine.search("zzz").isEmpty)
        XCTAssertTrue(engine.search("ززززز").isEmpty)
    }

    func testFiltersAndPreviews() async throws {
        let library = try await QuranFixture.library()
        let engine = try await QuranFixture.engine()
        XCTAssertTrue(engine.search("الناس", filter: .surahs).allSatisfy { $0.kind == .surah })
        let verses = engine.search("الناس", filter: .verses)
        XCTAssertTrue(verses.allSatisfy { $0.kind == .verse })
        for result in verses.prefix(200) {
            let stored = try XCTUnwrap(library.verse(result.ref)).arabicText
            var shown = result.matchedText
            if shown.hasPrefix("… ") { shown.removeFirst(2) }
            if shown.hasSuffix(" …") { shown.removeLast(2) }
            XCTAssertTrue(stored.contains(shown), result.id)
            let range = try XCTUnwrap(result.highlight)
            XCTAssertLessThanOrEqual(range.upperBound, result.matchedText.count)
        }
    }

    func testShareContentKeepsTheTextVerbatim() async throws {
        let library = try await QuranFixture.library()
        let verse = try XCTUnwrap(library.verse(QuranVerseRef(surah: 2, ayah: 255)))
        let share = QuranShareContent(verse: verse, surah: try XCTUnwrap(library.surah(2)))
        XCTAssertEqual(share.text, verse.arabicText)
        XCTAssertEqual(share.reference, "سورة البقرة، الآية 255")
        XCTAssertEqual(share.copyText, verse.arabicText + "\nسورة البقرة، الآية 255")
    }

    func testAccessibilityText() async throws {
        let library = try await QuranFixture.library()
        XCTAssertEqual(QuranAccessibility.surahLabel(try XCTUnwrap(library.surah(1))), "سورة الفاتحة، رقم 1، مكية، 7 آيات")
        XCTAssertEqual(QuranAccessibility.surahLabel(try XCTUnwrap(library.surah(2))), "سورة البقرة، رقم 2، مدنية، 286 آية")
        XCTAssertEqual(QuranAccessibility.verseCount(1), "آية واحدة")
        XCTAssertEqual(QuranAccessibility.verseCount(2), "آيتان")
        XCTAssertEqual(QuranAccessibility.juzLabel(2, start: QuranVerseRef(surah: 2, ayah: 142), library: library),
                       "الجزء 2، يبدأ من سورة البقرة، الآية 142")
    }
}
