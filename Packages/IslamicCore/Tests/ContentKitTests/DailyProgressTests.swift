import XCTest
@testable import ContentKit

final class DailyProgressTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "DailyProgressTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    func testDayKeyFollowsTheLocalCalendar() {
        // 2026-10-08 22:30 UTC is still the 8th in London (BST) but already the 9th in Riyadh.
        let date = Date(timeIntervalSince1970: 1_791_498_600)
        XCTAssertEqual(DayKey(date: date, calendar: calendar("UTC")).string, "2026-10-08")
        XCTAssertEqual(DayKey(date: date, calendar: calendar("Asia/Riyadh")).string, "2026-10-09")
        XCTAssertEqual(DayKey(date: date, calendar: calendar("America/Los_Angeles")).string, "2026-10-08")
    }

    func testDayKeyParsingAndOrder() {
        XCTAssertEqual(DayKey(string: "2026-03-01"), DayKey(year: 2026, month: 3, day: 1))
        XCTAssertNil(DayKey(string: "2026-13-01"))
        XCTAssertNil(DayKey(string: "yesterday"))
        XCTAssertLessThan(DayKey(year: 2025, month: 12, day: 31), DayKey(year: 2026, month: 1, day: 1))
        let gregorian = calendar("UTC")
        XCTAssertEqual(DayKey(year: 2026, month: 3, day: 1).adding(days: -1, calendar: gregorian).string, "2026-02-28")
        XCTAssertEqual(DayKey(year: 2024, month: 3, day: 1).adding(days: -1, calendar: gregorian).string, "2024-02-29")
    }

    func testDayKeyAcrossDaylightSaving() {
        let berlin = calendar("Europe/Berlin")
        // Clocks go back on 2026-10-25; the day after the 24th is still the 25th.
        XCTAssertEqual(DayKey(year: 2026, month: 10, day: 24).adding(days: 1, calendar: berlin).string, "2026-10-25")
        XCTAssertEqual(DayKey(year: 2026, month: 3, day: 29).adding(days: 1, calendar: berlin).string, "2026-03-30")
    }

    func testMarkAndReadBack() {
        let store = UserDefaultsDailyProgressStore(defaults: defaults())
        let today = DayKey(year: 2026, month: 10, day: 8)
        XCTAssertTrue(store.completed(on: today).isEmpty)
        store.markCompleted(.hisnSection("hisn-ch-027"), on: today)
        store.markCompleted(.hisnSection("hisn-ch-027"), on: today)
        store.markCompleted(.dhikrGroup("morning"), on: today)
        XCTAssertEqual(store.completed(on: today), [.hisnSection("hisn-ch-027"), .dhikrGroup("morning")])
        XCTAssertTrue(store.isCompleted(.hisnSection("hisn-ch-027"), on: today))
        XCTAssertFalse(store.isCompleted(.hisnSection("hisn-ch-027"), on: today.adding(days: 1)))
    }

    func testSurvivesANewStoreAndUsesTheDocumentedFormat() throws {
        let defaults = defaults()
        let day = DayKey(year: 2026, month: 10, day: 8)
        UserDefaultsDailyProgressStore(defaults: defaults).markCompleted(.hisnSection("hisn-ch-001"), on: day)
        XCTAssertEqual(UserDefaultsDailyProgressStore(defaults: defaults).completed(on: day), [.hisnSection("hisn-ch-001")])
        let data = try XCTUnwrap(defaults.data(forKey: UserDefaultsDailyProgressStore.defaultKey))
        XCTAssertEqual(String(decoding: data, as: UTF8.self),
                       #"{"days":{"2026-10-08":["hisn:hisn-ch-001"]},"version":1}"#)
    }

    func testOldDaysArePruned() {
        let store = UserDefaultsDailyProgressStore(defaults: defaults(), retentionDays: 3)
        let first = DayKey(year: 2026, month: 10, day: 1)
        store.markCompleted(.dua("d1"), on: first)
        store.markCompleted(.dua("d2"), on: first.adding(days: 2))
        XCTAssertFalse(store.completed(on: first).isEmpty, "inside the window")
        store.markCompleted(.dua("d3"), on: first.adding(days: 3))
        XCTAssertTrue(store.completed(on: first).isEmpty, "older than the window")
        XCTAssertEqual(store.completed(on: first.adding(days: 2)), [.dua("d2")])
    }

    func testCorruptedOrUnsupportedDataIsRemoved() {
        let defaults = defaults()
        let key = UserDefaultsDailyProgressStore.defaultKey
        let store = UserDefaultsDailyProgressStore(defaults: defaults)
        let day = DayKey(year: 2026, month: 10, day: 8)
        defaults.set(Data("not json".utf8), forKey: key)
        XCTAssertTrue(store.completed(on: day).isEmpty)
        XCTAssertNil(defaults.data(forKey: key))
        defaults.set(Data(#"{"version":2,"days":{}}"#.utf8), forKey: key)
        XCTAssertTrue(store.completed(on: day).isEmpty)
        XCTAssertNil(defaults.data(forKey: key))
        defaults.set(Data(#"{"version":1,"days":{"2026-10-08":["nonsense"]}}"#.utf8), forKey: key)
        XCTAssertTrue(store.completed(on: day).isEmpty)
        store.markCompleted(.dua("d1"), on: day)
        XCTAssertEqual(store.completed(on: day), [.dua("d1")])
        store.clear()
        XCTAssertTrue(store.completed(on: day).isEmpty)
    }
}

final class ContentRefTests: XCTestCase {
    func testStringForm() throws {
        XCTAssertEqual(ContentRef.quranVerse(surah: 2, ayah: 255).string, "quran:2:255")
        XCTAssertEqual(ContentRef(string: "quran:2:255"), .quranVerse(surah: 2, ayah: 255))
        XCTAssertEqual(ContentRef(string: "hisn:hisn-001-01"), .hisnItem("hisn-001-01"))
        XCTAssertEqual(ContentRef.dhikrGroup("morning").string, "adhkar:group:morning")
        XCTAssertNil(ContentRef(string: "music:1"))
        XCTAssertNil(ContentRef(string: "quran:"))
        XCTAssertNil(ContentRef(string: "hisn"))
        let data = try JSONEncoder().encode([ContentRef.dua("d1")])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["dua:d1"]"#)
        XCTAssertEqual(try JSONDecoder().decode([ContentRef].self, from: data), [.dua("d1")])
        XCTAssertThrowsError(try JSONDecoder().decode([ContentRef].self, from: Data(#"["x"]"#.utf8)))
    }
}

final class ArabicSearchNormalizerTests: XCTestCase {
    func testRules() {
        XCTAssertEqual(ArabicSearchNormalizer.normalize("الحَمْدُ لِلَّهِ"), "الحمد لله")
        XCTAssertEqual(ArabicSearchNormalizer.normalize("أَإِآٱ"), "اااا")
        XCTAssertEqual(ArabicSearchNormalizer.normalize("مُوسَى رَحْمَة"), "موسي رحمه")
        XCTAssertEqual(ArabicSearchNormalizer.normalize("الحـــمد"), "الحمد")
        XCTAssertEqual(ArabicSearchNormalizer.normalize(" \n«قل» (هو) ١٢ abc "), "قل هو")
        // Uthmani marks: superscript alef and small high letters are dropped.
        XCTAssertEqual(ArabicSearchNormalizer.normalize("ٱلرَّحْمَـٰنِ"), "الرحمن")
        XCTAssertEqual(ArabicSearchNormalizer.normalize("مَـٰلِكِ يَوْمِ ٱلدِّينِ"), "ملك يوم الدين")
    }
}
