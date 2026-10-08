import XCTest
import IslamicCore
@testable import HisnReading

/// Phase 3D: the persistent reading cursor (format, versioning, invalid data) and resume.
final class HisnPersistenceTests: XCTestCase {
    private static var cached: HisnLibrary?
    private var suite = ""
    private var defaults: UserDefaults!
    private let key = UserDefaultsHisnReadingPositionStore.defaultKey
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Riyadh")!
        return calendar
    }()

    override func setUpWithError() throws {
        suite = "HisnPersistenceTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func library() async throws -> HisnLibrary {
        if let cached = Self.cached { return cached }
        let library = HisnLibrary(book: try await BundledHisnRepository().loadBook())
        Self.cached = library
        return library
    }

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private var store: UserDefaultsHisnReadingPositionStore { UserDefaultsHisnReadingPositionStore(defaults: defaults) }

    private func position(_ chapterId: String = "hisn-ch-017", _ itemId: String = "hisn-017-01", index: Int = 0,
                          repetitions: Int = 0, day: Int = 8) -> HisnReadingPosition {
        HisnReadingPosition(chapterId: chapterId, itemId: itemId, itemIndex: index, completedRepetitions: repetitions,
                            savedAt: date(day, 7))
    }

    private func storeJSON(_ object: [String: Any]) throws {
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: key)
    }

    private func validObject() -> [String: Any] {
        ["version": 1, "chapterId": "hisn-ch-017", "itemId": "hisn-017-01", "itemIndex": 0,
         "completedRepetitions": 2, "savedAt": date(8, 7).timeIntervalSinceReferenceDate]
    }

    // MARK: Store

    func testSaveLoadUpdateClear() {
        XCTAssertNil(store.load())
        store.save(position(repetitions: 1))
        XCTAssertEqual(store.load(), position(repetitions: 1), "survives a new store (app relaunch)")
        store.save(position("hisn-ch-001", "hisn-001-02", index: 1))
        XCTAssertEqual(store.load(), position("hisn-ch-001", "hisn-001-02", index: 1), "update replaces")
        store.clear()
        XCTAssertNil(store.load())
        XCTAssertNil(defaults.object(forKey: key))
    }

    func testFormatCarriesVersion1() throws {
        store.save(position(repetitions: 2))
        let data = try XCTUnwrap(defaults.data(forKey: key))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["version"] as? Int, HisnReadingPosition.currentVersion)
        XCTAssertEqual(HisnReadingPosition.currentVersion, 1)
        XCTAssertEqual(Set(object.keys), ["version", "chapterId", "itemId", "itemIndex", "completedRepetitions", "savedAt"])
        store.save(position(repetitions: 2))
        XCTAssertEqual(defaults.data(forKey: key), data, "deterministic encoding")
    }

    func testPhase3ADataWithoutVersionStillLoads() throws {
        var legacy = validObject()
        legacy.removeValue(forKey: "version")
        try storeJSON(legacy)
        XCTAssertEqual(store.load(), position(repetitions: 2))
    }

    func testUnsupportedVersionIsDiscarded() throws {
        var future = validObject()
        future["version"] = 2
        try storeJSON(future)
        XCTAssertNil(store.load())
        XCTAssertNil(defaults.object(forKey: key), "replaced by a clean state")
    }

    func testCorruptedAndIncompleteDataIsDiscarded() throws {
        let broken: [Any] = [
            Data("not json".utf8),
            Data("{}".utf8),
            "a string, not data",
            42,
        ]
        for value in broken {
            defaults.set(value, forKey: key)
            XCTAssertNil(store.load(), "\(value)")
            XCTAssertNil(defaults.object(forKey: key), "\(value) removed")
        }
        for field in ["chapterId", "itemId", "itemIndex", "completedRepetitions", "savedAt"] {
            var object = validObject()
            object.removeValue(forKey: field)
            try storeJSON(object)
            XCTAssertNil(store.load(), "missing \(field)")
        }
        let invalid: [(String, Any)] = [("chapterId", ""), ("itemId", ""), ("itemIndex", -1),
                                        ("completedRepetitions", -3), ("itemIndex", "zero")]
        for (field, value) in invalid {
            var object = validObject()
            object[field] = value
            try storeJSON(object)
            XCTAssertNil(store.load(), "\(field) = \(value)")
        }
    }

    // MARK: Resume

    func testValidCursorResumesAtTheSavedItem() async throws {
        let library = try await library()
        store.save(position("hisn-ch-027", "hisn-027-04", index: 3))
        let resumed = try XCTUnwrap(HisnResume.position(in: store, library: library, now: date(8, 9), calendar: calendar))
        let reader = try XCTUnwrap(HisnResume.reader(for: resumed, in: library))
        XCTAssertEqual(reader.chapter.id, "hisn-ch-027")
        XCTAssertEqual(reader.currentItem.id, library.chapter(id: "hisn-ch-027")?.items[3].id)
        XCTAssertEqual(reader.itemIndex, 3)
    }

    func testMissingCursorOpensTheIndex() async throws {
        XCTAssertNil(HisnResume.position(in: store, library: try await library(), now: date(8, 9), calendar: calendar))
    }

    func testInvalidChapterOrItemOpensTheIndexAndIsCleared() async throws {
        let library = try await library()
        for invalid in [position("hisn-ch-999", "hisn-999-01"), position("hisn-ch-017", "hisn-999-01"),
                        position("hisn-ch-017", "hisn-001-01")] {
            store.save(invalid)
            XCTAssertNil(HisnResume.position(in: store, library: library, now: date(8, 9), calendar: calendar),
                         "\(invalid)")
            XCTAssertNil(defaults.object(forKey: key), "invalid cursor cleared")
        }
    }

    func testCorruptedStoreOpensTheIndex() async throws {
        defaults.set(Data([0xFF, 0x00, 0x13]), forKey: key)
        XCTAssertNil(HisnResume.position(in: store, library: try await library(), now: date(8, 9), calendar: calendar))
    }

    func testStaleIndexIsCorrectedByItemId() async throws {
        let library = try await library()
        store.save(position("hisn-ch-027", "hisn-027-04", index: 40))
        let resumed = try XCTUnwrap(HisnResume.position(in: store, library: library, now: date(8, 9), calendar: calendar))
        XCTAssertEqual(HisnResume.reader(for: resumed, in: library)?.currentItem.id, "hisn-027-04")
    }
}
