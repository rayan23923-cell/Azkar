import XCTest
import IslamicCore
import ContentKit
@testable import AdhkarReading

final class AdhkarLibraryTests: XCTestCase {
    func testBundledCollectionsLoadUnchanged() async throws {
        let library = try await AdhkarLibrary.load()
        XCTAssertEqual(library.adhkar.map(\.ref.string),
                       ["adhkar:group:morning", "adhkar:group:evening", "adhkar:group:afterPrayer",
                        "adhkar:group:sleep", "adhkar:group:general"])
        XCTAssertEqual(library.adhkar.map(\.items.count), [11, 11, 12, 11, 6])
        XCTAssertEqual(library.duas.map(\.ref.string), ["dua:category:quranic", "dua:category:prophetic"])
        XCTAssertEqual(library.duas.map(\.items.count), [10, 7])
        XCTAssertEqual(library.itemCount, 68)

        // Texts and sources are the stored ones.
        let repository = BundledDhikrRepository()
        let morning = try await repository.loadItems(group: .morning)
        XCTAssertEqual(library.adhkar[0].items.map(\.text), morning.map(\.arabicText))
        XCTAssertEqual(library.adhkar[0].items.map(\.source), morning.map(\.source))
        XCTAssertEqual(library.adhkar[0].items.map(\.repeatCount), morning.map(\.repeatCount))
        XCTAssertTrue(library.duas.flatMap(\.items).allSatisfy { $0.repeatCount == 1 })
    }

    func testLocateAndLookup() async throws {
        let library = try await AdhkarLibrary.load()
        let ref = ContentRef.dhikr("dhikr-morning-002")
        let found = try XCTUnwrap(library.locate(ref))
        XCTAssertEqual(found.collection.ref, .dhikrGroup("morning"))
        XCTAssertEqual(found.index, 1)
        XCTAssertEqual(library.item(ref)?.order, 2)
        XCTAssertNil(library.locate(.dhikr("missing")))
        XCTAssertNotNil(library.collection(.duaCategory("quranic")))
        XCTAssertNil(library.collection(.duaCategory("missing")))
    }
}

@MainActor
final class DevotionalReaderTests: XCTestCase {
    private func morning() async throws -> DevotionalCollection {
        let library = try await AdhkarLibrary.load()
        return try XCTUnwrap(library.collection(.dhikrGroup("morning")))
    }

    func testCountingMovesOnAfterTheRepetitions() async throws {
        let collection = try await morning()
        let store = InMemoryDevotionalPositionStore()
        let reader = try XCTUnwrap(DevotionalReaderController(collection: collection, store: store))
        XCTAssertEqual(reader.index, 0)
        XCTAssertEqual(reader.recite(), .movedToNext)  // آية الكرسي, once
        XCTAssertEqual(reader.index, 1)
        XCTAssertEqual(reader.remaining, 3)
        XCTAssertEqual(reader.recite(), .repeated(remaining: 2))
        XCTAssertEqual(store.position(in: collection.ref)?.item, .dhikr("dhikr-morning-002"))
        XCTAssertEqual(store.position(in: collection.ref)?.repetitions, 1)
    }

    func testFinishingRecordsTodayAndClearsThePosition() async throws {
        let collection = try await morning()
        let store = InMemoryDevotionalPositionStore()
        let daily = InMemoryDailyProgressStore()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let reader = try XCTUnwrap(DevotionalReaderController(collection: collection, store: store,
                                                              dailyProgress: daily, now: { date }))
        let total = collection.totalRepetitions
        for _ in 0..<(total - 1) { reader.recite() }
        XCTAssertFalse(reader.isComplete)
        XCTAssertEqual(reader.recite(), .finished)
        XCTAssertTrue(reader.isComplete)
        XCTAssertTrue(daily.completed(on: DayKey(date: date)).contains(collection.ref))
        XCTAssertNil(store.position(in: collection.ref))
        XCTAssertEqual(reader.recite(), .finished)
        reader.restart()
        XCTAssertFalse(reader.isComplete)
        XCTAssertEqual(reader.index, 0)
    }

    func testResumeRestoresItemAndRepetitions() async throws {
        let collection = try await morning()
        let store = InMemoryDevotionalPositionStore()
        store.save(DevotionalPosition(item: .dhikr("dhikr-morning-002"), repetitions: 2, savedAt: Date()),
                   in: collection.ref)
        let reader = try XCTUnwrap(DevotionalReaderController(collection: collection, store: store))
        XCTAssertEqual(reader.index, 1)
        XCTAssertEqual(reader.remaining, 1)

        // A saved count at or above the item's total never completes the item on open.
        store.save(DevotionalPosition(item: .dhikr("dhikr-morning-002"), repetitions: 9, savedAt: Date()),
                   in: collection.ref)
        let again = try XCTUnwrap(DevotionalReaderController(collection: collection, store: store))
        XCTAssertEqual(again.index, 1)
        XCTAssertEqual(again.remaining, 1)

        // A stale item opens at the start.
        store.save(DevotionalPosition(item: .dhikr("gone"), repetitions: 1, savedAt: Date()), in: collection.ref)
        let stale = try XCTUnwrap(DevotionalReaderController(collection: collection, store: store))
        XCTAssertEqual(stale.index, 0)
        XCTAssertEqual(stale.cursor.completedRepetitions, 0)
    }

    func testOpeningAtAnItemKeepsOnlyItsOwnSavedCount() async throws {
        let collection = try await morning()
        let store = InMemoryDevotionalPositionStore()
        store.save(DevotionalPosition(item: .dhikr("dhikr-morning-002"), repetitions: 1, savedAt: Date()),
                   in: collection.ref)
        let other = try XCTUnwrap(DevotionalReaderController(collection: collection, start: .dhikr("dhikr-morning-003"),
                                                             store: store))
        XCTAssertEqual(other.index, 2)
        XCTAssertEqual(other.cursor.completedRepetitions, 0)
        let same = try XCTUnwrap(DevotionalReaderController(collection: collection, start: .dhikr("dhikr-morning-002"),
                                                            store: store))
        XCTAssertEqual(same.cursor.completedRepetitions, 1)
    }

    func testNavigationStopsAtTheEnds() async throws {
        let collection = try await morning()
        let reader = try XCTUnwrap(DevotionalReaderController(collection: collection,
                                                              store: InMemoryDevotionalPositionStore()))
        reader.previous()
        XCTAssertEqual(reader.index, 0)
        reader.jump(to: collection.items.count - 1)
        reader.next()
        XCTAssertEqual(reader.index, collection.items.count - 1)
        reader.jump(to: 99)
        XCTAssertEqual(reader.index, collection.items.count - 1)
    }

    func testPositionsPersistInUserDefaults() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "adhkar.positions.tests"))
        defaults.removePersistentDomain(forName: "adhkar.positions.tests")
        let store = UserDefaultsDevotionalPositionStore(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        store.save(DevotionalPosition(item: .dua("dua-quranic-003"), repetitions: 0, savedAt: date),
                   in: .duaCategory("quranic"))
        let reread = UserDefaultsDevotionalPositionStore(defaults: defaults)
        XCTAssertEqual(reread.position(in: .duaCategory("quranic"))?.item, .dua("dua-quranic-003"))
        reread.clear(.duaCategory("quranic"))
        XCTAssertNil(store.position(in: .duaCategory("quranic")))

        defaults.set(Data("not json".utf8), forKey: UserDefaultsDevotionalPositionStore.defaultKey)
        XCTAssertNil(store.position(in: .duaCategory("quranic")))
        XCTAssertNil(defaults.data(forKey: UserDefaultsDevotionalPositionStore.defaultKey))
    }

    func testCountsComeBackAfterRelaunchTheSameDay() async throws {
        let collection = try await morning()
        let store = InMemoryDevotionalPositionStore()
        let counts = InMemoryItemCountStore()
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try XCTUnwrap(DevotionalReaderController(collection: collection, store: store, counts: counts,
                                                             now: { day }))
        first.recite()                       // item 1, once
        first.recite(); first.recite(); first.recite() // item 2, three times
        XCTAssertEqual(first.index, 2)
        first.persist()

        let second = try XCTUnwrap(DevotionalReaderController(collection: collection, store: store, counts: counts,
                                                              now: { day.addingTimeInterval(600) }))
        XCTAssertEqual(second.index, 2)
        second.previous()
        XCTAssertEqual(second.remaining, 0, "the finished item keeps its count after the app is opened again")
        XCTAssertEqual(second.cursor.completedRepetitions, 3)
        second.previous()
        XCTAssertEqual(second.remaining, 0)

        let nextDay = try XCTUnwrap(DevotionalReaderController(collection: collection, store: store, counts: counts,
                                                               now: { day.addingTimeInterval(86_400 * 2) }))
        nextDay.jump(to: 1)
        XCTAssertEqual(nextDay.remaining, 3, "a new day starts at zero")

        second.restart()
        XCTAssertTrue(counts.counts(in: collection.ref, on: DayKey(date: day)).isEmpty)
    }

    func testUserDefaultsItemCountsKeepOneDay() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "item-counts-\(UUID().uuidString)"))
        let store = UserDefaultsItemCountStore(defaults: defaults)
        let today = DayKey(year: 2026, month: 10, day: 9)
        let group = ContentRef.dhikrGroup("morning")
        store.save(["a": 3, "b": 0], in: group, on: today)
        XCTAssertEqual(UserDefaultsItemCountStore(defaults: defaults).counts(in: group, on: today), ["a": 3])
        XCTAssertTrue(store.counts(in: group, on: today.adding(days: 1)).isEmpty)
        store.save(["c": 1], in: .hisnSection("hisn-ch-001"), on: today.adding(days: 1))
        XCTAssertTrue(store.counts(in: group, on: today).isEmpty, "writing a new day drops the old one")
        store.clear(.hisnSection("hisn-ch-001"))
        XCTAssertNil(defaults.data(forKey: UserDefaultsItemCountStore.defaultKey))
        defaults.set(Data("bad".utf8), forKey: UserDefaultsItemCountStore.defaultKey)
        XCTAssertTrue(store.counts(in: group, on: today).isEmpty)
        XCTAssertNil(defaults.data(forKey: UserDefaultsItemCountStore.defaultKey), "unreadable data is removed")
    }
}

final class DevotionalSearchTests: XCTestCase {
    func testSearchFindsTitlesThenTextsDeterministically() async throws {
        let library = try await AdhkarLibrary.load()
        let index = DevotionalSearchIndex(library: library)
        XCTAssertEqual(index.entryCount, 68 + 7)
        XCTAssertTrue(index.search("   ").isEmpty)
        XCTAssertTrue(index.search("abc").isEmpty)

        let morning = index.search("أذكار الصباح")
        XCTAssertEqual(morning.first?.kind, .collection)
        XCTAssertEqual(morning.first?.collection, .dhikrGroup("morning"))

        let first = index.search("سبحان الله")
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, index.search("سُبْحَانَ اللَّهِ"))
        XCTAssertEqual(first, DevotionalSearchIndex(library: library).search("سبحان الله"))
        XCTAssertEqual(Set(first.map(\.id)).count, first.count)
        for pair in zip(first, first.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.match, pair.1.match)
        }
    }

    func testStandardSpellingFindsUthmaniVersesAndKindFilter() async throws {
        let library = try await AdhkarLibrary.load()
        let index = DevotionalSearchIndex(library: library)
        let results = index.search("ربنا اتنا في الدنيا حسنة")
        XCTAssertTrue(results.contains { $0.item == .dua("dua-quranic-001") })
        XCTAssertTrue(index.search("ربنا", kind: .adhkar).allSatisfy { $0.collectionKind == .adhkar })
        XCTAssertTrue(index.search("ربنا", kind: .dua).allSatisfy { $0.collectionKind == .dua })
        for result in results {
            let text = try XCTUnwrap(library.item(try XCTUnwrap(result.item))?.text)
            if !result.matchedText.hasPrefix("… ") && !result.matchedText.hasSuffix(" …") {
                XCTAssertEqual(result.matchedText, text)
            }
        }
    }

    func testAccessibilityText() async throws {
        XCTAssertEqual(DevotionalAccessibility.repetitions(1), "مرة واحدة")
        XCTAssertEqual(DevotionalAccessibility.repetitions(2), "مرتان")
        XCTAssertEqual(DevotionalAccessibility.repetitions(3), "3 مرات")
        XCTAssertEqual(DevotionalAccessibility.repetitions(33), "33 مرة")
        XCTAssertEqual(DevotionalAccessibility.remaining(0), "اكتمل")
        XCTAssertEqual(DevotionalAccessibility.itemPosition(0, of: 11), "1 من 11")
        let library = try await AdhkarLibrary.load()
        XCTAssertEqual(DevotionalAccessibility.collectionLabel(library.adhkar[0], completedToday: true),
                       "أذكار الصباح، 11 أذكار، أُتمّت اليوم")
        let latin = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        XCTAssertNil(DevotionalAccessibility.counterHint.rangeOfCharacter(from: latin))
    }
}
