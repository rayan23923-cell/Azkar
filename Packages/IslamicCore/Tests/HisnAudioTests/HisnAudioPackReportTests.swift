import XCTest
import IslamicCore
@testable import HisnReading

/// Phase 3H: the release report over the audio pack.
final class HisnAudioPackReportTests: XCTestCase {
    private func book() async throws -> HisnBook {
        try await BundledHisnRepository().loadBook()
    }

    private func asset(_ item: String, usage: HisnAudioAsset.Usage = .production, reciter: String? = "Reciter",
                       duration: Int? = 12_000) -> HisnAudioAsset {
        HisnAudioAsset(id: "a-\(item)", itemId: item, usage: usage, resourceName: "\(item).m4a", format: .m4a,
                       durationMilliseconds: duration, byteCount: 10, sha256: String(repeating: "a", count: 64),
                       source: HisnAudioSource(sourceName: "Source", sourceURL: nil, reciter: reciter,
                                               narrationStyle: nil, retrievalDate: nil, licenseOrRightsStatement: nil,
                                               rightsStatus: .pendingPreReleaseReview))
    }

    /// The bundled pack today: empty and pending, so it cannot ship and no item has a recording.
    func testBundledPackIsPendingAndEmpty() async throws {
        let book = try await book()
        let repository = BundledHisnAudioRepository(knownItemIds: Set(book.allItems.map(\.id)))
        let manifest = try await repository.manifest()
        let report = HisnAudioPackReport(manifest: manifest, book: book)
        XCTAssertEqual(report.packStatus, "PENDING_RIGHTS_AND_ASSETS")
        XCTAssertEqual(report.assetCount, 0)
        XCTAssertTrue(report.coveredItemIds.isEmpty)
        XCTAssertEqual(report.missingItemIds.count, 302)
        XCTAssertEqual(report.missingItemIds, book.allItems.map(\.id))
        XCTAssertFalse(report.isReleaseReady)
        XCTAssertEqual(report.releaseBlockers, ["packStatus is PENDING_RIGHTS_AND_ASSETS, not READY",
                                                "the pack has no recordings"])
        XCTAssertEqual(report.coverage, 0)
    }

    /// Pending rights block every recording, even in a pack marked ready.
    func testPendingRightsAlwaysBlock() async throws {
        let book = try await book()
        let manifest = HisnAudioManifest(formatVersion: 1, packStatus: "READY",
                                         assets: [asset("hisn-001-01"), asset("hisn-001-02", usage: .testOnly, reciter: nil, duration: nil)])
        let report = HisnAudioPackReport(manifest: manifest, book: book)
        XCTAssertEqual(report.coveredItemIds, ["hisn-001-01", "hisn-001-02"])
        XCTAssertEqual(report.missingItemIds.count, 300)
        XCTAssertEqual(report.releaseBlockers, [
            "a-hisn-001-01 rights are PENDING_PRE_RELEASE_REVIEW",
            "a-hisn-001-02 is TEST_ONLY",
            "a-hisn-001-02 rights are PENDING_PRE_RELEASE_REVIEW",
            "a-hisn-001-02 has no reciter",
            "a-hisn-001-02 has no measured duration",
        ])
        XCTAssertEqual(report.coverage, 2.0 / 302.0, accuracy: 1e-9)
    }
}
