import XCTest
import IslamicCore
@testable import HisnReading

/// Phase 3A: offline search over the domain `searchText` fields.
final class HisnSearchTests: XCTestCase {
    private static var cached: (HisnLibrary, HisnSearchIndex)?

    private func fixture() async throws -> (library: HisnLibrary, index: HisnSearchIndex) {
        if let cached = Self.cached { return cached }
        let book = try await BundledHisnRepository().loadBook()
        let fixture = (HisnLibrary(book: book), HisnSearchIndex(book: book))
        Self.cached = fixture
        return fixture
    }

    /// The query key follows the content builder's rule, so it agrees with every bundled key.
    func testQueryKeyMatchesTheBundledSearchKeys() async throws {
        let book = try await fixture().library.book
        for chapter in book.chapters {
            XCTAssertEqual(HisnSearchKey.make(chapter.titleArabic), chapter.searchText, chapter.id)
            for item in chapter.items {
                XCTAssertEqual(HisnSearchKey.make(item.arabicText), item.searchText, item.id)
            }
        }
    }

    func testQueryKeyIgnoresMarksAndLetterForms() {
        XCTAssertEqual(HisnSearchKey.make("الحَمْدُ لِلَّهِ"), "الحمد لله")
        XCTAssertEqual(HisnSearchKey.make("  أَحْيَانَا، إِلَيْهِ  "), "احيانا اليه")
        XCTAssertEqual(HisnSearchKey.make("مُوسَى رَحْمَة"), "موسي رحمه")
        XCTAssertEqual(HisnSearchKey.make("abc 123 ؟"), "")
    }

    func testExactMatchOpensTheItem() async throws {
        let (library, index) = try await fixture()
        let results = index.search("الحَمْدُ لِلَّهِ الذِي أَحْيَانَا")
        let first = try XCTUnwrap(results.first)
        XCTAssertEqual(first.match, .exact)
        XCTAssertEqual(first.kind, .item)
        XCTAssertEqual(first.chapterId, "hisn-ch-001")
        let chapter = try XCTUnwrap(library.chapter(id: first.chapterId))
        let reader = try XCTUnwrap(HisnReader(chapter: chapter, itemIndex: first.itemIndex))
        XCTAssertEqual(reader.currentItem.id, "hisn-001-01", "the result opens its item")
        XCTAssertEqual(first.itemText, reader.currentItem.arabicText, "the row shows the bundled text")
    }

    func testPartialMatchFindsPartOfAWord() async throws {
        let (library, index) = try await fixture()
        let results = index.search("احيان")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.match == .partial })
        let hit = try XCTUnwrap(results.first { $0.kind == .item })
        XCTAssertEqual(library.chapter(id: hit.chapterId)?.items[hit.itemIndex].id, "hisn-001-01")
    }

    func testExactResultsComeBeforePartialOnes() async throws {
        let results = try await fixture().index.search("سبحان الله وبحمده")
        XCTAssertGreaterThan(results.count, 1)
        let matches = results.map(\.match)
        XCTAssertEqual(matches, matches.sorted(), "exact first, then partial")
        XCTAssertTrue(matches.contains(.exact))
        XCTAssertTrue(matches.contains(.partial))
    }

    func testChapterTitleMatchOpensTheChapter() async throws {
        let results = try await fixture().index.search("أذكار الصباح")
        let chapter = try XCTUnwrap(results.first { $0.kind == .chapter })
        XCTAssertEqual(chapter.chapterId, "hisn-ch-027")
        XCTAssertEqual(chapter.itemIndex, 0)
        XCTAssertEqual(chapter.match, .exact)
        XCTAssertNil(chapter.itemText)
    }

    func testNoResults() async throws {
        let index = try await fixture().index
        XCTAssertTrue(index.search("ززززز").isEmpty)
        XCTAssertTrue(index.search("").isEmpty)
        XCTAssertTrue(index.search("   ").isEmpty)
        XCTAssertTrue(index.search("hello").isEmpty, "no Arabic letters, no results")
    }

    func testEveryResultPointsAtARealItem() async throws {
        let (library, index) = try await fixture()
        let results = index.search("الله")
        XCTAssertGreaterThan(results.count, 100)
        XCTAssertEqual(Set(results.map(\.id)).count, results.count, "no duplicate rows")
        for result in results {
            let chapter = try XCTUnwrap(library.chapter(id: result.chapterId))
            XCTAssertTrue(chapter.items.indices.contains(result.itemIndex), result.id)
            if result.kind == .item {
                XCTAssertTrue(chapter.items[result.itemIndex].searchText.contains("الله"), result.id)
            }
        }
    }
}
