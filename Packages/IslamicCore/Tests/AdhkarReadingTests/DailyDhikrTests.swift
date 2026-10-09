import XCTest
@testable import AdhkarReading
import ContentKit
import IslamicCore

final class DailyDhikrTests: XCTestCase {
    func testTheSameDhikrAllDayAndANewOneTomorrow() async throws {
        let library = try await AdhkarLibrary.load()
        let day = DayKey(year: 2026, month: 10, day: 9)
        let today = try XCTUnwrap(DailyDhikr.item(on: day, in: library))
        XCTAssertEqual(DailyDhikr.item(on: day, in: library), today)
        let tomorrow = try XCTUnwrap(DailyDhikr.item(on: DayKey(year: 2026, month: 10, day: 10), in: library))
        XCTAssertNotEqual(tomorrow, today)
    }

    func testOnlyWholeBundledAdhkarAreShown() async throws {
        let library = try await AdhkarLibrary.load()
        let pool = DailyDhikr.pool(in: library)
        XCTAssertGreaterThanOrEqual(pool.count, 10)
        for item in pool {
            XCTAssertLessThanOrEqual(item.text.count, DailyDhikr.maximumLength)
            XCTAssertEqual(item.ref.kind, .adhkar)
            // The stored item, unchanged: the widget shows the library's own text and source.
            XCTAssertEqual(library.item(item.ref), item)
        }
        // A whole cycle shows every eligible dhikr once.
        var seen: Set<ContentRef> = []
        var day = DayKey(year: 2026, month: 1, day: 1)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        for _ in 0..<pool.count {
            seen.insert(try XCTUnwrap(DailyDhikr.item(on: day, in: library)).ref)
            day = day.adding(days: 1, calendar: calendar)
        }
        XCTAssertEqual(seen.count, pool.count)
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
