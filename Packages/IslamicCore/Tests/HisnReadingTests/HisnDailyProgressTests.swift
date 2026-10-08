import XCTest
import IslamicCore
import ContentKit
@testable import HisnReading

/// Phase 3G: finishing a chapter is recorded for the day; nothing else is.
@MainActor
final class HisnDailyProgressTests: XCTestCase {
    private static var library: HisnLibrary?

    private func chapter(_ id: String) async throws -> HisnChapter {
        if Self.library == nil { Self.library = HisnLibrary(book: try await BundledHisnRepository().loadBook()) }
        return try XCTUnwrap(Self.library?.chapter(id: id), id)
    }

    private let day = DayKey(year: 2026, month: 10, day: 8)
    private var fixedNow: Date {
        var calendar = Calendar.current
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 9)) ?? Date()
    }

    func testCountingToTheEndRecordsTheChapterOnce() async throws {
        let chapter = try await chapter("hisn-ch-002")
        let daily = InMemoryDailyProgressStore()
        let now = fixedNow
        let controller = HisnReaderController(reader: try XCTUnwrap(HisnReader(chapter: chapter)),
                                              store: InMemoryHisnReadingPositionStore(), dailyProgress: daily,
                                              now: { now })
        XCTAssertTrue(daily.completed(on: day).isEmpty, "opening records nothing")
        while !controller.reader.isCompleted { controller.recite() }
        XCTAssertEqual(daily.completed(on: day), [.hisnSection("hisn-ch-002")])
        controller.restart()
        while !controller.reader.isCompleted { controller.recite() }
        XCTAssertEqual(daily.completed(on: day).count, 1)
    }

    func testCountedTapsAndNavigationRecordNothingUntilTheEnd() async throws {
        let chapter = try await chapter("hisn-ch-027")
        let daily = InMemoryDailyProgressStore()
        let now = fixedNow
        let controller = HisnReaderController(reader: try XCTUnwrap(HisnReader(chapter: chapter)),
                                              store: InMemoryHisnReadingPositionStore(), dailyProgress: daily,
                                              now: { now })
        controller.recite()
        controller.next()
        controller.previous()
        XCTAssertTrue(daily.days.isEmpty)
        // «إنهاء الباب» on the last item also completes the chapter.
        for _ in 0..<chapter.itemCount { controller.next() }
        XCTAssertTrue(controller.reader.isCompleted)
        XCTAssertEqual(daily.completed(on: day), [.hisnSection("hisn-ch-027")])
    }

    func testWithoutAStoreNothingChanges() async throws {
        let chapter = try await chapter("hisn-ch-002")
        let controller = HisnReaderController(reader: try XCTUnwrap(HisnReader(chapter: chapter)),
                                              store: InMemoryHisnReadingPositionStore())
        while !controller.reader.isCompleted { controller.recite() }
        XCTAssertTrue(controller.reader.isCompleted)
    }

    func testIndexAccessibilitySaysCompletedToday() async throws {
        _ = try await chapter("hisn-ch-001")
        let entry = try XCTUnwrap(Self.library?.sections.first)
        XCTAssertEqual(HisnAccessibility.sectionValue(entry, isCurrent: false, completedToday: true),
                       "أُتمّ اليوم، عدد الأذكار \(entry.itemCount)")
        XCTAssertEqual(HisnAccessibility.sectionValue(entry, isCurrent: true),
                       "موضع القراءة الحالي، عدد الأذكار \(entry.itemCount)")
    }
}
