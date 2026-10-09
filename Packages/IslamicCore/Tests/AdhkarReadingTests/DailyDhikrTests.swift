import XCTest
@testable import AdhkarReading
import ContentKit
import IslamicCore

final class DailyDhikrTests: XCTestCase {
    /// A library with one dhikr per review state (and a long reviewed one), for the gate.
    private func mixedLibrary() -> AdhkarLibrary {
        func dhikr(_ id: String, _ order: Int, _ text: String, _ status: ContentReviewStatus) -> DevotionalItem {
            DevotionalItem(dhikr: DhikrItem(id: id, group: .morning, order: order, arabicText: text, source: "مصدر",
                                            repeatCount: 1, quranRef: nil, reviewStatus: status))
        }
        let items = [
            dhikr("t-required", 1, "نص يحتاج مراجعة", .reviewRequired),
            dhikr("t-quran", 2, "نص قرآني", .quranVerbatimTanzil),
            dhikr("t-reviewed-a", 3, "نص معتمد أول", .reviewed),
            dhikr("t-reviewed-long", 4, String(repeating: "ب", count: DailyDhikr.maximumLength + 1), .reviewed),
            dhikr("t-reviewed-b", 5, "نص معتمد ثان", .reviewed),
        ]
        let collection = DevotionalCollection(kind: .adhkar, ref: .dhikrGroup("morning"), title: "أذكار الصباح", items: items)
        let dua = DevotionalItem(dua: DuaItem(id: "t-dua", category: "quranic", order: 1, arabicText: "دعاء معتمد",
                                              source: "مصدر", quranRef: nil, reviewStatus: .reviewed))
        let duas = DevotionalCollection(kind: .dua, ref: .duaCategory("quranic"), title: "أدعية", items: [dua])
        return AdhkarLibrary(adhkar: [collection], duas: [duas])
    }

    func testOnlyReviewedAdhkarCanBeChosen() {
        let library = mixedLibrary()
        let pool = DailyDhikr.pool(in: library)
        XCTAssertEqual(pool.map(\.ref), [.dhikr("t-reviewed-a"), .dhikr("t-reviewed-b")],
                       "not CONTENT_REVIEW_REQUIRED, not Quranic text, not too long to show whole, not duas")
        var day = DayKey(year: 2026, month: 1, day: 1)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var chosen: Set<ContentRef> = []
        for _ in 0..<400 {
            if let item = DailyDhikr.item(on: day, in: library) {
                XCTAssertEqual(item.reviewStatus, .reviewed)
                chosen.insert(item.ref)
            }
            day = day.adding(days: 1, calendar: calendar)
        }
        XCTAssertEqual(chosen, [.dhikr("t-reviewed-a"), .dhikr("t-reviewed-b")], "each eligible one in turn")
    }

    func testTheSameDhikrAllDayAndTheNextOneTomorrow() {
        let library = mixedLibrary()
        let day = DayKey(year: 2026, month: 10, day: 9)
        XCTAssertEqual(DailyDhikr.item(on: day, in: library), DailyDhikr.item(on: day, in: library))
        XCTAssertNotEqual(DailyDhikr.item(on: day, in: library),
                          DailyDhikr.item(on: DayKey(year: 2026, month: 10, day: 10), in: library))
    }

    func testNothingIsChosenWhenNothingIsReviewed() {
        func dhikr(_ id: String, _ status: ContentReviewStatus) -> DevotionalItem {
            DevotionalItem(dhikr: DhikrItem(id: id, group: .evening, order: 1, arabicText: "نص", source: "مصدر",
                                            repeatCount: 3, quranRef: nil, reviewStatus: status))
        }
        let library = AdhkarLibrary(adhkar: [DevotionalCollection(kind: .adhkar, ref: .dhikrGroup("evening"), title: "x",
                                                                  items: [dhikr("a", .reviewRequired), dhikr("b", .quranVerbatimTanzil)])],
                                    duas: [])
        XCTAssertEqual(DailyDhikr.pool(in: library), [])
        XCTAssertNil(DailyDhikr.item(on: DayKey(year: 2026, month: 10, day: 9), in: library), "the widget shows its placeholder")
    }

    func testTheBundledContentIsGatedAndUnchanged() async throws {
        let library = try await AdhkarLibrary.load()
        // Whatever the review state of the bundle, only REVIEWED adhkar are eligible.
        let reviewed = library.adhkar.flatMap(\.items).filter {
            $0.reviewStatus == .reviewed && $0.text.count <= DailyDhikr.maximumLength
        }
        XCTAssertEqual(DailyDhikr.pool(in: library).map(\.ref), reviewed.map(\.ref).sorted())
        for item in library.collections.flatMap(\.items) where item.reviewStatus != .reviewed {
            XCTAssertFalse(DailyDhikr.isEligible(item), item.ref.string)
        }
        // The gate hides nothing from the readers: every bundled item is still in the library.
        XCTAssertEqual(library.adhkar.flatMap(\.items).count, 51)
        XCTAssertEqual(library.duas.flatMap(\.items).count, 17)
    }

    func testDayNumbersAreConsecutiveAcrossMonthsAndLeapYears() {
        XCTAssertEqual(DailyDhikr.dayNumber(DayKey(year: 2000, month: 1, day: 1)), 0)
        XCTAssertEqual(DailyDhikr.dayNumber(DayKey(year: 2000, month: 3, day: 1)), 60, "2000 is a leap year")
        XCTAssertEqual(DailyDhikr.dayNumber(DayKey(year: 2026, month: 10, day: 9)), 9778)
        XCTAssertEqual(DailyDhikr.dayNumber(DayKey(year: 2024, month: 3, day: 1)) - DailyDhikr.dayNumber(DayKey(year: 2024, month: 2, day: 28)), 2)
        XCTAssertEqual(DailyDhikr.dayNumber(DayKey(year: 2027, month: 1, day: 1)) - DailyDhikr.dayNumber(DayKey(year: 2026, month: 12, day: 31)), 1)
    }

    func testAllSavedPositionsAreListed() {
        let defaults = UserDefaults(suiteName: "DailyDhikrTests.\(UUID().uuidString)")!
        let store = UserDefaultsDevotionalPositionStore(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_791_537_600)
        store.save(DevotionalPosition(item: .dhikr("a"), repetitions: 1, savedAt: date), in: .dhikrGroup("morning"))
        store.save(DevotionalPosition(item: .dua("b"), repetitions: 0, savedAt: date), in: .duaCategory("quranic"))
        XCTAssertEqual(Set(store.all().keys), [.dhikrGroup("morning"), .duaCategory("quranic")])
        XCTAssertEqual(store.all()[.dhikrGroup("morning")]?.item, .dhikr("a"))
        store.clear(.dhikrGroup("morning"))
        XCTAssertEqual(Array(store.all().keys), [.duaCategory("quranic")])
    }
}

/// A widget, shortcut or link only opens a place: it never counts, completes or moves on.
@MainActor
final class OpeningFromALinkTests: XCTestCase {
    func testOpeningAtAnItemCountsNothingAndSavesNothingByItself() async throws {
        let library = try await AdhkarLibrary.load()
        let morning = try XCTUnwrap(library.collection(.dhikrGroup("morning")))
        let positions = InMemoryDevotionalPositionStore()
        let saved = DevotionalPosition(item: morning.items[1].ref, repetitions: 1, savedAt: Date(timeIntervalSince1970: 0))
        positions.save(saved, in: morning.ref)
        let counts = InMemoryItemCountStore()
        let today = DayKey(date: Date())
        counts.save([morning.items[1].ref.string: 1], in: morning.ref, on: today)
        let progress = InMemoryDailyProgressStore()

        let reader = try XCTUnwrap(DevotionalReaderController(collection: morning, start: morning.items[3].ref,
                                                              store: positions, dailyProgress: progress, counts: counts))
        XCTAssertEqual(reader.index, 3)
        XCTAssertEqual(reader.cursor.completedRepetitions, 0, "the opened item starts uncounted")
        XCTAssertEqual(positions.position(in: morning.ref), saved, "opening alone saves nothing")
        XCTAssertEqual(counts.counts(in: morning.ref, on: today), [morning.items[1].ref.string: 1], "no count added")
        XCTAssertTrue(progress.completed(on: today).isEmpty, "nothing marked done")
    }

    func testOpeningTheCollectionResumesWithoutCounting() async throws {
        let library = try await AdhkarLibrary.load()
        let evening = try XCTUnwrap(library.collection(.dhikrGroup("evening")))
        let positions = InMemoryDevotionalPositionStore()
        let saved = DevotionalPosition(item: evening.items[2].ref, repetitions: 0, savedAt: Date(timeIntervalSince1970: 0))
        positions.save(saved, in: evening.ref)
        let reader = try XCTUnwrap(DevotionalReaderController(collection: evening, store: positions))
        XCTAssertEqual(reader.index, 2, "the shortcut lands where reading stopped")
        XCTAssertEqual(reader.cursor.completedRepetitions, 0)
        XCTAssertEqual(positions.position(in: evening.ref), saved)
    }
}
