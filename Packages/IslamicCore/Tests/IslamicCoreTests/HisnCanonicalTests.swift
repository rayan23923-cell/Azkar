import XCTest
@testable import IslamicCore

/// Phase 2E: the canonical book structure (132 chapters / 267 items) and the corrections
/// applied from tools/content/hisn.corrections.json.
final class HisnCanonicalTests: XCTestCase {
    let repository = BundledHisnRepository()

    private func items() async throws -> [String: HisnItem] {
        Dictionary(uniqueKeysWithValues: try await repository.loadBook().allItems.map { ($0.id, $0) })
    }

    // MARK: Canonical structure

    func testCanonicalBookHas132ChaptersAnd267Items() async throws {
        let book = try await repository.loadBook()
        XCTAssertEqual(book.canonicalChapters.count, 132)
        XCTAssertEqual(book.canonicalChapters.map(\.bookChapterNumber), Array(1...132))
        XCTAssertEqual(book.bookItemNumbers, Set(1...267), "every book item 1...267 is carried")
        XCTAssertEqual(book.canonicalChapters.flatMap(\.bookItemNumbers), Array(1...267),
                       "each book item belongs to exactly one canonical chapter, in book order")
        XCTAssertEqual(book.provenance.corrections.canonicalBookChapters, 132)
        XCTAssertEqual(book.provenance.corrections.canonicalBookItems, 267)
    }

    func testPresentationHas133SectionsAnd302Items() async throws {
        let book = try await repository.loadBook()
        XCTAssertEqual(book.chapters.count, 133)
        XCTAssertEqual(book.itemCount, 302)
        XCTAssertEqual(book.provenance.corrections.presentationSections, 133)
        XCTAssertEqual(book.provenance.corrections.displayItems, 302)
    }

    func testChapter27IsShownAsMorningAndEvening() async throws {
        let book = try await repository.loadBook()
        let chapter27 = try XCTUnwrap(book.canonicalChapters.first { $0.bookChapterNumber == 27 })
        XCTAssertEqual(chapter27.sections.map(\.id), ["hisn-ch-027", "hisn-ch-028"])
        XCTAssertEqual(chapter27.sections.map(\.presentationSection), [.morning, .evening])
        XCTAssertEqual(chapter27.sections.map(\.presentationLabel), ["27A", "27B"])
        XCTAssertEqual(book.canonicalChapters.filter { $0.sections.count > 1 }.map(\.bookChapterNumber), [27],
                       "no other chapter is split, and there is no 133rd canonical chapter")
        for chapter in book.chapters where chapter.bookChapterNumber != 27 {
            XCTAssertNil(chapter.presentationSection, chapter.id)
        }
        let items = try await items()
        XCTAssertEqual(items["hisn-027-01"]?.bookItemRelation, .chapterIntroduction)
        XCTAssertEqual(items["hisn-028-01"]?.bookItemRelation, .chapterIntroduction)
        XCTAssertNil(items["hisn-027-01"]?.bookItemNumber)
        for id in ["hisn-028-04", "hisn-028-05", "hisn-028-07", "hisn-028-08", "hisn-028-16", "hisn-028-17"] {
            XCTAssertEqual(items[id]?.bookItemRelation, .eveningVariant, id)
        }
    }

    // MARK: Relations

    func testSplitBookItems() async throws {
        let items = try await items()
        let groups: [Int: [String]] = [
            106: ["hisn-029-08", "hisn-029-09", "hisn-029-10"],
            114: ["hisn-032-01", "hisn-032-02", "hisn-032-03", "hisn-032-04"],
            133: ["hisn-041-01", "hisn-041-02"],
        ]
        for (number, ids) in groups {
            XCTAssertEqual(items.values.filter { $0.bookItemNumber == number }.map(\.id).sorted(), ids, "book item \(number)")
            for id in ids {
                XCTAssertEqual(items[id]?.bookItemRelation, .splitPart, id)
            }
        }
    }

    func testEveryItemHasAConsistentRelation() async throws {
        for chapter in try await repository.loadChapters() {
            for item in chapter.items {
                switch item.bookItemRelation {
                case .direct, .splitPart: XCTAssertNotNil(item.bookItemNumber, item.id)
                case .chapterIntroduction: XCTAssertNil(item.bookItemNumber, item.id)
                case .eveningVariant: XCTAssertEqual(chapter.presentationSection, .evening, item.id)
                }
            }
        }
        let unnumbered = try await repository.loadBook().allItems.filter { $0.bookItemNumber == nil }.map(\.id)
        XCTAssertEqual(unnumbered, ["hisn-027-01", "hisn-028-01", "hisn-028-05"],
                       "only the two introductions and the pending evening variant of 78")
    }

    // MARK: Book item numbers

    func testP0BookItemNumberCorrections() async throws {
        let items = try await items()
        let expected = ["hisn-001-03": 2, "hisn-004-02": 7, "hisn-010-02": 16, "hisn-027-20": 93, "hisn-028-16": 89,
                        "hisn-029-14": 110, "hisn-041-02": 133, "hisn-046-02": 142, "hisn-133-01": 267]
        for (id, number) in expected {
            let item = try XCTUnwrap(items[id], id)
            XCTAssertEqual(item.bookItemNumber, number, id)
            XCTAssertFalse(item.corrections.applied.isEmpty, "\(id) names the manifest entry that set it")
        }
        XCTAssertNil(items["hisn-028-05"]?.bookItemNumber, "78 is proposed only, not applied")
        XCTAssertFalse(items["hisn-028-05"]?.corrections.open.isEmpty ?? true)
    }

    func testSwappedPairsKeepDisplayOrderAndGetBookOrder() async throws {
        let chapters = Dictionary(uniqueKeysWithValues: try await repository.loadChapters().map { ($0.id, $0) })
        let pairs: [(String, [String], [String])] = [
            ("hisn-ch-001", ["hisn-001-02", "hisn-001-03"], ["hisn-001-03", "hisn-001-02"]),
            ("hisn-ch-004", ["hisn-004-01", "hisn-004-02"], ["hisn-004-02", "hisn-004-01"]),
            ("hisn-ch-010", ["hisn-010-01", "hisn-010-02"], ["hisn-010-02", "hisn-010-01"]),
        ]
        for (chapterId, display, book) in pairs {
            let chapter = try XCTUnwrap(chapters[chapterId])
            let ids = Set(display)
            XCTAssertEqual(chapter.items.map(\.id).filter(ids.contains), display, "upstream order is kept")
            XCTAssertEqual(chapter.itemsInBookOrder.map(\.id).filter(ids.contains), book, "book order")
        }
        for chapter in chapters.values {
            let inverted = zip(chapter.items, chapter.itemsInBookOrder).contains { $0.id != $1.id }
            XCTAssertEqual(inverted, ["hisn-ch-001", "hisn-ch-004", "hisn-ch-010"].contains(chapter.id), chapter.id)
        }
    }

    // MARK: Repetition

    func testAcceptedRepetitionCorrections() async throws {
        let items = try await items()
        XCTAssertEqual(items["hisn-027-20"]?.repetition.count, 100)
        XCTAssertEqual(items["hisn-032-03"]?.repetition.count, 1)
        XCTAssertEqual(items["hisn-032-04"]?.repetition.count, 1)
    }

    func testRepetitionsKeptNil() async throws {
        let items = try await items()
        for id in ["hisn-016-05", "hisn-025-01", "hisn-025-02", "hisn-025-04", "hisn-029-06",
                   "hisn-119-01", "hisn-125-01", "hisn-131-02"] {
            XCTAssertNil(items[id]?.repetition.count, id)
        }
        // Phase 2F declined the medium-confidence proposal of 1: «مائة مرة» is narrated, not a repeat count.
        for id in ["hisn-130-02", "hisn-130-06"] {
            XCTAssertNil(items[id]?.repetition.count, id)
            XCTAssertEqual(items[id]?.editorialReviews.map(\.decision), [.keepNil], id)
        }
    }

    // MARK: Quran

    func testQuranCitationCorrections() async throws {
        let items = try await items()
        XCTAssertEqual(items["hisn-001-04"]?.quranStatus, .resolved)
        XCTAssertEqual(items["hisn-001-04"]?.quranCitations,
                       [HisnQuranCitation(reference: QuranReference(surah: 3, fromAyah: 190, toAyah: 200),
                                          coversWholeVerses: true, match: .exact)])
        XCTAssertEqual(items["hisn-029-03"]?.quranStatus, .resolved)
        XCTAssertEqual(items["hisn-029-03"]?.quranCitations,
                       [HisnQuranCitation(reference: QuranReference(surah: 2, fromAyah: 285, toAyah: 286),
                                          coversWholeVerses: true, match: .exact)])
        let surahs = try XCTUnwrap(items["hisn-029-14"])
        XCTAssertEqual(surahs.quranStatus, .resolved)
        XCTAssertEqual(surahs.quranCitations, [
            HisnQuranCitation(reference: QuranReference(surah: 32, fromAyah: 1, toAyah: 2),
                              coversWholeVerses: false, match: .exact, recitesWholeSurah: true),
            HisnQuranCitation(reference: QuranReference(surah: 67, ayah: 1),
                              coversWholeVerses: false, match: .exact, recitesWholeSurah: true),
        ])
        XCTAssertTrue(surahs.arabicText.hasPrefix("يَقْرَأُ {ألم * تَنْزِيل ...}"), "no surah text was added")
    }

    // MARK: Review state

    func testCorrectionsAreNotEditorialReview() async throws {
        let book = try await repository.loadBook()
        for item in book.allItems {
            XCTAssertEqual(item.reviewStatus, .reviewRequired, item.id)
            XCTAssertEqual(item.repetition.reviewStatus, .reviewRequired, item.id)
        }
        XCTAssertEqual(book.attribution.rightsStatus, .pendingPreReleaseReview)
        XCTAssertEqual(ContentRightsStatus.allCases, [.pendingPreReleaseReview])
        let corrections = book.provenance.corrections
        XCTAssertEqual(corrections.manifest, "tools/content/hisn.corrections.json")
        XCTAssertEqual(corrections.total,
                       corrections.accepted + corrections.observationOnly + corrections.pendingDecision + corrections.rejected)
        XCTAssertGreaterThan(corrections.p0Pending, 0, "text discrepancies stay open for editorial review")
    }

    func testObservedDiscrepanciesStayOpen() async throws {
        let items = try await items()
        for id in ["hisn-016-01", "hisn-016-06", "hisn-017-04", "hisn-025-02", "hisn-029-15", "hisn-037-02",
                   "hisn-043-01", "hisn-052-02", "hisn-112-01", "hisn-001-03", "hisn-133-01", "hisn-029-14"] {
            XCTAssertFalse(items[id]?.corrections.open.isEmpty ?? true, id)
        }
    }
}
