import XCTest
import IslamicCore
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
}
