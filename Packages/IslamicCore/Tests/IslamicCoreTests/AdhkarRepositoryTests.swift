import XCTest
@testable import IslamicCore

final class DhikrRepositoryTests: XCTestCase {
    let repository = BundledDhikrRepository()
    let quran = BundledQuranRepository()

    func testHasTheFiveGroupsInOrder() async throws {
        let groups = try await repository.loadGroups()
        XCTAssertEqual(groups.map(\.id), [.morning, .evening, .afterPrayer, .sleep, .general])
        XCTAssertEqual(groups.first?.titleArabic, "أذكار الصباح")
        for group in groups { assertArabicIntegrity(group.titleArabic, group.id.rawValue) }
    }

    func testEveryGroupHasOrderedValidItems() async throws {
        var ids = Set<String>()
        for group in try await repository.loadGroups() {
            let items = try await repository.loadItems(group: group.id)
            XCTAssertFalse(items.isEmpty, group.id.rawValue)
            XCTAssertEqual(items.map(\.order), Array(1...items.count))
            for item in items {
                XCTAssertEqual(item.group, group.id)
                XCTAssertGreaterThanOrEqual(item.repeatCount, 1, item.id)
                XCTAssertFalse(item.source.isEmpty, item.id)
                assertArabicIntegrity(item.arabicText, item.id)
                XCTAssertTrue(ids.insert(item.id).inserted, "duplicate \(item.id)")
            }
        }
    }

    func testQuranicAdhkarAreVerbatimAndOthersNeedReview() async throws {
        for group in try await repository.loadGroups() {
            for item in try await repository.loadItems(group: group.id) {
                if let ref = item.quranRef {
                    XCTAssertEqual(item.reviewStatus, .quranVerbatimTanzil, item.id)
                    let verses = try await quran.loadVerses(ref)
                    XCTAssertEqual(item.arabicText, verses.map(\.arabicText).joined(separator: " "), item.id)
                } else {
                    XCTAssertEqual(item.reviewStatus, .reviewRequired, item.id)
                }
            }
        }
    }

    func testKnownRepeatCounts() async throws {
        let afterPrayer = try await repository.loadItems(group: .afterPrayer)
        XCTAssertEqual(afterPrayer.first?.repeatCount, 3)
        let sleep = try await repository.loadItems(group: .sleep)
        XCTAssertEqual(sleep.last?.repeatCount, 34)
    }

    func testLoadByIdAndInvalidIds() async throws {
        let item = try await repository.loadItem(id: "dhikr-morning-001")
        XCTAssertEqual(item.group, .morning)
        XCTAssertEqual(item.quranRef, QuranReference(surah: 2, ayah: 255))
        await assertNotFound { _ = try await self.repository.loadItem(id: "missing") }
        await assertNotFound { _ = try await self.repository.loadItems(group: "unknown") }
    }
}

final class DuaRepositoryTests: XCTestCase {
    let repository = BundledDuaRepository()
    let quran = BundledQuranRepository()

    func testHasQuranicAndPropheticCategories() async throws {
        let categories = try await repository.loadCategories()
        XCTAssertEqual(categories.map(\.id), [.quranic, .prophetic])
    }

    func testQuranicDuasAreWholeVersesFromTanzil() async throws {
        let items = try await repository.loadItems(category: .quranic)
        XCTAssertFalse(items.isEmpty)
        for item in items {
            let ref = try XCTUnwrap(item.quranRef, item.id)
            XCTAssertEqual(item.reviewStatus, .quranVerbatimTanzil)
            let verses = try await quran.loadVerses(ref)
            XCTAssertEqual(item.arabicText, verses.map(\.arabicText).joined(separator: " "), item.id)
            XCTAssertTrue(item.source.hasPrefix("سورة "), item.id)
        }
    }

    func testPropheticDuasHaveSourcesAndNeedReview() async throws {
        let items = try await repository.loadItems(category: .prophetic)
        XCTAssertFalse(items.isEmpty)
        XCTAssertEqual(items.map(\.order), Array(1...items.count))
        for item in items {
            XCTAssertNil(item.quranRef)
            XCTAssertEqual(item.reviewStatus, .reviewRequired)
            XCTAssertFalse(item.source.isEmpty)
            assertArabicIntegrity(item.arabicText, item.id)
        }
    }

    func testLoadByIdAndInvalidIds() async throws {
        let item = try await repository.loadItem(id: "dua-prophetic-001")
        XCTAssertEqual(item.category, .prophetic)
        await assertNotFound { _ = try await self.repository.loadItem(id: "dua-x") }
        await assertNotFound { _ = try await self.repository.loadItems(category: "unknown") }
    }
}
