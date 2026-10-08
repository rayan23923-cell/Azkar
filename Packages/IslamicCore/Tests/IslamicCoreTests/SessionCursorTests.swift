import XCTest
@testable import IslamicCore

private struct Item: RepeatableContent, Equatable {
    let name: String
    let repeatCount: Int
}

final class SessionCursorTests: XCTestCase {
    private func items(_ counts: Int...) -> [Item] {
        counts.enumerated().map { Item(name: "i\($0.offset)", repeatCount: $0.element) }
    }

    func testEmptyListAndBadStartIndexAreRejected() {
        XCTAssertNil(SessionCursor<Item>(items: []))
        XCTAssertNil(SessionCursor(items: items(1, 1), startIndex: 2))
        XCTAssertNil(SessionCursor(items: items(1), startIndex: -1))
    }

    func testPreviousOnFirstStaysFirst() throws {
        var cursor = try XCTUnwrap(SessionCursor(items: items(1, 1, 1)))
        XCTAssertFalse(cursor.previous())
        XCTAssertEqual(cursor.index, 0)
        XCTAssertTrue(cursor.isFirst)
    }

    func testNextOnLastStaysLast() throws {
        var cursor = try XCTUnwrap(SessionCursor(items: items(1, 1, 1), startIndex: 2))
        XCTAssertFalse(cursor.next())
        XCTAssertEqual(cursor.index, 2)
        XCTAssertTrue(cursor.isLast)
    }

    func testNormalNextAndPrevious() throws {
        var cursor = try XCTUnwrap(SessionCursor(items: items(1, 1, 1)))
        XCTAssertTrue(cursor.next())
        XCTAssertEqual(cursor.current.name, "i1")
        XCTAssertTrue(cursor.next())
        XCTAssertEqual(cursor.current.name, "i2")
        XCTAssertTrue(cursor.previous())
        XCTAssertEqual(cursor.current.name, "i1")
    }

    func testSingleItem() throws {
        var cursor = try XCTUnwrap(SessionCursor(items: items(1)))
        XCTAssertTrue(cursor.isFirst && cursor.isLast)
        XCTAssertFalse(cursor.next())
        XCTAssertFalse(cursor.previous())
        XCTAssertEqual(cursor.advance(), .finished)
        XCTAssertTrue(cursor.isFinished)
        XCTAssertEqual(cursor.advance(), .finished)
        XCTAssertEqual(cursor.index, 0)
    }

    func testRepeatCountOneMovesOnEachAdvance() throws {
        var cursor = try XCTUnwrap(SessionCursor(items: items(1, 1, 1)))
        XCTAssertEqual(cursor.advance(), .movedToNext)
        XCTAssertEqual(cursor.index, 1)
        XCTAssertEqual(cursor.advance(), .movedToNext)
        XCTAssertEqual(cursor.advance(), .finished)
        XCTAssertEqual(cursor.index, 2)
        XCTAssertEqual(cursor.progress, 1)
    }

    func testRepeatCountAboveOneWaitsForAllRepetitions() throws {
        var cursor = try XCTUnwrap(SessionCursor(items: items(3, 1)))
        XCTAssertEqual(cursor.remainingRepetitions, 3)
        XCTAssertEqual(cursor.advance(), .repeated(remaining: 2))
        XCTAssertEqual(cursor.index, 0)
        XCTAssertEqual(cursor.advance(), .repeated(remaining: 1))
        XCTAssertEqual(cursor.index, 0)
        XCTAssertEqual(cursor.advance(), .movedToNext)
        XCTAssertEqual(cursor.index, 1)
        XCTAssertEqual(cursor.completedRepetitions, 0)
    }

    func testRepeatOnLastItemThenFinish() throws {
        var cursor = try XCTUnwrap(SessionCursor(items: items(1, 2), startIndex: 1))
        XCTAssertEqual(cursor.advance(), .repeated(remaining: 1))
        XCTAssertFalse(cursor.isFinished)
        XCTAssertEqual(cursor.advance(), .finished)
        XCTAssertTrue(cursor.isFinished)
        XCTAssertEqual(cursor.remainingRepetitions, 0)
    }

    func testNavigationResetsRepetitionsAndFinishedState() throws {
        var cursor = try XCTUnwrap(SessionCursor(items: items(3, 3)))
        cursor.advance()
        XCTAssertEqual(cursor.completedRepetitions, 1)
        cursor.next()
        XCTAssertEqual(cursor.completedRepetitions, 0)
        cursor.advance(); cursor.advance(); cursor.advance()
        XCTAssertTrue(cursor.isFinished)
        XCTAssertTrue(cursor.previous())
        XCTAssertFalse(cursor.isFinished)
        XCTAssertEqual(cursor.remainingRepetitions, 3)
    }

    func testZeroOrNegativeRepeatCountActsAsOne() throws {
        var cursor = try XCTUnwrap(SessionCursor(items: items(0, -2, 1)))
        XCTAssertEqual(cursor.advance(), .movedToNext)
        XCTAssertEqual(cursor.advance(), .movedToNext)
    }

    func testJump() throws {
        var cursor = try XCTUnwrap(SessionCursor(items: items(1, 1, 1)))
        XCTAssertTrue(cursor.jump(to: 2))
        XCTAssertTrue(cursor.isLast)
        XCTAssertFalse(cursor.jump(to: 3))
        XCTAssertEqual(cursor.index, 2)
    }
}

final class SessionTests: XCTestCase {
    func testQuranSessionStartsAtRequestedAyah() async throws {
        let repository = BundledQuranRepository()
        let surah = try await repository.loadSurah(id: 1)
        let verses = try await repository.loadVerses(surahId: 1)
        var session = try XCTUnwrap(QuranSession(surah: surah, verses: verses, startAyah: 7))
        XCTAssertEqual(session.currentVerse.ayahNumber, 7)
        XCTAssertFalse(session.cursor.next())
        XCTAssertNil(QuranSession(surah: surah, verses: verses, startAyah: 8))
        let baqarah = try await repository.loadVerses(surahId: 2)
        XCTAssertNil(QuranSession(surah: surah, verses: baqarah), "verses from another surah")
    }

    func testDhikrSessionHonoursRepeatCount() async throws {
        let repository = BundledDhikrRepository()
        let groups = try await repository.loadGroups()
        let group = try XCTUnwrap(groups.first { $0.id == .afterPrayer })
        let items = try await repository.loadItems(group: .afterPrayer)
        var session = try XCTUnwrap(DhikrSession(group: group, items: items))
        XCTAssertEqual(session.currentItem.repeatCount, 3)
        session.cursor.advance()
        session.cursor.advance()
        XCTAssertEqual(session.currentItem.order, 1)
        session.cursor.advance()
        XCTAssertEqual(session.currentItem.order, 2)
    }

    func testDuaSessionWalksCategory() async throws {
        let repository = BundledDuaRepository()
        let categories = try await repository.loadCategories()
        let category = try XCTUnwrap(categories.first)
        let items = try await repository.loadItems(category: category.id)
        var session = try XCTUnwrap(DuaSession(category: category, items: items))
        for _ in 1..<items.count { XCTAssertEqual(session.cursor.advance(), .movedToNext) }
        XCTAssertEqual(session.cursor.advance(), .finished)
    }
}

final class StateTypeTests: XCTestCase {
    func testStateCasesMatchV1Spec() {
        XCTAssertEqual(SessionState.allCases.map(\.rawValue),
                       ["idle", "preparing", "ready", "playing", "paused", "stopping", "stopped", "error"])
        XCTAssertEqual(PlaybackState.allCases.map(\.rawValue),
                       ["stopped", "playing", "paused", "buffering", "completed", "error"])
        XCTAssertEqual(PiPState.allCases.map(\.rawValue),
                       ["unavailable", "idle", "starting", "active", "stopping", "stopped", "error"])
        XCTAssertEqual(AudioState.allCases.map(\.rawValue),
                       ["unavailable", "idle", "playing", "paused", "stopped", "interrupted", "error"])
    }
}
