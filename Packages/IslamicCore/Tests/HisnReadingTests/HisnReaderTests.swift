import XCTest
import IslamicCore
@testable import HisnReading

/// Phase 3A: the Hisn reader state on the bundled content (navigation, repetition, resume).
final class HisnReaderTests: XCTestCase {
    private static var cached: HisnLibrary?

    private func library() async throws -> HisnLibrary {
        if let cached = Self.cached { return cached }
        let library = HisnLibrary(book: try await BundledHisnRepository().loadBook())
        Self.cached = library
        return library
    }

    private func reader(_ chapterId: String, at index: Int = 0, completed: Int = 0) async throws -> HisnReader {
        let chapter = try XCTUnwrap(try await library().chapter(id: chapterId), chapterId)
        return try XCTUnwrap(HisnReader(chapter: chapter, itemIndex: index, completedRepetitions: completed))
    }

    private func chapterId(ofItem itemId: String) async throws -> (chapter: String, index: Int) {
        for chapter in try await library().book.chapters {
            if let index = chapter.items.firstIndex(where: { $0.id == itemId }) { return (chapter.id, index) }
        }
        throw XCTSkip("missing \(itemId)")
    }

    // MARK: Structure

    func testStructureIsUnchanged() async throws {
        let library = try await library()
        XCTAssertEqual(library.book.canonicalChapters.count, 132)
        XCTAssertEqual(library.book.bookItemNumbers, Set(1...267))
        XCTAssertEqual(library.sections.count, 133)
        XCTAssertEqual(library.sections.reduce(0) { $0 + $1.itemCount }, 302)
    }

    // MARK: Index

    func testIndexListsThe133SectionsInOrderWithDomainTitles() async throws {
        let library = try await library()
        XCTAssertEqual(library.sections.map(\.id), library.book.chapters.map(\.id))
        XCTAssertEqual(library.sections.map(\.title), library.book.chapters.map(\.titleArabic))
        XCTAssertEqual(library.sections.map(\.itemCount), library.book.chapters.map(\.itemCount))
        XCTAssertEqual(Set(library.sections.map(\.id)).count, 133)
        for entry in library.sections {
            XCTAssertNotNil(library.chapter(id: entry.id), entry.id)
        }
    }

    func testChapter27IsShownAsMorningAndEvening() async throws {
        let library = try await library()
        let split = library.sections.filter { $0.timeOfDay != nil }
        XCTAssertEqual(split.map(\.id), ["hisn-ch-027", "hisn-ch-028"])
        XCTAssertEqual(split.map(\.timeOfDay), [.morning, .evening])
        XCTAssertEqual(split.map { HisnSearchKey.make($0.title) }, ["اذكار الصباح", "اذكار المساء"],
                       "titles come from the domain")
    }

    // MARK: Navigation

    func testOpeningAChapterStartsAtItsFirstItem() async throws {
        let library = try await library()
        for chapter in library.book.chapters {
            let reader = try XCTUnwrap(HisnReader(chapter: chapter), chapter.id)
            XCTAssertEqual(reader.currentItem.id, chapter.items.first?.id, chapter.id)
            XCTAssertEqual(reader.itemCount, chapter.items.count)
            XCTAssertEqual(reader.itemNumber, 1)
            XCTAssertEqual(reader.progress, 0)
            XCTAssertFalse(reader.isCompleted)
        }
    }

    func testNextAndPreviousFollowTheDomainSession() async throws {
        var reader = try await reader("hisn-ch-027")
        let chapter = reader.chapter
        var domain = try XCTUnwrap(HisnSession(chapter: chapter))
        var visited = [reader.currentItem.id]
        while !reader.isLastItem {
            reader.next()
            domain.next()
            XCTAssertEqual(reader.currentItem.id, domain.currentItem.id)
            XCTAssertEqual(reader.progress, Double(reader.itemIndex) / Double(chapter.items.count), "display items")
            visited.append(reader.currentItem.id)
        }
        XCTAssertEqual(visited, chapter.items.map(\.id), "display order, every item once")
        while !reader.isFirstItem {
            reader.previous()
        }
        XCTAssertEqual(reader.currentItem.id, chapter.items[0].id)
        reader.previous()
        XCTAssertEqual(reader.itemIndex, 0, "previous stops at the first item")
        XCTAssertFalse(reader.isCompleted)
    }

    func testNextOnTheLastItemCompletesTheChapterWithoutLeavingIt() async throws {
        let library = try await library()
        let chapter = try XCTUnwrap(library.chapter(id: "hisn-ch-001"))
        var reader = try XCTUnwrap(HisnReader(chapter: chapter, itemIndex: chapter.items.count - 1))
        reader.next()
        XCTAssertTrue(reader.isCompleted)
        XCTAssertEqual(reader.progress, 1)
        XCTAssertEqual(reader.chapter.id, "hisn-ch-001", "no automatic move to the next chapter")
        XCTAssertEqual(reader.currentItem.id, chapter.items.last?.id)
        reader.next()
        XCTAssertEqual(reader.chapter.id, "hisn-ch-001")
        XCTAssertTrue(reader.isCompleted)
        XCTAssertEqual(reader.recite(), .completed)
    }

    func testCompletionOffersRestartAndReturn() async throws {
        let chapter = try XCTUnwrap(try await library().chapter(id: "hisn-ch-001"))
        var reader = try XCTUnwrap(HisnReader(chapter: chapter, itemIndex: chapter.items.count - 1))
        reader.next()
        reader.previous()
        XCTAssertFalse(reader.isCompleted)
        XCTAssertEqual(reader.currentItem.id, chapter.items.last?.id, "back to the last item")
        reader.next()
        reader.restart()
        XCTAssertFalse(reader.isCompleted)
        XCTAssertEqual(reader.itemIndex, 0)
        XCTAssertEqual(reader.completedRepetitions, 0)
    }

    func testOutOfRangeItemIsRejected() async throws {
        let chapter = try XCTUnwrap(try await library().chapter(id: "hisn-ch-001"))
        XCTAssertNil(HisnReader(chapter: chapter, itemIndex: chapter.items.count))
        XCTAssertNil(HisnReader(chapter: chapter, itemIndex: -1))
    }

    // MARK: Repetition

    func testKnownCountIsCountedBeforeMovingOn() async throws {
        let (chapterId, index) = try await chapterId(ofItem: "hisn-017-01")
        var reader = try await reader(chapterId, at: index)
        XCTAssertEqual(reader.currentItem.repetition.count, 3)
        XCTAssertEqual(reader.repetition, .counted(completed: 0, total: 3))
        XCTAssertEqual(reader.recite(), .counted(remaining: 2))
        XCTAssertEqual(reader.repetition, .counted(completed: 1, total: 3))
        XCTAssertEqual(reader.recite(), .counted(remaining: 1))
        XCTAssertEqual(reader.currentItem.id, "hisn-017-01")
        XCTAssertEqual(reader.recite(), .movedToNext)
        XCTAssertEqual(reader.itemIndex, index + 1)
        XCTAssertEqual(reader.completedRepetitions, 0)
    }

    func testFinalRepetitionOfTheLastItemCompletesTheChapter() async throws {
        let (chapterId, index) = try await chapterId(ofItem: "hisn-034-01")
        var reader = try await reader(chapterId, at: index)
        XCTAssertTrue(reader.isLastItem)
        XCTAssertEqual(reader.repetition, .counted(completed: 0, total: 3))
        reader.recite()
        reader.recite()
        XCTAssertFalse(reader.isCompleted)
        XCTAssertEqual(reader.recite(), .completed)
        XCTAssertTrue(reader.isCompleted)
        XCTAssertEqual(reader.chapter.id, chapterId)
    }

    func testCountOfOneIsReadOnce() async throws {
        var reader = try await reader("hisn-ch-001")
        XCTAssertEqual(reader.currentItem.repetition.count, 1)
        XCTAssertEqual(reader.repetition, .once)
        XCTAssertEqual(reader.recite(), .movedToNext)
    }

    func testNilCountIsReadOnceAndNoCountIsInvented() async throws {
        for itemId in ["hisn-029-06", "hisn-130-02", "hisn-130-06", "hisn-025-02"] {
            let (chapterId, index) = try await chapterId(ofItem: itemId)
            var reader = try await reader(chapterId, at: index)
            XCTAssertNil(reader.currentItem.repetition.count, itemId)
            XCTAssertEqual(reader.repetition, .unstated, itemId)
            let step = reader.recite()
            XCTAssertTrue(step == .movedToNext || step == .completed, itemId)
            XCTAssertTrue(reader.isCompleted || reader.currentItem.id != itemId, "\(itemId) is read once")
        }
    }

    func testEveryItemShowsOnlyItsStatedCount() async throws {
        for chapter in try await library().book.chapters {
            for index in chapter.items.indices {
                let reader = try XCTUnwrap(HisnReader(chapter: chapter, itemIndex: index))
                switch reader.currentItem.repetition.count {
                case nil: XCTAssertEqual(reader.repetition, .unstated)
                case let count? where count > 1: XCTAssertEqual(reader.repetition, .counted(completed: 0, total: count))
                default: XCTAssertEqual(reader.repetition, .once)
                }
            }
        }
    }

    // MARK: Presentation

    func testPresentationShowsTextAndSourcesOnly() async throws {
        let reader = try await reader("hisn-ch-001")
        let item = reader.currentItem
        XCTAssertEqual(reader.presentation.text, item.arabicText, "text unchanged")
        XCTAssertEqual(reader.presentation.sources, item.references.map(\.originalText))
        XCTAssertEqual(Mirror(reflecting: reader.presentation).children.compactMap { $0.label }, ["text", "sources"],
                       "no review flags, ids, hashes or provenance reach the screen")
    }

    func testPresentationTextIsTheBundledTextForEveryItem() async throws {
        for item in try await library().book.allItems {
            XCTAssertEqual(HisnItemPresentation(item: item).text, item.arabicText, item.id)
        }
    }
}
