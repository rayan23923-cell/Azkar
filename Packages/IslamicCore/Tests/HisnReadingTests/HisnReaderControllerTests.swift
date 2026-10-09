import XCTest
import IslamicCore
import ContentKit
@testable import HisnReading

/// Phase 3D: when the reader controller saves the cursor, and the completed-item cue. No audio.
@MainActor
final class HisnReaderControllerTests: XCTestCase {
    private static var cached: HisnLibrary?

    private func library() async throws -> HisnLibrary {
        if let cached = Self.cached { return cached }
        let library = HisnLibrary(book: try await BundledHisnRepository().loadBook())
        Self.cached = library
        return library
    }

    private func makeController(_ chapterId: String, at index: Int = 0,
                                store: InMemoryHisnReadingPositionStore) async throws -> HisnReaderController {
        let loaded = try await library()
        let chapter = try XCTUnwrap(loaded.chapter(id: chapterId))
        let reader = try XCTUnwrap(HisnReader(chapter: chapter, itemIndex: index))
        return HisnReaderController(reader: reader, store: store)
    }

    func testOpeningAndMovingSaveTheCursor() async throws {
        let store = InMemoryHisnReadingPositionStore()
        let controller = try await makeController("hisn-ch-001", at: 1, store: store)
        XCTAssertEqual(store.position?.itemId, "hisn-001-02", "open item 2 and leave → item 2")
        controller.next()
        XCTAssertEqual(store.position?.itemId, "hisn-001-03", "move to item 3 and leave → item 3")
        controller.previous()
        XCTAssertEqual(store.position?.itemId, "hisn-001-02")
        controller.close()
        XCTAssertEqual(store.position?.itemId, "hisn-001-02", "closing keeps the cursor")

        let other = try await makeController("hisn-ch-017", store: store)
        XCTAssertEqual(store.position?.chapterId, "hisn-ch-017", "another chapter → its cursor")
        other.recite()
        XCTAssertEqual(store.position?.completedRepetitions, 1, "counting is saved")
    }

    func testPersistSavesWithoutChangingTheReader() async throws {
        let store = InMemoryHisnReadingPositionStore()
        let controller = try await makeController("hisn-ch-017", store: store)
        controller.recite()
        let before = controller.reader
        store.clear()
        controller.persist()
        XCTAssertEqual(store.position?.itemId, "hisn-017-01")
        XCTAssertEqual(store.position?.completedRepetitions, 1)
        XCTAssertEqual(controller.reader, before)
    }

    func testCompletedChapterLeavesNothingToResume() async throws {
        let store = InMemoryHisnReadingPositionStore()
        let controller = try await makeController("hisn-ch-001", store: store)
        for _ in 0..<100 where !controller.reader.isCompleted { controller.next() }
        XCTAssertTrue(controller.reader.isCompleted)
        XCTAssertNil(store.position)
        controller.close()
        XCTAssertNil(store.position)
    }

    func testFinishingAnItemSaysSoAndDoesNotSkipAhead() async throws {
        let store = InMemoryHisnReadingPositionStore()
        let controller = try await makeController("hisn-ch-017", store: store)
        XCTAssertEqual(controller.reader.repetition, .counted(completed: 0, total: 3))
        controller.recite()
        XCTAssertEqual(controller.reader.repetition, .counted(completed: 1, total: 3))
        XCTAssertNil(controller.finishedItemNumber)
        controller.recite()
        controller.recite()
        XCTAssertEqual(controller.finishedItemNumber, 1, "item 1's count is done")
        XCTAssertEqual(controller.reader.itemNumber, 2, "the session's rule: on to the next item, one step only")
        controller.previous()
        XCTAssertNil(controller.finishedItemNumber)
        XCTAssertEqual(controller.reader.itemNumber, 1)
        XCTAssertEqual(controller.reader.repetition, .counted(completed: 3, total: 3),
                       "going back to the finished item shows its count, not zero")
        let recitations = controller.recitations
        controller.recite()
        XCTAssertEqual(controller.reader.itemNumber, 2, "a finished item is not counted again; on to the next")
        XCTAssertEqual(controller.recitations, recitations + 1)
    }

    /// The owner's report (2026-10-09): finish an item, go on, come back: the count was zero
    /// on the screen and in PiP. Each item keeps its count while the chapter is open; «إعادة»
    /// clears them all.
    func testEveryItemKeepsItsCountUntilRestart() async throws {
        let store = InMemoryHisnReadingPositionStore()
        let controller = try await makeController("hisn-ch-017", store: store)
        controller.recite(); controller.recite(); controller.recite()
        XCTAssertEqual(controller.reader.itemNumber, 2)
        controller.next()
        controller.previous()
        controller.previous()
        XCTAssertEqual(controller.reader.itemNumber, 1)
        XCTAssertEqual(controller.reader.repetition, .counted(completed: 3, total: 3))
        controller.next()
        XCTAssertEqual(controller.reader.itemNumber, 2)
        controller.restart()
        XCTAssertEqual(controller.reader.repetition, .counted(completed: 0, total: 3), "«إعادة» clears every count")
    }

    func testRestartClearsTheCue() async throws {
        let store = InMemoryHisnReadingPositionStore()
        let controller = try await makeController("hisn-ch-001", store: store)
        controller.recite()
        XCTAssertEqual(controller.finishedItemNumber, 1)
        controller.restart()
        XCTAssertNil(controller.finishedItemNumber)
        XCTAssertEqual(store.position?.itemIndex, 0)
    }

    /// Counts outlive the screen and the app the same day: a new controller (the app opened
    /// again) shows the finished item's count when gone back to; the next day starts at zero.
    func testCountsComeBackAfterRelaunchTheSameDay() async throws {
        let loaded = try await library()
        let chapter = try XCTUnwrap(loaded.chapter(id: "hisn-ch-017"))
        let store = InMemoryHisnReadingPositionStore()
        let counts = InMemoryItemCountStore()
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let first = HisnReaderController(reader: try XCTUnwrap(HisnReader(chapter: chapter)), store: store,
                                         counts: counts, now: { day })
        first.recite(); first.recite(); first.recite()
        XCTAssertEqual(first.reader.itemNumber, 2)
        first.close()

        let position = try XCTUnwrap(store.position)
        let reopen = { (date: Date) in
            HisnReaderController(reader: try XCTUnwrap(HisnReader(chapter: chapter, itemIndex: position.itemIndex,
                                                                  completedRepetitions: position.completedRepetitions)),
                                 store: store, counts: counts, now: { date })
        }
        let second = try reopen(day.addingTimeInterval(3600))
        XCTAssertEqual(second.reader.itemNumber, 2)
        second.previous()
        XCTAssertEqual(second.reader.repetition, .counted(completed: 3, total: 3), "the finished item keeps its count")
        second.recite()
        XCTAssertEqual(second.reader.itemNumber, 2, "a finished item is not counted again: it moves on")
        second.previous()
        XCTAssertEqual(second.reader.repetition, .counted(completed: 3, total: 3))

        let nextDay = try reopen(day.addingTimeInterval(86_400 * 2))
        nextDay.previous()
        XCTAssertEqual(nextDay.reader.repetition, .counted(completed: 0, total: 3), "a new day starts at zero")
    }

    func testRestartAndCompletionClearTheSavedCounts() async throws {
        let loaded = try await library()
        let chapter = try XCTUnwrap(loaded.chapter(id: "hisn-ch-017"))
        let counts = InMemoryItemCountStore()
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let controller = HisnReaderController(reader: try XCTUnwrap(HisnReader(chapter: chapter)),
                                              store: InMemoryHisnReadingPositionStore(), counts: counts, now: { day })
        controller.recite()
        XCTAssertEqual(counts.counts(in: .hisnSection(chapter.id), on: DayKey(date: day)).values.first, 1)
        controller.restart()
        XCTAssertTrue(counts.counts(in: .hisnSection(chapter.id), on: DayKey(date: day)).isEmpty)
        while !controller.reader.isCompleted { controller.recite() }
        XCTAssertTrue(counts.counts(in: .hisnSection(chapter.id), on: DayKey(date: day)).isEmpty,
                      "a finished chapter opens afresh")
    }

    /// A saved item (Favorites) opens in its section at its place.
    func testLocatingASavedItem() async throws {
        let loaded = try await library()
        let found = try XCTUnwrap(loaded.locate(itemId: "hisn-017-03"))
        XCTAssertEqual(found.chapter.id, "hisn-ch-017")
        XCTAssertEqual(found.chapter.items[found.itemIndex].id, "hisn-017-03")
        XCTAssertNil(loaded.locate(itemId: "gone"))
        for entry in loaded.sections.prefix(20) {
            let chapter = try XCTUnwrap(loaded.chapter(id: entry.id))
            for item in chapter.items {
                XCTAssertNotNil(loaded.locate(itemId: item.id), item.id)
            }
        }
    }
}
