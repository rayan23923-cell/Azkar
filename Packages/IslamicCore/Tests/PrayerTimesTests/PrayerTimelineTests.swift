import XCTest
@testable import PrayerTimes

final class PrayerTimelineTests: XCTestCase {
    private let baghdad = Coordinates(latitude: 33.3152, longitude: 44.3661)
    private let london = Coordinates(latitude: 51.5074, longitude: -0.1278)
    /// 2026-10-09 09:20 UTC.
    private let morning = Date(timeIntervalSince1970: 1_791_537_600)

    private func schedule(_ coordinates: Coordinates, _ zone: String) -> PrayerSchedule {
        PrayerSchedule(coordinates: coordinates, timeZone: TimeZone(identifier: zone)!, parameters: PrayerParameters())
    }

    func testMomentsFollowEveryChangeInOrder() throws {
        let schedule = schedule(baghdad, "Asia/Baghdad")
        let moments = schedule.moments(from: morning)
        XCTAssertEqual(moments.first?.date, morning)
        XCTAssertEqual(moments.count, 16)
        for (earlier, later) in zip(moments, moments.dropFirst()) {
            XCTAssertLessThan(earlier.date, later.date)
        }
        for moment in moments {
            XCTAssertGreaterThan(moment.nextTime, moment.date, "the next prayer is always ahead")
            XCTAssertEqual(moment.next, schedule.next(after: moment.date)?.prayer)
            XCTAssertEqual(moment.current, schedule.current(at: moment.date))
            XCTAssertEqual(moment.day, schedule.day(containing: moment.date))
        }
        // Each prayer time is a moment, so the widget moves on as soon as a time comes.
        let today = try XCTUnwrap(schedule.day(containing: morning))
        let dates = Set(moments.map(\.date))
        for time in [today.asr, today.maghrib, today.isha] { XCTAssertTrue(dates.contains(time)) }
        XCTAssertGreaterThan(moments.last!.date, today.isha.addingTimeInterval(6 * 3600), "covers the night")
    }

    func testTheDayTurnsAtTheLocalMidnight() throws {
        let schedule = schedule(baghdad, "Asia/Baghdad")
        let moments = schedule.moments(from: morning)
        // Midnight in Baghdad (UTC+3) is 21:00 UTC: the list switches to the 10th then.
        let midnight = Date(timeIntervalSince1970: 1_791_579_600) // 2026-10-09T21:00:00Z
        let atMidnight = try XCTUnwrap(moments.first { $0.date == midnight })
        XCTAssertEqual(atMidnight.day, PrayerCalculator.times(year: 2026, month: 10, day: 10, at: baghdad))
        XCTAssertEqual(atMidnight.next, .fajr)
        XCTAssertEqual(atMidnight.current, .isha, "Isha's time lasts until Fajr")
        let before = try XCTUnwrap(moments.last { $0.date < midnight })
        XCTAssertEqual(before.day, PrayerCalculator.times(year: 2026, month: 10, day: 9, at: baghdad))
    }

    func testAcrossDaylightSavingChanges() throws {
        let schedule = schedule(london, "Europe/London")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = schedule.timeZone
        // Clocks go forward on 2026-03-29 and back on 2026-10-25 in London.
        for (month, day) in [(3, 29), (10, 25), (3, 28), (10, 24)] {
            let noon = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
            let times = try XCTUnwrap(schedule.day(containing: noon))
            let order = Prayer.allCases.map { times.time(of: $0) }
            XCTAssertEqual(order, order.sorted(), "\(month)/\(day) in order")
            XCTAssertTrue(calendar.isDate(times.fajr, inSameDayAs: noon))
            XCTAssertTrue(calendar.isDate(times.isha, inSameDayAs: noon))
            // Dhuhr is just after solar noon, within half an hour of 12:00 GMT whatever the
            // clocks say, and the local clock shows it an hour later on summer-time days.
            var utc = Calendar(identifier: .gregorian)
            utc.timeZone = TimeZone(identifier: "UTC")!
            let gmt = utc.dateComponents([.hour, .minute], from: times.dhuhr)
            XCTAssertTrue((690...750).contains(gmt.hour! * 60 + gmt.minute!), "\(month)/\(day)")
            let summer = schedule.timeZone.isDaylightSavingTime(for: times.dhuhr)
            XCTAssertEqual(calendar.component(.hour, from: times.dhuhr), gmt.hour! + (summer ? 1 : 0), "\(month)/\(day)")
        }
        // Moments through the night the clocks change stay in order and never repeat.
        let eve = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 20))!
        let moments = schedule.moments(from: eve, limit: 12)
        for (earlier, later) in zip(moments, moments.dropFirst()) { XCTAssertLessThan(earlier.date, later.date) }
        XCTAssertTrue(moments.contains { calendar.isDate($0.date, inSameDayAs: eve.addingTimeInterval(86_400)) && $0.next == .dhuhr })
    }

    func testNoMomentsWhereTheSunDoesNotSet() {
        let polar = PrayerSchedule(coordinates: Coordinates(latitude: 78, longitude: 15),
                                   timeZone: TimeZone(identifier: "Arctic/Longyearbyen")!, parameters: PrayerParameters())
        let midsummer = Date(timeIntervalSince1970: 1_782_043_200) // 2026-06-21T12:00:00Z
        XCTAssertEqual(polar.moments(from: midsummer), [], "the widget then asks to open the app")
    }

    // MARK: Saved place

    func testAPlaceInAnotherTimeZoneIsPointedOut() throws {
        let riyadh = TimeZone(identifier: "Asia/Riyadh")!
        let mosul = try XCTUnwrap(PrayerCities.all.first { $0.name == "الموصل" })
        XCTAssertNil(PrayerPlaceNotice.check(mosul, deviceTimeZone: TimeZone(identifier: "Asia/Baghdad")!, at: morning))
        XCTAssertNil(PrayerPlaceNotice.check(mosul, deviceTimeZone: riyadh, at: morning), "same clock, different zone")
        XCTAssertEqual(PrayerPlaceNotice.check(mosul, deviceTimeZone: TimeZone(identifier: "Europe/London")!, at: morning),
                       .cityInOtherTimeZone)

        let here = PrayerPlace(name: "موقعي الحالي", coordinates: baghdad, timeZoneID: "Asia/Baghdad", isCurrentLocation: true)
        XCTAssertNil(PrayerPlaceNotice.check(here, deviceTimeZone: TimeZone(identifier: "Asia/Baghdad")!, at: morning))
        XCTAssertEqual(PrayerPlaceNotice.check(here, deviceTimeZone: TimeZone(identifier: "Asia/Dubai")!, at: morning),
                       .locationMayBeOld)

        let noZone = PrayerPlace(name: "x", coordinates: baghdad, timeZoneID: nil, isCurrentLocation: true)
        XCTAssertNil(PrayerPlaceNotice.check(noZone, deviceTimeZone: TimeZone(identifier: "Asia/Dubai")!, at: morning),
                     "a place without a zone follows the device")
    }

    func testOffsetsAreComparedOnTheDayItself() {
        // London and Lisbon share the clock all year, summer time included.
        let london = PrayerPlace(name: "لندن", coordinates: self.london, timeZoneID: "Europe/London", isCurrentLocation: false)
        let lisbon = TimeZone(identifier: "Europe/Lisbon")!
        let july = Date(timeIntervalSince1970: 1_783_944_000) // 2026-07-13
        XCTAssertNil(PrayerPlaceNotice.check(london, deviceTimeZone: lisbon, at: july))
        XCTAssertNil(PrayerPlaceNotice.check(london, deviceTimeZone: lisbon, at: morning))
    }
}
