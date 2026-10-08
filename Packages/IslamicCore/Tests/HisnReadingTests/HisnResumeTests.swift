import XCTest
import IslamicCore
@testable import HisnReading

/// Phase 3A: same-day resume (chapter, item, repetitions) through the position store.
final class HisnResumeTests: XCTestCase {
    private static var cached: HisnLibrary?
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        return calendar
    }()

    private func library() async throws -> HisnLibrary {
        if let cached = Self.cached { return cached }
        let library = HisnLibrary(book: try await BundledHisnRepository().loadBook())
        Self.cached = library
        return library
    }

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func reader(_ chapterId: String, at index: Int = 0) async throws -> HisnReader {
        let chapter = try XCTUnwrap(try await library().chapter(id: chapterId))
        return try XCTUnwrap(HisnReader(chapter: chapter, itemIndex: index))
    }

    func testLeaveAndReturnRestoresItemAndRepetitions() async throws {
        let library = try await library()
        let store = InMemoryHisnReadingPositionStore()
        var reader = try await reader("hisn-ch-017")
        XCTAssertEqual(reader.currentItem.repetition.count, 3)
        reader.recite()
        reader.recite()
        HisnResume.record(reader, in: store, now: date(8, 7))

        let position = try XCTUnwrap(HisnResume.position(in: store, library: library, now: date(8, 21), calendar: calendar))
        XCTAssertEqual(position.chapterId, "hisn-ch-017")
        XCTAssertEqual(position.itemId, "hisn-017-01")
        let restored = try XCTUnwrap(HisnResume.reader(for: position, in: library))
        XCTAssertEqual(restored.currentItem.id, "hisn-017-01")
        XCTAssertEqual(restored.completedRepetitions, 2)
        XCTAssertEqual(restored.repetition, .counted(completed: 2, total: 3))
        var next = restored
        XCTAssertEqual(next.recite(), .movedToNext, "one more recitation finishes the item")
    }

    func testItemRestoreAfterNavigation() async throws {
        let library = try await library()
        let store = InMemoryHisnReadingPositionStore()
        var reader = try await reader("hisn-ch-027")
        reader.next()
        reader.next()
        reader.next()
        HisnResume.record(reader, in: store, now: date(8, 6))
        let restored = try XCTUnwrap(HisnResume.position(in: store, library: library, now: date(8, 6), calendar: calendar)
            .flatMap { HisnResume.reader(for: $0, in: library) })
        XCTAssertEqual(restored.currentItem.id, reader.currentItem.id)
        XCTAssertEqual(restored.itemIndex, 3)
        XCTAssertEqual(restored.completedRepetitions, 0)
    }

    func testOnlyTheSameDayResumes() async throws {
        let library = try await library()
        let store = InMemoryHisnReadingPositionStore()
        HisnResume.record(try await reader("hisn-ch-001", at: 1), in: store, now: date(8, 23))
        XCTAssertNotNil(HisnResume.position(in: store, library: library, now: date(8, 23), calendar: calendar))
        XCTAssertNil(HisnResume.position(in: store, library: library, now: date(9, 0), calendar: calendar),
                     "a new day starts from the index")
        XCTAssertNil(HisnResume.position(in: store, library: library, now: date(7, 23), calendar: calendar))
    }

    func testCompletingTheChapterClearsThePosition() async throws {
        let store = InMemoryHisnReadingPositionStore()
        var reader = try await reader("hisn-ch-001")
        HisnResume.record(reader, in: store, now: date(8, 7))
        XCTAssertNotNil(store.position)
        while !reader.isCompleted { reader.next() }
        HisnResume.record(reader, in: store, now: date(8, 7))
        XCTAssertNil(store.position)
    }

    func testBoundaries() async throws {
        let library = try await library()
        let chapter = try XCTUnwrap(library.chapter(id: "hisn-ch-017"))
        func position(_ chapterId: String, _ itemId: String, _ index: Int, _ repetitions: Int) -> HisnReadingPosition {
            HisnReadingPosition(chapterId: chapterId, itemId: itemId, itemIndex: index,
                                completedRepetitions: repetitions, savedAt: date(8, 7))
        }
        // Repetitions at or beyond the count, or negative, start the item again.
        XCTAssertEqual(HisnResume.reader(for: position(chapter.id, "hisn-017-01", 0, 3), in: library)?.completedRepetitions, 0)
        XCTAssertEqual(HisnResume.reader(for: position(chapter.id, "hisn-017-01", 0, 99), in: library)?.completedRepetitions, 0)
        XCTAssertEqual(HisnResume.reader(for: position(chapter.id, "hisn-017-01", 0, -2), in: library)?.completedRepetitions, 0)
        // The item is found by id when the saved index is stale.
        let last = chapter.items[chapter.items.count - 1]
        XCTAssertEqual(HisnResume.reader(for: position(chapter.id, last.id, 0, 0), in: library)?.currentItem.id, last.id)
        XCTAssertEqual(HisnResume.reader(for: position(chapter.id, last.id, 99, 0), in: library)?.currentItem.id, last.id)
        // Unknown chapter or item: nothing to resume.
        XCTAssertNil(HisnResume.reader(for: position("hisn-ch-999", "hisn-017-01", 0, 0), in: library))
        XCTAssertNil(HisnResume.reader(for: position(chapter.id, "hisn-001-01", 0, 0), in: library))
        let store = InMemoryHisnReadingPositionStore(position(chapter.id, "missing", 0, 0))
        XCTAssertNil(HisnResume.position(in: store, library: library, now: date(8, 8), calendar: calendar))
    }

    func testUserDefaultsStoreRoundTrip() throws {
        let suite = "HisnResumeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsHisnReadingPositionStore(defaults: defaults)
        XCTAssertNil(store.load())
        let saved = HisnReadingPosition(chapterId: "hisn-ch-017", itemId: "hisn-017-01", itemIndex: 0,
                                        completedRepetitions: 2, savedAt: date(8, 7))
        store.save(saved)
        XCTAssertEqual(UserDefaultsHisnReadingPositionStore(defaults: defaults).load(), saved)
        store.clear()
        XCTAssertNil(store.load())
        defaults.set(Data("not json".utf8), forKey: UserDefaultsHisnReadingPositionStore.defaultKey)
        XCTAssertNil(store.load(), "unreadable data is no position")
    }
}
