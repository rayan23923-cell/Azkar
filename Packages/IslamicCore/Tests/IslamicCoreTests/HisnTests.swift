import XCTest
@testable import IslamicCore
#if canImport(CryptoKit)
import CryptoKit
#endif

final class HisnRepositoryTests: XCTestCase {
    let repository = BundledHisnRepository()
    let quran = BundledQuranRepository()

    static let upstreamFile = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Upstream/hisn/asellam/hisn.json")

    /// SHA-256 of hisn.json as downloaded from github.com/asellam/HisnElMuslim on 2026-10-08.
    static let upstreamSHA256 = "b30a448ef40184b0422c40bd3c372bf2b25bfb5b0539fd3699e6b4fba9459d80"

    // MARK: Book

    func testBookMetadataAndProvenance() async throws {
        let book = try await repository.loadBook()
        XCTAssertEqual(book.id, "hisn-al-muslim")
        assertArabicIntegrity(book.titleArabic, "title")
        assertArabicIntegrity(book.author, "author")
        XCTAssertEqual(book.provenance.primarySource.sha256, Self.upstreamSHA256)
        XCTAssertEqual(book.provenance.primarySource.url, "https://github.com/asellam/HisnElMuslim")
        XCTAssertEqual(book.provenance.canonicalEdition.comparison, "NOT_YET_COMPARED")
        XCTAssertEqual(book.attribution.rightsStatus, .pendingPreReleaseReview)
        XCTAssertNil(book.attribution.attributionText, "attribution wording is not final")
    }

    func testUpstreamFileIsUnchanged() throws {
        #if canImport(CryptoKit)
        let data = try Data(contentsOf: Self.upstreamFile)
        XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), Self.upstreamSHA256)
        #else
        throw XCTSkip("CryptoKit unavailable")
        #endif
    }

    /// Every bundled item is the upstream text, character for character, in upstream order.
    func testBundledTextEqualsUpstream() async throws {
        let data = try Data(contentsOf: Self.upstreamFile)
        let upstream = try JSONDecoder().decode([String: UpstreamChapter].self, from: data)
        let order = try upstreamChapterOrder(data)
        let chapters = try await repository.loadChapters()
        XCTAssertEqual(chapters.map(\.titleArabic), order)
        for chapter in chapters {
            let source = try XCTUnwrap(upstream[chapter.titleArabic])
            XCTAssertEqual(chapter.items.map(\.arabicText), source.Adhkar.map(\.Text), chapter.id)
            XCTAssertEqual(chapter.items.map(\.repetition.sourceCount), source.Adhkar.map(\.Count), chapter.id)
            XCTAssertEqual(chapter.items.map { $0.references.first?.originalText ?? "" },
                           source.Adhkar.map { $0.Reference.trimmingCharacters(in: .whitespacesAndNewlines) }, chapter.id)
        }
    }

    // MARK: Chapters

    func testChaptersAreUniqueOrderedAndTitled() async throws {
        let chapters = try await repository.loadChapters()
        XCTAssertFalse(chapters.isEmpty)
        XCTAssertEqual(Set(chapters.map(\.id)).count, chapters.count)
        XCTAssertEqual(chapters.map(\.number), Array(1...chapters.count))
        for chapter in chapters {
            assertArabicIntegrity(chapter.titleArabic, chapter.id)
            XCTAssertFalse(chapter.searchText.isEmpty, chapter.id)
            XCTAssertEqual(chapter.itemCount, chapter.items.count)
        }
        XCTAssertEqual(chapters.first?.titleArabic, "أَذْكَارُ الِاسْتِيقَاظِ مِنَ النَّوْمِ")
    }

    func testBookChapterNumbersFollowTheBook() async throws {
        let numbers = try await repository.loadChapters().compactMap(\.bookChapterNumber)
        XCTAssertEqual(numbers, numbers.sorted(), "chapters keep the book's order")
        XCTAssertEqual(Set(numbers).count, 132, "every book chapter is represented")
    }

    // MARK: Items

    func testItemsAreUniqueOrderedAndInTheirChapter() async throws {
        var ids = Set<String>()
        for chapter in try await repository.loadChapters() {
            XCTAssertFalse(chapter.items.isEmpty, chapter.id)
            XCTAssertEqual(chapter.items.map(\.order), Array(1...chapter.items.count), chapter.id)
            for item in chapter.items {
                XCTAssertEqual(item.chapterId, chapter.id)
                XCTAssertTrue(ids.insert(item.id).inserted, "duplicate \(item.id)")
                assertArabicIntegrity(item.arabicText, item.id)
                XCTAssertFalse(item.searchText.isEmpty, item.id)
                XCTAssertNil(item.searchText.unicodeScalars.first { (0x064B...0x0652).contains($0.value) },
                             "\(item.id): search text keeps diacritics")
            }
        }
    }

    func testBookItemNumbersFollowTheBookInBookOrder() async throws {
        // Display order is the source's; three chapters list two book items the other way round.
        for chapter in try await repository.loadChapters() {
            let numbers = chapter.itemsInBookOrder.compactMap(\.bookItemNumber)
            XCTAssertEqual(numbers, numbers.sorted(), chapter.id)
            XCTAssertTrue(numbers.allSatisfy { (1...267).contains($0) }, chapter.id)
        }
    }

    func testLoadByIdAndUnknownIds() async throws {
        let item = try await repository.loadItem(id: "hisn-001-01")
        XCTAssertEqual(item.chapterId, "hisn-ch-001")
        XCTAssertEqual(item.bookItemNumber, 1)
        XCTAssertTrue(item.arabicText.hasPrefix("الحَمْدُ لِلَّهِ الذِي أَحْيَانَا"))
        let chapter = try await repository.loadChapter(id: "hisn-ch-001")
        XCTAssertEqual(chapter.items.first, item)
        await assertNotFound { _ = try await self.repository.loadItem(id: "missing") }
        await assertNotFound { _ = try await self.repository.loadChapter(id: "missing") }
    }

    // MARK: References

    func testReferencesKeepTheFullOriginalText() async throws {
        let item = try await repository.loadItem(id: "hisn-001-01")
        XCTAssertEqual(item.references, [HisnReference(originalText: "البخاري مع الفتح 11/ 113 ومسلم 4/ 2083",
                                                       collections: ["البخاري", "مسلم"])])
        for item in try await repository.loadBook().allItems {
            for reference in item.references {
                XCTAssertFalse(reference.originalText.isEmpty, item.id)
                // Names are indexed on the text without diacritics (e.g. البيهقيّ → البيهقي).
                let bare = String(String.UnicodeScalarView(reference.originalText.unicodeScalars.filter {
                    let v = $0.value
                    return !((0x0610...0x061A).contains(v) || (0x064B...0x065F).contains(v) || v == 0x0670
                             || (0x06D6...0x06ED).contains(v) || v == 0x0640)
                }))
                for name in reference.collections {
                    XCTAssertTrue(bare.contains(name), "\(item.id): \(name)")
                }
            }
        }
    }

    // MARK: Quran

    func testQuranCitationsResolveAgainstTanzil() async throws {
        var resolved = 0
        for item in try await repository.loadBook().allItems {
            for citation in item.quranCitations {
                let verses = try await quran.loadVerses(citation.reference)
                XCTAssertEqual(verses.count, citation.reference.toAyah - citation.reference.fromAyah + 1, item.id)
                resolved += 1
            }
        }
        XCTAssertGreaterThan(resolved, 0)
        let kursi = try await repository.loadItem(id: "hisn-027-02")
        XCTAssertEqual(kursi.quranCitations, [HisnQuranCitation(reference: QuranReference(surah: 2, ayah: 255),
                                                                coversWholeVerses: true, match: .exact)])
        let qul = try await repository.loadItem(id: "hisn-027-03")
        XCTAssertEqual(qul.quranCitations.map(\.reference.surah), [112, 113, 114])
    }

    func testUnresolvedQuranIsReportedNotGuessed() async throws {
        let items = try await repository.loadBook().allItems
        // Phase 2E resolved the last open passages through the correction manifest; any
        // passage still open must carry the Phase 2C flag that reported it.
        for item in items where item.quranStatus == .partial || item.quranStatus == .unresolved {
            XCTAssertTrue(item.reviewFlags.contains { $0.hasPrefix("QURAN_SEGMENT_UNRESOLVED") }, item.id)
        }
        for item in items where item.quranCitations.contains(where: { $0.match == .fuzzy }) {
            XCTAssertTrue(item.reviewFlags.contains { $0.hasPrefix("QURAN_FUZZY_MATCH") }, item.id)
        }
        // A Phase 2C finding is only cleared by an applied manifest entry.
        let reported = items.filter { item in
            item.reviewFlags.contains { $0.hasPrefix("QURAN_FUZZY_MATCH") || $0.hasPrefix("QURAN_SEGMENT_UNRESOLVED") }
        }
        XCTAssertEqual(reported.map(\.id), ["hisn-001-04", "hisn-029-03", "hisn-029-14"])
        for item in reported where item.quranStatus == .resolved && item.quranCitations.allSatisfy({ $0.match == .exact }) {
            XCTAssertFalse(item.corrections.applied.isEmpty, item.id)
        }
    }

    // MARK: Repetition

    func testRepeatCountsArePositiveOrAbsent() async throws {
        for item in try await repository.loadBook().allItems {
            XCTAssertGreaterThanOrEqual(item.repetition.sourceCount, 1, item.id)
            if let count = item.repetition.count {
                XCTAssertGreaterThanOrEqual(count, 1, item.id)
                XCTAssertEqual(count, item.repetition.sourceCount, item.id)
            } else {
                XCTAssertTrue(item.reviewFlags.contains { $0.hasPrefix("REPEAT_CONFLICT") }, item.id)
            }
            XCTAssertEqual(item.repeatCount, item.repetition.count ?? 1)
            XCTAssertEqual(item.repetition.reviewStatus, .reviewRequired, item.id)
        }
    }

    func testRepeatCountIsNilWhenTheBookDisagrees() async throws {
        // Source says 1, book text says "ثلاثاً" inside the item: no structured count.
        let item = try await repository.loadItem(id: "hisn-025-01")
        XCTAssertNil(item.repetition.count)
        XCTAssertEqual(item.repetition.sourceCount, 1)
        XCTAssertEqual(item.repetition.bookStatedCounts, [3])
        XCTAssertTrue(item.arabicText.contains("(ثَلَاثًا)"), "the wording stays in the text")
        let sleep = try await repository.loadChapter(id: "hisn-ch-029")
        XCTAssertEqual(sleep.items.suffix(from: 7).prefix(3).map(\.repetition.count), [33, 33, 34])
    }

    // MARK: Review status

    func testNothingIsSilentlyReviewed() async throws {
        for item in try await repository.loadBook().allItems {
            XCTAssertEqual(item.reviewStatus, .reviewRequired, item.id)
        }
    }

    // MARK: Session

    func testChapterSessionNavigation() async throws {
        let chapter = try await repository.loadChapter(id: "hisn-ch-001")
        var session = try XCTUnwrap(HisnSession(chapter: chapter))
        XCTAssertEqual(session.scope, .chapter(id: "hisn-ch-001"))
        XCTAssertEqual(session.currentItem.id, "hisn-001-01")
        XCTAssertEqual(session.currentChapterTitle, chapter.titleArabic)
        XCTAssertFalse(session.previous())
        XCTAssertTrue(session.next())
        XCTAssertEqual(session.currentItem.order, 2)
        XCTAssertEqual(session.progress, 1.0 / Double(chapter.items.count), accuracy: 1e-9)
        while session.next() {}
        XCTAssertEqual(session.currentItem, chapter.items.last)
        session.restart()
        XCTAssertEqual(session.currentItem, chapter.items.first)
        XCTAssertEqual(session.progress, 0)
    }

    func testBookSessionCrossesChaptersAndCountsRepetitions() async throws {
        let book = try await repository.loadBook()
        let first = book.chapters[0]
        var session = try XCTUnwrap(HisnSession(book: book, startIndex: first.items.count - 1))
        XCTAssertEqual(session.currentChapterId, first.id)
        XCTAssertTrue(session.next())
        XCTAssertEqual(session.currentChapterId, book.chapters[1].id)
        XCTAssertEqual(session.currentChapterTitle, book.chapters[1].titleArabic)

        let morning = try await repository.loadChapter(id: "hisn-ch-027")
        var reading = try XCTUnwrap(HisnSession(chapter: morning, startIndex: 2))   // the three Quls, 3 times
        XCTAssertEqual(reading.cursor.advance(), .repeated(remaining: 2))
        XCTAssertEqual(reading.cursor.advance(), .repeated(remaining: 1))
        XCTAssertEqual(reading.cursor.advance(), .movedToNext)
        XCTAssertNil(HisnSession(book: book, startIndex: book.itemCount))
    }
}

// MARK: Invalid content

final class HisnInvalidContentTests: XCTestCase {
    private static let morning = #""MORNING""#
    private static let evening = #""EVENING""#

    private func repository(_ json: String) -> BundledHisnRepository {
        BundledHisnRepository(source: .data(Data(json.utf8)))
    }

    private func book(chapters: String) -> String {
        #"""
        {"formatVersion": 1, "contentVersion": 1,
         "book": {"id": "b", "titleArabic": "حصن", "author": "مؤلف",
          "provenance": {
            "primarySource": {"name": "n", "url": "u", "license": "l", "edition": "e", "upstreamFile": "f", "sha256": "s", "retrieved": "r"},
            "crossCheck": {"name": "n", "urls": [], "bookChapters": 1, "bookItems": 1},
            "canonicalEdition": {"name": "n", "url": "u", "sha256": "s", "comparison": "NOT_YET_COMPARED"},
            "corrections": {"manifest": "m", "sha256": "s", "total": 0, "accepted": 0, "observationOnly": 0,
                            "pendingDecision": 0, "p0Accepted": 0, "p0Pending": 0, "canonicalBookChapters": 1,
                            "canonicalBookItems": 1, "presentationSections": 1, "displayItems": 1}},
          "attribution": {"sourceTitle": "t", "author": "a", "edition": null, "sourceURL": "u", "attributionText": null,
                          "rightsStatus": "PENDING_PRE_RELEASE_REVIEW"}},
         "chapters": \#(chapters)}
        """#
    }

    private func item(id: String = "i1", chapter: String = "c1", order: Int = 1, text: String = "ذكر",
                      count: String = "1", status: String = "CONTENT_REVIEW_REQUIRED", number: String = "1",
                      relation: String = "DIRECT", citations: String = "[]", quranStatus: String = "NONE",
                      corrections: String = #"{"applied": [], "open": []}"#) -> String {
        #"""
        {"id": "\#(id)", "chapterId": "\#(chapter)", "order": \#(order), "bookItemNumber": \#(number),
         "bookItemRelation": "\#(relation)", "arabicText": "\#(text)",
         "searchText": "ذكر", "repetition": {"count": \#(count), "sourceCount": 1, "bookStatedCounts": [], "reviewStatus": "CONTENT_REVIEW_REQUIRED"},
         "references": [], "quranCitations": \#(citations), "quranStatus": "\#(quranStatus)", "reviewFlags": [],
         "corrections": \#(corrections), "reviewStatus": "\#(status)"}
        """#
    }

    private func chapter(id: String = "c1", number: Int = 1, bookChapter: String = "1", section: String = "null",
                         items: [String]) -> String {
        #"{"id": "\#(id)", "number": \#(number), "titleArabic": "باب", "searchText": "باب", "bookChapterNumber": \#(bookChapter), "presentationSection": \#(section), "items": [\#(items.joined(separator: ","))]}"#
    }

    private func citation(fromAyah: Int, wholeSurah: Bool) -> String {
        #"[{"reference": {"surah": 67, "fromAyah": \#(fromAyah), "toAyah": \#(fromAyah)}, "coversWholeVerses": false, "match": "EXACT", "recitesWholeSurah": \#(wholeSurah)}]"#
    }

    func testValidMinimalBookLoads() async throws {
        let minimal = try await repository(book(chapters: "[\(chapter(items: [item()]))]")).loadBook()
        XCTAssertEqual(minimal.itemCount, 1)
        let morning = chapter(section: Self.morning, items: [item()])
        let evening = chapter(id: "c2", number: 2, section: Self.evening,
                              items: [item(id: "i2", chapter: "c2", relation: "EVENING_VARIANT")])
        let split = "[\(morning), \(evening)]"
        let sections = try await repository(book(chapters: split)).loadBook()
        XCTAssertEqual(sections.canonicalChapters.map { $0.sections.count }, [2])
        let surah = "[\(chapter(items: [item(citations: citation(fromAyah: 1, wholeSurah: true), quranStatus: "RESOLVED")]))]"
        let whole = try await repository(book(chapters: surah)).loadBook()
        XCTAssertEqual(whole.allItems.first?.quranCitations.first?.recitesWholeSurah, true)
    }

    func testRejectsBrokenContent() async {
        let foreign = #"{"applied": ["X-1"], "open": []}"#
        let cases: [String: String] = [
            "no chapters": "[]",
            "empty chapter": "[\(chapter(items: []))]",
            "duplicate chapter id": "[\(chapter(items: [item()])), \(chapter(number: 2, items: [item(id: "i2")]))]",
            "chapter number gap": "[\(chapter(number: 2, items: [item()]))]",
            "duplicate item id": "[\(chapter(items: [item(), item(order: 2)]))]",
            "item in wrong chapter": "[\(chapter(items: [item(chapter: "other")]))]",
            "item order": "[\(chapter(items: [item(order: 2)]))]",
            "empty text": "[\(chapter(items: [item(text: "")]))]",
            "non-Arabic text": "[\(chapter(items: [item(text: "abc")]))]",
            "zero repeat count": "[\(chapter(items: [item(count: "0")]))]",
            "Tanzil status on Hisn text": "[\(chapter(items: [item(status: "QURAN_VERBATIM_TANZIL")]))]",
            "unknown review status": "[\(chapter(items: [item(status: "LICENSED")]))]",
            "book item number outside the book": "[\(chapter(items: [item(number: "2")]))]",
            "unmapped canonical book item": "[\(chapter(items: [item(number: "null", relation: "CHAPTER_INTRODUCTION")]))]",
            "direct item without a number": "[\(chapter(items: [item(number: "null")]))]",
            "numbered chapter introduction": "[\(chapter(items: [item(relation: "CHAPTER_INTRODUCTION")]))]",
            "evening variant outside the evening": "[\(chapter(items: [item(relation: "EVENING_VARIANT")]))]",
            "unknown relation": "[\(chapter(items: [item(relation: "MERGED")]))]",
            "presentation section on a single chapter": "[\(chapter(section: Self.morning, items: [item()]))]",
            "two sections without sections": "[\(chapter(items: [item()])), \(chapter(id: "c2", number: 2, items: [item(id: "i2", chapter: "c2")]))]",
            "canonical chapter missing": "[\(chapter(bookChapter: "null", items: [item()]))]",
            "whole-surah citation mid-surah": "[\(chapter(items: [item(citations: citation(fromAyah: 2, wholeSurah: true), quranStatus: "RESOLVED")]))]",
            "foreign correction id": "[\(chapter(items: [item(corrections: foreign)]))]",
        ]
        for (name, chapters) in cases {
            do {
                _ = try await repository(book(chapters: chapters)).loadBook()
                XCTFail("accepted: \(name)")
            } catch ContentError.invalidContent {
                continue
            } catch {
                XCTFail("\(name): got \(error)")
            }
        }
    }

    func testRejectsUnknownRightsStatus() async {
        let json = book(chapters: "[\(chapter(items: [item()]))]")
            .replacingOccurrences(of: "PENDING_PRE_RELEASE_REVIEW", with: "PUBLIC_DOMAIN")
        do {
            _ = try await repository(json).loadBook()
            XCTFail("accepted an unverified rights status")
        } catch let error as ContentError {
            guard case .invalidContent = error else { return XCTFail("got \(error)") }
        } catch {
            XCTFail("got \(error)")
        }
    }
}

// MARK: Helpers

private struct UpstreamChapter: Decodable {
    struct Entry: Decodable {
        let Text: String
        let Count: Int
        let Reference: String
    }

    let Adhkar: [Entry]
}

/// JSONDecoder loses object key order, so read the chapter titles in file order.
private func upstreamChapterOrder(_ data: Data) throws -> [String] {
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let text = String(decoding: data, as: UTF8.self)
    let offsets = (object ?? [:]).keys.map { title -> (String, Int) in
        let range = text.range(of: "\"\(title)\"")!
        return (title, text.utf8.distance(from: text.utf8.startIndex, to: range.lowerBound))
    }
    return offsets.sorted { $0.1 < $1.1 }.map(\.0)
}
