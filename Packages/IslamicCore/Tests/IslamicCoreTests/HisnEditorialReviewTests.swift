import XCTest
@testable import IslamicCore

/// Phase 2F: the editorial decisions on the fifteen P0 findings, as decoded by IslamicCore.
final class HisnEditorialReviewTests: XCTestCase {
    let repository = BundledHisnRepository()

    private static let decisions: [String: HisnEditorialReview.Decision] = [
        "hisn-016-01": .deferred, "hisn-016-06": .deferred, "hisn-017-04": .deferred, "hisn-025-02": .keepSource,
        "hisn-029-15": .deferred, "hisn-037-02": .deferred, "hisn-043-01": .keepSource, "hisn-052-02": .deferred,
        "hisn-112-01": .deferred, "hisn-001-03": .keepMetadata, "hisn-133-01": .keepMetadata,
        "hisn-029-14": .keepMetadata, "hisn-130-02": .keepNil, "hisn-130-06": .keepNil, "hisn-029-06": .keepNil,
    ]

    func testEveryP0FindingHasOneRecordedDecision() async throws {
        let items = try await repository.loadBook().allItems
        let reviewed = items.filter { !$0.editorialReviews.isEmpty }
        XCTAssertEqual(Set(reviewed.map(\.id)), Set(Self.decisions.keys))
        for item in reviewed {
            XCTAssertEqual(item.editorialReviews.map(\.decision), [Self.decisions[item.id]], item.id)
            XCTAssertEqual(item.editorialReviews.map(\.changesApplied), [false], item.id)
        }
    }

    func testDecisionsAreNotIndependentReview() async throws {
        let book = try await repository.loadBook()
        let summary = book.provenance.editorialReview
        XCTAssertEqual(summary.total, 15)
        XCTAssertEqual(summary.decisions, ["ACCEPT_CORRECTION": 0, "KEEP_SOURCE": 2, "KEEP_NIL": 3,
                                           "KEEP_METADATA": 3, "DEFER": 7])
        XCTAssertEqual(summary.changesApplied, 0)
        XCTAssertEqual(summary.independentlyReviewed, 0)
        XCTAssertFalse(summary.editorialReviewComplete)
        XCTAssertTrue(book.allItems.allSatisfy { $0.reviewStatus == .reviewRequired })
        XCTAssertEqual(book.attribution.rightsStatus, .pendingPreReleaseReview)
    }

    func testNonRecitationTextMarksVerbatimSpans() async throws {
        let items = Dictionary(uniqueKeysWithValues: try await repository.loadBook().allItems.map { ($0.id, $0) })
        XCTAssertEqual(items["hisn-001-03"]?.nonRecitationText.map(\.role), [.narration])
        XCTAssertEqual(items["hisn-133-01"]?.nonRecitationText.map(\.role), [.closing])
        XCTAssertEqual(items["hisn-029-14"]?.nonRecitationText.map(\.role), [.label, .label])
        XCTAssertEqual(items["hisn-001-03"]?.nonRecitationText.first?.text,
                       "أَوْ دَعَا اسْتُجِيبَ لَهُ فَإِنْ تَوَضَّأَ وَصَلَّى قُبِلَتْ صَلَاتَهُ")
        for item in items.values {
            for span in item.nonRecitationText {
                XCTAssertTrue(item.arabicText.contains(span.text), item.id)
            }
        }
        XCTAssertEqual(items.values.filter { !$0.nonRecitationText.isEmpty }.count, 3)
    }

    func testDeferredTextIsTheSourceText() async throws {
        let items = Dictionary(uniqueKeysWithValues: try await repository.loadBook().allItems.map { ($0.id, $0) })
        XCTAssertTrue(items["hisn-037-02"]?.arabicText.contains("بِكَ أَجُولُ") ?? false, "source wording kept")
        XCTAssertTrue(items["hisn-112-01"]?.arabicText.contains("مِنْهُمْ") ?? false, "source wording kept")
        XCTAssertFalse(items["hisn-016-06"]?.arabicText.contains("أَعْلَمُ بِهِ مِنِّي") ?? true, "nothing inserted")
        XCTAssertNil(items["hisn-025-02"]?.repetition.count, "[ثلاثاً] is not a whole-item count")
        XCTAssertEqual(items["hisn-043-01"]?.repetition.count, 3)
    }
}
