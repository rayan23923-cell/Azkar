import XCTest
@testable import PrayerTimes

final class PrayerAlertTests: XCTestCase {
    private let baghdad = Coordinates(latitude: 33.3152, longitude: 44.3661)
    /// 2026-10-09 09:20 UTC (12:20 in Baghdad, after Dhuhr).
    private let morning = Date(timeIntervalSince1970: 1_791_537_600)

    private var schedule: PrayerSchedule {
        PrayerSchedule(coordinates: baghdad, timeZone: TimeZone(identifier: "Asia/Baghdad")!, parameters: PrayerParameters())
    }

    func testNothingIsPlannedUntilAPrayerIsTurnedOn() {
        XCTAssertTrue(PrayerAlertPlanner.requests(schedule: schedule, settings: PrayerAlertSettings(),
                                                  placeName: "بغداد", from: morning).isEmpty)
    }

    func testSunriseIsNeverAnAlert() {
        var settings = PrayerAlertSettings(prayers: [.sunrise, .fajr])
        XCTAssertEqual(settings.prayers, [.fajr])
        settings.set(.sunrise, enabled: true)
        XCTAssertFalse(settings.isEnabled(.sunrise))
        XCTAssertEqual(PrayerAlertSettings.all.prayers.count, 5)
    }

    func testAlertsAreAtEachPrayerTimeFromNowOn() throws {
        let requests = PrayerAlertPlanner.requests(schedule: schedule, settings: .all, placeName: "بغداد", from: morning)
        XCTAssertEqual(requests.count, PrayerAlertPlanner.maximumRequests)
        XCTAssertLessThanOrEqual(PrayerAlertPlanner.maximumRequests + 2, 64, "fits beside the adhkar reminders")
        XCTAssertEqual(Set(requests.map(\.identifier)).count, requests.count, "identifiers are unique")
        for (earlier, later) in zip(requests, requests.dropFirst()) { XCTAssertLessThan(earlier.date, later.date) }
        for request in requests {
            XCTAssertGreaterThan(request.date, morning)
            XCTAssertTrue(request.identifier.hasPrefix(PrayerAlertPlanner.identifierPrefix))
            XCTAssertNotEqual(request.prayer, .sunrise)
        }
        let today = try XCTUnwrap(schedule.day(containing: morning))
        let first = try XCTUnwrap(requests.first)
        XCTAssertEqual(first.date, schedule.next(after: morning)?.time)
        XCTAssertTrue(requests.contains { $0.date == today.isha && $0.prayer == .isha })
        XCTAssertEqual(requests.first { $0.prayer == .asr }?.body, "حان الآن وقت صلاة العصر في بغداد")
        XCTAssertEqual(requests.first { $0.date == today.asr }?.identifier, "azkar.adhan.20261009.asr")
    }

    func testOnlyTheChosenPrayers() {
        let requests = PrayerAlertPlanner.requests(schedule: schedule, settings: PrayerAlertSettings(prayers: [.fajr]),
                                                   placeName: "بغداد", from: morning, limit: 5)
        XCTAssertEqual(requests.count, 5)
        XCTAssertTrue(requests.allSatisfy { $0.prayer == .fajr })
    }

    func testCorrectionsMoveTheAlerts() throws {
        let corrected = PrayerSchedule(coordinates: baghdad, timeZone: TimeZone(identifier: "Asia/Baghdad")!,
                                       parameters: PrayerParameters(adjustments: [.isha: 5]))
        let plain = PrayerAlertPlanner.requests(schedule: schedule, settings: PrayerAlertSettings(prayers: [.isha]),
                                                placeName: "بغداد", from: morning, limit: 1)
        let moved = PrayerAlertPlanner.requests(schedule: corrected, settings: PrayerAlertSettings(prayers: [.isha]),
                                                placeName: "بغداد", from: morning, limit: 1)
        let a = try XCTUnwrap(plain.first), b = try XCTUnwrap(moved.first)
        XCTAssertEqual(b.date.timeIntervalSince(a.date), 300, accuracy: 1)
    }

    func testStoreReadsNothingUnreadableAsNone() {
        let defaults = UserDefaults(suiteName: "PrayerAlertTests")!
        defaults.removePersistentDomain(forName: "PrayerAlertTests")
        let store = PrayerAlertStore(defaults: defaults)
        XCTAssertFalse(store.settings.anyEnabled)
        store.settings = PrayerAlertSettings(prayers: [.dhuhr, .maghrib])
        XCTAssertEqual(store.settings.prayers, [.dhuhr, .maghrib])
        defaults.set("garbage", forKey: PrayerAlertStore.key)
        XCTAssertFalse(store.settings.anyEnabled)
    }

    func testJustEnteredShowsTheAdhanForAWhile() throws {
        let today = try XCTUnwrap(schedule.day(containing: morning))
        let atAsr = schedule.justEntered(at: today.asr)
        XCTAssertEqual(atAsr?.prayer, .asr)
        XCTAssertEqual(schedule.justEntered(at: today.asr.addingTimeInterval(10 * 60))?.prayer, .asr)
        XCTAssertNil(schedule.justEntered(at: today.asr.addingTimeInterval(16 * 60)))
        XCTAssertNil(schedule.justEntered(at: today.asr.addingTimeInterval(-1)), "not before its time")
        XCTAssertNil(schedule.justEntered(at: today.sunrise.addingTimeInterval(60)), "sunrise is not a prayer")
    }
}

final class PrayerCountdownTests: XCTestCase {
    func testCountdownReadsLikeATimer() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(PrayerFormat.countdown(from: now, to: now.addingTimeInterval(3909)), "1:05:09")
        XCTAssertEqual(PrayerFormat.countdown(from: now, to: now.addingTimeInterval(760)), "12:40")
        XCTAssertEqual(PrayerFormat.countdown(from: now, to: now.addingTimeInterval(0.4)), "0:01")
        XCTAssertEqual(PrayerFormat.countdown(from: now, to: now), "0:00")
        XCTAssertEqual(PrayerFormat.countdown(from: now, to: now.addingTimeInterval(-5)), "0:00")
    }
}
