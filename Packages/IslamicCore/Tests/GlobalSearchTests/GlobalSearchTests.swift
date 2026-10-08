import XCTest
import IslamicCore
import ContentKit
import QuranReading
import HisnReading
import AdhkarReading
@testable import GlobalSearch

final class GlobalSearchTests: XCTestCase {
    private static var cached: GlobalSearchEngine?

    private func engine() async throws -> GlobalSearchEngine {
        if let cached = Self.cached { return cached }
        let quran = try await QuranLibrary.load()
        let book = try await BundledHisnRepository().loadBook()
        let adhkar = try await AdhkarLibrary.load()
        let engine = GlobalSearchEngine(
            quran: (quran, QuranSearchEngine(index: QuranSearchIndex(library: quran))),
            hisn: (book, HisnSearchEngine(index: HisnSearchIndex(book: book))),
            adhkar: (adhkar, DevotionalSearchIndex(library: adhkar)))
        Self.cached = engine
        return engine
    }

    func testEmptyAndNonArabicQueries() async throws {
        let engine = try await engine()
        XCTAssertEqual(engine.search(""), .empty)
        XCTAssertEqual(engine.search("  ،. "), .empty)
        XCTAssertTrue(engine.search("hello").results.isEmpty)
    }

    func testResultsSpanEverySourceAndAreRanked() async throws {
        let engine = try await engine()
        let response = engine.search("الحمد لله")
        XCTAssertNil(response.correctedQuery)
        let sources = Set(response.results.map(\.source))
        XCTAssertTrue(sources.isSuperset(of: [.quran, .hisn]))
        for pair in zip(response.results, response.results.dropFirst()) {
            let a = (pair.0.strength, pair.0.isTitle ? 0 : 1, pair.0.source.rawValue, pair.0.order)
            let b = (pair.1.strength, pair.1.isTitle ? 0 : 1, pair.1.source.rawValue, pair.1.order)
            XCTAssertTrue(a <= b)
        }
        XCTAssertEqual(Set(response.results.map(\.id)).count, response.results.count)
        XCTAssertEqual(response, engine.search("الْحَمْدُ لِلَّهِ"))
    }

    func testTitlesComeFirstAndDestinationsResolve() async throws {
        let engine = try await engine()
        let first = try XCTUnwrap(engine.search("البقرة").results.first)
        XCTAssertTrue(first.isTitle)
        XCTAssertEqual(first.source, .quran)
        XCTAssertEqual(first.destination, .quran(QuranVerseRef(surah: 2, ayah: 1), highlights: false))

        let morning = engine.search("أذكار الصباح").results
        XCTAssertTrue(morning.contains { $0.destination == .devotional(collection: .dhikrGroup("morning"), item: nil) })
        XCTAssertTrue(morning.contains { if case .hisn = $0.destination { return $0.isTitle } else { return false } })
    }

    func testSourceFilterAndLimit() async throws {
        let engine = try await engine()
        let quranOnly = engine.search("الله", source: .quran, limit: 20)
        XCTAssertEqual(quranOnly.results.count, 20)
        XCTAssertTrue(quranOnly.results.allSatisfy { $0.source == .quran })
        XCTAssertGreaterThan(quranOnly.totals[.quran] ?? 0, 1000)
        XCTAssertNil(quranOnly.totals[.hisn])
    }

    func testTypoSuggestionOnlyWhenNothingMatched() async throws {
        let engine = try await engine()
        // «الرحيم» with one letter changed; «الرجيم» is also one edit away but rarer.
        let typo = engine.search("الرخيم")
        XCTAssertEqual(typo.correctedQuery, "الرحيم")
        XCTAssertFalse(typo.results.isEmpty)
        // A query that matches as typed is never corrected.
        XCTAssertNil(engine.search("الرحيم").correctedQuery)
        // Short words are not corrected; nonsense gives nothing.
        XCTAssertNil(engine.search("زقص").correctedQuery)
        XCTAssertTrue(engine.search("قثصضطظغ").results.isEmpty)
        // Deterministic.
        XCTAssertEqual(engine.search("الرخيم"), typo)
    }

    func testEditDistance() {
        func check(_ a: String, _ b: String) -> Bool { SearchVocabulary.isOneEditAway(Array(a), Array(b)) }
        XCTAssertTrue(check("كتاب", "كتب"))
        XCTAssertTrue(check("كتب", "كتاب"))
        XCTAssertTrue(check("قلب", "قلت"))
        XCTAssertTrue(check("رحمين", "رحيمن"))
        XCTAssertFalse(check("رحمه", "رحمه"))
        XCTAssertFalse(check("كتاب", "كاتبين"))
        XCTAssertFalse(check("ابجد", "دجبا"))
    }

    func testContentIsUnchangedInResults() async throws {
        let engine = try await engine()
        let quran = try await QuranLibrary.load()
        for result in engine.search("رب العالمين", source: .quran).results {
            guard case .quran(let ref, true) = result.destination else { continue }
            let text = try XCTUnwrap(quran.verse(ref)?.arabicText)
            let body = result.matchedText.replacingOccurrences(of: "… ", with: "").replacingOccurrences(of: " …", with: "")
            XCTAssertTrue(text.contains(body))
        }
    }
}
