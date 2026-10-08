import XCTest
import IslamicCore
@testable import HisnReading

/// Phase 3F: offline search (normalization, index, ranking, results, navigation).
final class HisnSearchTests: XCTestCase {
    private struct Fixture {
        let library: HisnLibrary
        let index: HisnSearchIndex
        let engine: HisnSearchEngine
    }

    private static var cached: Fixture?

    private func fixture() async throws -> Fixture {
        if let cached = Self.cached { return cached }
        let book = try await BundledHisnRepository().loadBook()
        let index = HisnSearchIndex(book: book)
        let fixture = Fixture(library: HisnLibrary(book: book), index: index, engine: HisnSearchEngine(index: index))
        Self.cached = fixture
        return fixture
    }

    // MARK: Normalization

    func testNormalizationRemovesTashkeel() {
        XCTAssertEqual(HisnSearchNormalizer.normalize("الحَمْدُ لِلَّهِ"), "الحمد لله")
        XCTAssertEqual(HisnSearchNormalizer.normalize("سُبْحَانَ اللَّهِ وَبِحَمْدِهِ"), "سبحان الله وبحمده")
    }

    func testNormalizationFoldsAlefForms() {
        XCTAssertEqual(HisnSearchNormalizer.normalize("أَحْيَانَا إِلَيْهِ آمَنَ ٱللَّه"), "احيانا اليه امن الله")
    }

    func testNormalizationFoldsAlefMaksuraAndTaMarbuta() {
        XCTAssertEqual(HisnSearchNormalizer.normalize("مُوسَى عَلَى"), "موسي علي")
        XCTAssertEqual(HisnSearchNormalizer.normalize("رَحْمَة الصَّلَاةِ"), "رحمه الصلاه")
        XCTAssertEqual(HisnSearchNormalizer.normalize("صلاة"), HisnSearchNormalizer.normalize("صلاه"))
    }

    func testNormalizationRemovesTatweel() {
        XCTAssertEqual(HisnSearchNormalizer.normalize("الحـــمد لـله"), "الحمد لله")
    }

    func testNormalizationCollapsesWhitespace() {
        XCTAssertEqual(HisnSearchNormalizer.normalize("  الحمد \n\t  لله  "), "الحمد لله")
    }

    func testNormalizationSeparatesPunctuation() {
        XCTAssertEqual(HisnSearchNormalizer.normalize("«الحمد لله»، (سبحان) الله. ﴿قل﴾"), "الحمد لله سبحان الله قل")
        XCTAssertEqual(HisnSearchNormalizer.normalize("abc 123 ؟ !"), "")
        XCTAssertEqual(HisnSearchNormalizer.normalize(""), "")
    }

    /// Each key character points back at its letter in the original text.
    func testNormalizationMapsBackToTheSource() {
        let mapped = HisnSearchNormalizer.normalizeMapped("الحَمْدُ لِلَّهِ")
        XCTAssertEqual(mapped.key, "الحمد لله")
        XCTAssertEqual(mapped.sourceOffsets, [0, 1, 2, 4, 6, 8, 9, 11, 14])
        let scalars = Array("الحَمْدُ لِلَّهِ".unicodeScalars)
        for (keyScalar, offset) in zip(mapped.key.unicodeScalars, mapped.sourceOffsets) where keyScalar != " " {
            XCTAssertEqual(scalars[offset], keyScalar)
        }
    }

    /// The query rule is the content builder's rule, so it agrees with every bundled key.
    func testNormalizationMatchesTheBundledSearchKeys() async throws {
        let book = try await fixture().library.book
        for chapter in book.chapters {
            XCTAssertEqual(HisnSearchNormalizer.normalize(chapter.titleArabic), chapter.searchText, chapter.id)
            for item in chapter.items {
                XCTAssertEqual(HisnSearchNormalizer.normalize(item.arabicText), item.searchText, item.id)
            }
        }
    }

    // MARK: Ranking

    func testEmptyQueryReturnsNothing() async throws {
        let engine = try await fixture().engine
        XCTAssertTrue(engine.search("").isEmpty)
        XCTAssertTrue(engine.search("   \n").isEmpty)
        XCTAssertTrue(engine.search("hello 42").isEmpty, "no Arabic letters, no results")
        XCTAssertFalse(HisnSearchEngine.isSearchable("  "))
        XCTAssertTrue(HisnSearchEngine.isSearchable("ذكر"))
    }

    func testNoResults() async throws {
        let engine = try await fixture().engine
        XCTAssertTrue(engine.search("ززززز").isEmpty)
    }

    func testExactChapterMatchComesFirst() async throws {
        let results = try await fixture().engine.search("أَذْكَارُ النَّوْمِ")
        XCTAssertEqual(results.map(\.chapterId), ["hisn-ch-029", "hisn-ch-001"])
        XCTAssertEqual(results.map(\.rank), [.chapterExact, .chapterPartial])
        XCTAssertTrue(results.allSatisfy { $0.kind == .chapter && $0.itemId == nil && $0.itemIndex == nil })
    }

    func testChapterPrefixMatch() async throws {
        let results = try await fixture().engine.search("دعاء لبس الثوب")
        XCTAssertEqual(results.map(\.chapterId), ["hisn-ch-002", "hisn-ch-003"])
        XCTAssertEqual(results.map(\.rank), [.chapterExact, .chapterPrefix])
    }

    func testPartialChapterMatchKeepsBookOrder() async throws {
        let results = try await fixture().engine.search("النوم")
        XCTAssertEqual(results.map(\.chapterId), ["hisn-ch-001", "hisn-ch-029", "hisn-ch-031"])
        XCTAssertTrue(results.allSatisfy { $0.rank == .chapterPartial })
    }

    func testExactItemMatchComesBeforePrefixMatches() async throws {
        let results = try await fixture().engine.search("سُبْحَانَ اللَّهِ")
        XCTAssertEqual(results.prefix(2).map(\.itemId), ["hisn-029-08", "hisn-123-01"])
        XCTAssertEqual(results.prefix(2).map(\.rank), [.textExact, .textExact])
        XCTAssertEqual(results[2].rank, .textPrefix)
    }

    func testPartialItemMatchFindsPartOfAWord() async throws {
        let results = try await fixture().engine.search("احيان")
        let hit = try XCTUnwrap(results.first { $0.itemId == "hisn-001-01" })
        XCTAssertEqual(hit.rank, .textPartial)
        XCTAssertEqual(hit.kind, .item)
        XCTAssertEqual(hit.chapterId, "hisn-ch-001")
        XCTAssertEqual(hit.itemIndex, 0)
    }

    func testMultipleResultsAreRankedThenInBookOrder() async throws {
        let engine = try await fixture().engine
        for query in ["الله", "لا اله الا الله", "الله اكبر", "اذكار", "دعاء"] {
            let results = engine.search(query)
            XCTAssertGreaterThan(results.count, 1, query)
            for (previous, next) in zip(results, results.dropFirst()) {
                XCTAssertTrue((previous.rank, previous.order) < (next.rank, next.order), "\(query): \(next.id)")
            }
            XCTAssertEqual(Set(results.map(\.id)).count, results.count, "\(query): no duplicate rows")
        }
    }

    func testRankingIsDeterministic() async throws {
        let engine = try await fixture().engine
        for query in ["الله", "سبحان", "النوم", "رب"] {
            XCTAssertEqual(engine.search(query), engine.search(query), query)
        }
        let rebuilt = try await HisnSearchEngine(index: HisnSearchIndex(book: fixture().library.book))
        XCTAssertEqual(rebuilt.search("الله"), engine.search("الله"))
    }

    func testFilters() async throws {
        let engine = try await fixture().engine
        let all = engine.search("الله")
        let chapters = engine.search("الله", filter: .chapters)
        let texts = engine.search("الله", filter: .texts)
        XCTAssertFalse(chapters.isEmpty)
        XCTAssertFalse(texts.isEmpty)
        XCTAssertTrue(chapters.allSatisfy { $0.kind == .chapter })
        XCTAssertTrue(texts.allSatisfy { $0.kind == .item })
        XCTAssertEqual(all.count, chapters.count + texts.count)
        XCTAssertEqual(all.filter { $0.kind == .chapter }, chapters)
        XCTAssertEqual(all.filter { $0.kind == .item }, texts)
    }

    // MARK: Results

    func testResultsPointAtRealItemsAndShowStoredText() async throws {
        let (library, engine) = try await (fixture().library, fixture().engine)
        let results = engine.search("الله")
        XCTAssertGreaterThan(results.count, 100)
        for result in results {
            let chapter = try XCTUnwrap(library.chapter(id: result.chapterId), result.id)
            XCTAssertEqual(result.chapterTitle, chapter.titleArabic)
            XCTAssertEqual(result.chapterItemCount, chapter.itemCount)
            let stored: String
            if result.kind == .item {
                let index = try XCTUnwrap(result.itemIndex)
                XCTAssertEqual(chapter.items[index].id, result.itemId)
                stored = chapter.items[index].arabicText
            } else {
                stored = chapter.titleArabic
            }
            // The preview is the stored text, or a run of it between «… » / « …».
            var shown = result.matchedText
            if shown.hasPrefix("… ") { shown.removeFirst(2) }
            if shown.hasSuffix(" …") { shown.removeLast(2) }
            XCTAssertTrue(stored.contains(shown), result.id)
            if shown.count == result.matchedText.count { XCTAssertEqual(shown, stored, result.id) }
        }
    }

    /// The highlight covers whole words that contain the match, inside the preview.
    func testHighlightCoversWholeMatchingWords() async throws {
        let engine = try await fixture().engine
        for query in ["الله", "سُبْحَانَ اللَّهِ", "احيان", "النوم", "تفلحون"] {
            let words = HisnSearchNormalizer.normalize(query).split(separator: " ").map(String.init)
            for result in engine.search(query) {
                let characters = Array(result.matchedText)
                let range = try XCTUnwrap(result.highlight, "\(query): \(result.id)")
                XCTAssertTrue(range.lowerBound >= 0 && range.upperBound <= characters.count && !range.isEmpty)
                if range.lowerBound > 0 { XCTAssertTrue(HisnSearchEngine.isSeparator(characters[range.lowerBound - 1])) }
                if range.upperBound < characters.count {
                    XCTAssertTrue(HisnSearchEngine.isSeparator(characters[range.upperBound]))
                }
                let highlighted = HisnSearchNormalizer.normalize(String(characters[range]))
                XCTAssertTrue(words.contains { highlighted.contains($0) }, "\(query): \(result.id)")
            }
        }
    }

    /// A match deep in a long item shows a short excerpt around it, cut between words.
    func testLongItemShowsAnExcerptAroundTheMatch() async throws {
        let (library, engine) = try await (fixture().library, fixture().engine)
        let result = try XCTUnwrap(engine.search("تفلحون").first { $0.itemId == "hisn-001-04" })
        let stored = try XCTUnwrap(library.chapter(id: "hisn-ch-001")?.items[3].arabicText)
        XCTAssertGreaterThan(stored.count, 1000)
        XCTAssertTrue(result.matchedText.hasPrefix("… "))
        XCTAssertLessThan(result.matchedText.count, 400)
        let range = try XCTUnwrap(result.highlight)
        let word = String(Array(result.matchedText)[range])
        XCTAssertEqual(HisnSearchNormalizer.normalize(word), "تفلحون")
    }

    // MARK: Navigation

    private func result(_ query: String, item itemId: String) async throws -> HisnSearchResult {
        let results = try await fixture().engine.search(query)
        return try XCTUnwrap(results.first { $0.itemId == itemId })
    }

    func testChapterResultOpensTheChapter() async throws {
        let library = try await fixture().library
        let engine = try await fixture().engine
        let chapter = try XCTUnwrap(engine.search("أذكار النوم").first)
        let destination = try XCTUnwrap(HisnSearchDestination.resolve(chapter, in: library, cursor: nil))
        XCTAssertEqual(destination, HisnSearchDestination(chapterId: "hisn-ch-029", itemIndex: 0,
                                                          completedRepetitions: 0, highlightedItemId: nil))
        // With the saved place in that chapter, it opens there, as the index does.
        let cursor = HisnReadingPosition(chapterId: "hisn-ch-029", itemId: "hisn-029-03", itemIndex: 2,
                                         completedRepetitions: 1, savedAt: Date())
        let resumed = try XCTUnwrap(HisnSearchDestination.resolve(chapter, in: library, cursor: cursor))
        XCTAssertEqual(resumed.itemIndex, 2)
        XCTAssertEqual(resumed.completedRepetitions, 1)
    }

    func testItemResultOpensItsItem() async throws {
        let library = try await fixture().library
        let hit = try await result("سبحان الله", item: "hisn-123-01")
        let destination = try XCTUnwrap(HisnSearchDestination.resolve(hit, in: library, cursor: nil))
        XCTAssertEqual(destination.chapterId, "hisn-ch-123")
        XCTAssertEqual(destination.highlightedItemId, "hisn-123-01")
        XCTAssertEqual(destination.completedRepetitions, 0, "opening a result counts nothing")
        let chapter = try XCTUnwrap(library.chapter(id: destination.chapterId))
        let reader = try XCTUnwrap(HisnReader(chapter: chapter, itemIndex: destination.itemIndex,
                                              completedRepetitions: destination.completedRepetitions))
        XCTAssertEqual(reader.currentItem.id, "hisn-123-01")
        XCTAssertFalse(reader.isCompleted)
    }

    /// Opening the item the reader saved keeps its counted repetitions; any other item starts at zero.
    func testItemResultKeepsRepetitionsOnlyForTheSavedItem() async throws {
        let library = try await fixture().library
        let hit = try await result("سبحان الله", item: "hisn-123-01")
        let same = HisnReadingPosition(chapterId: "hisn-ch-123", itemId: "hisn-123-01", itemIndex: hit.itemIndex ?? 0,
                                       completedRepetitions: 2, savedAt: Date())
        XCTAssertEqual(HisnSearchDestination.resolve(hit, in: library, cursor: same)?.completedRepetitions, 2)
        let other = HisnReadingPosition(chapterId: "hisn-ch-123", itemId: "hisn-123-02", itemIndex: 1,
                                        completedRepetitions: 2, savedAt: Date())
        XCTAssertEqual(HisnSearchDestination.resolve(hit, in: library, cursor: other)?.completedRepetitions, 0)
    }

    func testInvalidResultsResolveToNothing() async throws {
        let library = try await fixture().library
        func make(_ kind: HisnSearchResult.Kind, chapter: String, item: String?, index: Int?) -> HisnSearchResult {
            HisnSearchResult(kind: kind, rank: .textPartial, order: 0, chapterId: chapter, chapterTitle: "",
                             chapterItemCount: 0, itemId: item, itemIndex: index, matchedText: "", highlight: nil)
        }
        XCTAssertNil(HisnSearchDestination.resolve(make(.chapter, chapter: "hisn-ch-999", item: nil, index: nil),
                                                   in: library, cursor: nil))
        XCTAssertNil(HisnSearchDestination.resolve(make(.item, chapter: "hisn-ch-001", item: "hisn-001-01", index: 40),
                                                   in: library, cursor: nil))
        XCTAssertNil(HisnSearchDestination.resolve(make(.item, chapter: "hisn-ch-001", item: "hisn-002-01", index: 0),
                                                   in: library, cursor: nil))
        XCTAssertNil(HisnSearchDestination.resolve(make(.item, chapter: "hisn-ch-001", item: nil, index: nil),
                                                   in: library, cursor: nil))
    }

    // MARK: Accessibility

    func testSearchAccessibilityText() async throws {
        let engine = try await fixture().engine
        let chapter = try XCTUnwrap(engine.search("أذكار النوم").first)
        XCTAssertEqual(HisnAccessibility.searchResultLabel(chapter), "باب، \(chapter.chapterTitle)")
        XCTAssertEqual(HisnAccessibility.searchResultHint(chapter), "يفتح الباب")
        let item = try XCTUnwrap(engine.search("سبحان الله").first)
        XCTAssertEqual(HisnAccessibility.searchResultLabel(item),
                       "ذكر، الذكر \((item.itemIndex ?? 0) + 1) من \(item.chapterItemCount)، \(item.chapterTitle)")
        XCTAssertEqual(HisnAccessibility.searchResultValue(item), item.matchedText)
        XCTAssertEqual(HisnAccessibility.searchResultHint(item), "يفتح الذكر في موضعه")

        XCTAssertEqual(HisnAccessibility.resultCount(0), "لا توجد نتائج")
        XCTAssertEqual(HisnAccessibility.resultCount(1), "نتيجة واحدة")
        XCTAssertEqual(HisnAccessibility.resultCount(2), "نتيجتان")
        XCTAssertEqual(HisnAccessibility.resultCount(7), "7 نتائج")
        XCTAssertEqual(HisnAccessibility.resultCount(23), "23 نتيجة")
        XCTAssertEqual(HisnSearchFilter.allCases.map(HisnAccessibility.filterTitle), ["الكل", "الأبواب", "النصوص"])

        let fixed = [HisnAccessibility.searchField, HisnAccessibility.clearSearch, HisnAccessibility.searchFilter]
        XCTAssertEqual(fixed, ["بحث في حصن المسلم", "مسح البحث", "نوع النتائج"])
        for text in fixed + [HisnAccessibility.searchResultLabel(chapter), HisnAccessibility.searchResultHint(item)] {
            XCTAssertFalse(text.unicodeScalars.contains { $0.isASCII && CharacterSet.letters.contains($0) }, text)
        }
    }

    // MARK: Content integrity and performance

    func testIndexCoversTheWholeBookWithoutChangingIt() async throws {
        let (library, index) = try await (fixture().library, fixture().index)
        let book = library.book
        XCTAssertEqual(book.canonicalChapters.count, 132)
        XCTAssertEqual(book.bookItemNumbers.count, 267)
        XCTAssertEqual(book.chapters.count, 133)
        XCTAssertEqual(book.itemCount, 302)
        XCTAssertEqual(index.chapterEntryCount, 133)
        XCTAssertEqual(index.itemEntryCount, 302)
        let stored = book.chapters.flatMap { [$0.titleArabic] + $0.items.map(\.arabicText) }
        XCTAssertEqual(index.entries.map(\.text), stored, "the index holds the stored text unchanged")
        let reloaded = try await BundledHisnRepository().loadBook()
        XCTAssertEqual(reloaded.allItems.map(\.arabicText), book.allItems.map(\.arabicText))
    }

    /// Queries reuse the one index; correctness holds across many queries over all 435 entries.
    func testQueriesReuseTheIndex() async throws {
        let (index, engine) = try await (fixture().index, fixture().engine)
        let queries = ["ا", "ال", "الل", "الله", "الله ا", "الله اك", "الله اكبر", "سبحان", "رب اغفر", "ززز"]
        var counts: [Int] = []
        for query in queries {
            let results = engine.search(query)
            XCTAssertTrue(engine.index === index)
            counts.append(results.count)
        }
        // Each extra letter narrows (or keeps) the full-text results for a growing word.
        XCTAssertEqual(counts.prefix(4).map { $0 }, counts.prefix(4).sorted(by: >))
        XCTAssertEqual(counts.last, 0)
    }
}
