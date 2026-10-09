import XCTest
import Combine
import PiPCore
import PiPRendering
import PrayerTimes
@testable import PiPProviders

/// The day's prayer times in PiP: the next prayer and the time left in the counter line, the
/// day's six times in the text, and skip to move between days.
@MainActor
final class PrayerPiPProviderTests: XCTestCase {
    private let zone = TimeZone(identifier: "Asia/Baghdad")!
    private var schedule: PrayerSchedule {
        PrayerSchedule(coordinates: Coordinates(latitude: 33.3152, longitude: 44.3661), timeZone: zone,
                       parameters: PrayerParameters())
    }

    func testShowsTheNextPrayerAndTheDaysTimes() throws {
        let noon = Date(timeIntervalSince1970: 1_791_537_600) // 2026-10-09 12:20 in Baghdad
        let today = try XCTUnwrap(schedule.day(containing: noon))
        var now = today.asr.addingTimeInterval(-65 * 60)
        let provider = PrayerPiPProvider(schedule: schedule, placeName: "بغداد", now: { now })
        let content = try XCTUnwrap(provider.current)
        XCTAssertEqual(content.contentType, .prayer)
        XCTAssertEqual(content.title, "بغداد")
        XCTAssertTrue(content.subtitle.hasPrefix("اليوم · "))
        let asr = PrayerFormat.clock(today.asr, timeZone: zone)
        XCTAssertEqual(content.detail, "العصر \(asr)  ·  بعد 1:05")
        XCTAssertNil(content.repetition, "nothing to count")
        for prayer in Prayer.allCases {
            XCTAssertTrue(content.text.contains("\(prayer.arabicName) \(PrayerFormat.clock(today.time(of: prayer), timeZone: zone))"))
        }
        XCTAssertEqual(content.text.split(separator: "\n").count, 3, "two times a line")
        now = today.asr.addingTimeInterval(-4 * 60)
        XCTAssertEqual(provider.current?.detail, "العصر \(asr)  ·  بعد 4 دقائق", "the countdown follows the clock")
    }

    func testSkipMovesBetweenDays() throws {
        let now = Date(timeIntervalSince1970: 1_791_537_600)
        let provider = PrayerPiPProvider(schedule: schedule, placeName: "بغداد", now: { now })
        XCTAssertTrue(try XCTUnwrap(provider.current).isFirst)
        provider.goToPrevious()
        XCTAssertEqual(provider.dayOffset, 0, "not before today")
        provider.goToNext()
        let tomorrow = try XCTUnwrap(schedule.day(containing: now, offset: 1))
        let content = try XCTUnwrap(provider.current)
        XCTAssertTrue(content.subtitle.hasPrefix("غداً"))
        XCTAssertTrue(content.text.contains(PrayerFormat.clock(tomorrow.fajr, timeZone: zone)))
        for _ in 0..<10 { provider.goToNext() }
        XCTAssertEqual(provider.dayOffset, PrayerPiPProvider.days - 1)
        XCTAssertTrue(try XCTUnwrap(provider.current).isLast)
    }

    func testFitsOnePageInEveryLayout() throws {
        let now = Date(timeIntervalSince1970: 1_791_537_600)
        let content = try XCTUnwrap(PrayerPiPProvider(schedule: schedule, placeName: "بغداد", now: { now }).current)
        for layout in [PiPLayout.landscape, .portrait] {
            let pagination = CoreTextPiPPaginator(layout: layout).paginate(content.text, style: .standard, withCounter: true)
            XCTAssertEqual(pagination.pages.count, 1, "\(layout): the whole day at once")
        }
    }

    func testRunsInTheEngine() throws {
        let now = Date(timeIntervalSince1970: 1_791_537_600)
        let provider = PrayerPiPProvider(schedule: schedule, placeName: "بغداد", now: { now })
        let engine = PiPEngine(paginator: CoreTextPiPPaginator(), sessionStore: InMemoryPiPSessionStore(),
                               availability: PiPAvailability(backgroundModeDeclared: true, userEnabled: true))
        let pip = StubPiPController()
        engine.register(pip, provider: provider)
        engine.start(provider, on: pip)
        pip.systemStarts()
        XCTAssertEqual(pip.frame?.content.contentType, .prayer)
        engine.skip(by: 15)
        XCTAssertEqual(provider.dayOffset, 1, "skip forward: the next day")
        XCTAssertEqual(pip.frame?.content.contentID, "prayer:1")
        engine.skip(by: -15)
        XCTAssertEqual(provider.dayOffset, 0)
    }

    func testAPlaceChangeRedrawsTheWindow() throws {
        let now = Date(timeIntervalSince1970: 1_791_537_600)
        let provider = PrayerPiPProvider(schedule: schedule, placeName: "بغداد", now: { now })
        var changes = 0
        let subscription = provider.changes.sink { changes += 1 }
        provider.update(schedule: schedule, placeName: "بغداد", twentyFourHour: false)
        XCTAssertEqual(changes, 0, "nothing changed")
        let makkah = PrayerSchedule(coordinates: Qibla.kaaba, timeZone: TimeZone(identifier: "Asia/Riyadh")!,
                                    parameters: PrayerParameters(method: .ummAlQura))
        provider.update(schedule: makkah, placeName: "مكة المكرمة", twentyFourHour: true)
        XCTAssertEqual(changes, 1)
        let content = try XCTUnwrap(provider.current)
        XCTAssertEqual(content.title, "مكة المكرمة")
        let fajr = try XCTUnwrap(makkah.day(containing: now)).fajr
        XCTAssertTrue(content.text.contains(PrayerFormat.clock(fajr, timeZone: makkah.timeZone, twentyFourHour: true)))
        subscription.cancel()
    }
}
