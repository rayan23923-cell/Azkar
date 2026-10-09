import XCTest
@testable import PrayerTimes

final class PrayerTimesTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func minutesFromUTCMidnight(_ date: Date, _ y: Int, _ m: Int, _ d: Int) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let midnight = calendar.date(from: DateComponents(year: y, month: m, day: d))!
        return date.timeIntervalSince(midnight) / 60
    }

    /// Cross-check against an independent formula set (NOAA's solar calculator: fractional-year
    /// Fourier series, iterated at each event's own time), evaluated separately for these
    /// places and dates. Fajr 18° and Isha 17° (Muslim World League), sunrise and sunset at
    /// 0.833°. Minutes after 0h UTC of the date. The two agree within 4 minutes everywhere
    /// (within 2 below 40° latitude), which is the spread between low-precision solar
    /// formulas; timetables round to the minute.
    private let reference: [(String, Double, Double, Int, Int, Int, [Double])] = [
        ("Makkah", 21.4225, 39.8262, 2026, 1, 15, [162, 241, 569, 898, 972]),
        ("Makkah", 21.4225, 39.8262, 2026, 3, 20, [132, 206, 569, 932, 1001]),
        ("Makkah", 21.4225, 39.8262, 2026, 6, 21, [73, 159, 562, 965, 1045]),
        ("Makkah", 21.4225, 39.8262, 2026, 10, 9, [120, 193, 548, 902, 971]),
        ("Baghdad", 33.3152, 44.3661, 2026, 1, 15, [159, 246, 551, 856, 939]),
        ("Baghdad", 33.3152, 44.3661, 2026, 3, 20, [106, 188, 551, 914, 991]),
        ("Baghdad", 33.3152, 44.3661, 2026, 6, 21, [10, 113, 544, 975, 1071]),
        ("Baghdad", 33.3152, 44.3661, 2026, 10, 9, [99, 181, 530, 878, 955]),
        ("London", 51.5074, -0.1278, 2026, 1, 15, [359, 480, 729, 979, 1093]),
        ("London", 51.5074, -0.1278, 2026, 3, 20, [253, 366, 729, 1092, 1199]),
        ("London", 51.5074, -0.1278, 2026, 10, 9, [261, 372, 708, 1042, 1147]),
        ("NewYork", 40.7128, -74.006, 2026, 1, 15, [641, 738, 1025, 1312, 1403]),
        ("NewYork", 40.7128, -74.006, 2026, 3, 20, [570, 661, 1024, 1387, 1474]),
        ("NewYork", 40.7128, -74.006, 2026, 6, 21, [438, 564, 1017, 1470, 1588]),
        ("NewYork", 40.7128, -74.006, 2026, 10, 9, [568, 659, 1003, 1346, 1432]),
        ("Jakarta", -6.2088, 106.8456, 2026, 1, 15, [-147, -72, 301, 675, 745]),
        ("Jakarta", -6.2088, 106.8456, 2026, 3, 20, [-132, -63, 301, 664, 729]),
        ("Jakarta", -6.2088, 106.8456, 2026, 6, 21, [-134, -59, 294, 647, 717]),
        ("Jakarta", -6.2088, 106.8456, 2026, 10, 9, [-156, -86, 280, 646, 711]),
        ("Sydney", -33.8688, 151.2093, 2026, 1, 15, [-403, -302, 124, 549, 643]),
        ("Sydney", -33.8688, 151.2093, 2026, 3, 20, [-326, -242, 123, 489, 567]),
        ("Sydney", -33.8688, 151.2093, 2026, 6, 21, [-270, -181, 116, 413, 498]),
        ("Sydney", -33.8688, 151.2093, 2026, 10, 9, [-362, -277, 102, 482, 562]),
    ]

    func testTimesAgreeWithAnIndependentSolarCalculation() throws {
        for (name, lat, lng, y, m, d, expected) in reference {
            let day = try XCTUnwrap(PrayerCalculator.times(year: y, month: m, day: d,
                                                           at: Coordinates(latitude: lat, longitude: lng)))
            let actual = [day.fajr, day.sunrise, day.dhuhr, day.maghrib, day.isha].map {
                minutesFromUTCMidnight($0, y, m, d)
            }
            let tolerance: Double = abs(lat) < 40 ? 2.5 : 4
            for (index, label) in ["fajr", "sunrise", "dhuhr", "maghrib", "isha"].enumerated() {
                XCTAssertEqual(actual[index], expected[index], accuracy: tolerance, "\(name) \(y)-\(m)-\(d) \(label)")
            }
        }
    }

    func testTheDayIsInOrderAndRoundedToTheMinute() throws {
        for method in CalculationMethod.allCases {
            for asr in AsrSchool.allCases {
                let day = try XCTUnwrap(PrayerCalculator.times(year: 2026, month: 10, day: 9,
                                                               at: Coordinates(latitude: 33.3152, longitude: 44.3661),
                                                               parameters: PrayerParameters(method: method, asr: asr)))
                let times = day.all.map(\.time)
                XCTAssertEqual(times, times.sorted(), "\(method) \(asr)")
                XCTAssertEqual(Set(times).count, 6)
                for time in times { XCTAssertEqual(time.timeIntervalSince1970.truncatingRemainder(dividingBy: 60), 0) }
            }
        }
    }

    func testMethodsDifferAsPublished() throws {
        let baghdad = Coordinates(latitude: 33.3152, longitude: 44.3661)
        func day(_ method: CalculationMethod, _ asr: AsrSchool = .standard) throws -> PrayerDay {
            try XCTUnwrap(PrayerCalculator.times(year: 2026, month: 10, day: 9, at: baghdad,
                                                 parameters: PrayerParameters(method: method, asr: asr)))
        }
        let mwl = try day(.muslimWorldLeague)
        let ummAlQura = try day(.ummAlQura)
        XCTAssertEqual(ummAlQura.isha.timeIntervalSince(ummAlQura.maghrib), 90 * 60, "Isha 90 minutes after Maghrib")
        XCTAssertLessThan(try day(.egyptian).fajr, mwl.fajr, "19.5° is earlier than 18°")
        XCTAssertGreaterThan(try day(.northAmerica).fajr, mwl.fajr, "15° is later than 18°")
        XCTAssertGreaterThan(try day(.muslimWorldLeague, .hanafi).asr, mwl.asr, "Hanafi Asr is later")
        let jafari = try day(.jafari)
        XCTAssertGreaterThan(jafari.maghrib, mwl.maghrib, "Maghrib 4° after sunset")
        XCTAssertEqual(mwl.dhuhr, jafari.dhuhr, "Dhuhr is solar noon for every method")
    }

    func testDhuhrIsSolarNoonAtTheEquinox() throws {
        // At the March equinox noon at longitude 0 is about 12:07 UTC (equation of time −7 min).
        let day = try XCTUnwrap(PrayerCalculator.times(year: 2026, month: 3, day: 20,
                                                       at: Coordinates(latitude: 0, longitude: 0)))
        XCTAssertEqual(minutesFromUTCMidnight(day.dhuhr, 2026, 3, 20), 12 * 60 + 7, accuracy: 1.5)
        XCTAssertEqual(day.maghrib.timeIntervalSince(day.sunrise) / 3600, 12.1, accuracy: 0.1, "about 12 hours of day")
    }

    func testHighLatitudeSummerStillHasFajrAndIsha() throws {
        // London in June: the sun never reaches 18° below the horizon; the angle-based rule
        // places Fajr and Isha within the night.
        let day = try XCTUnwrap(PrayerCalculator.times(year: 2026, month: 6, day: 21,
                                                       at: Coordinates(latitude: 51.5074, longitude: -0.1278)))
        let night = day.sunrise.addingTimeInterval(24 * 3600).timeIntervalSince(day.maghrib)
        XCTAssertLessThan(day.fajr, day.sunrise)
        XCTAssertLessThanOrEqual(day.sunrise.timeIntervalSince(day.fajr), 18.0 / 60 * night + 60)
        XCTAssertGreaterThan(day.isha, day.maghrib)
        XCTAssertLessThanOrEqual(day.isha.timeIntervalSince(day.maghrib), 17.0 / 60 * night + 60)
    }

    func testPolarDayAndBadCoordinatesHaveNoTimes() {
        XCTAssertNil(PrayerCalculator.times(year: 2026, month: 6, day: 21, at: Coordinates(latitude: 78, longitude: 15)))
        XCTAssertNil(PrayerCalculator.times(year: 2026, month: 6, day: 21, at: Coordinates(latitude: 95, longitude: 0)))
    }

    func testCalendarDayFollowsThePlacesTimeZone() throws {
        // 2026-10-09 22:30 UTC is already 10 October in Baghdad (UTC+3).
        let instant = Date(timeIntervalSince1970: 1_791_585_000) // 2026-10-09T22:30:00Z
        let baghdad = Coordinates(latitude: 33.3152, longitude: 44.3661)
        let local = try XCTUnwrap(PrayerCalculator.times(on: instant, at: baghdad,
                                                         timeZone: TimeZone(identifier: "Asia/Baghdad")!))
        let tenth = try XCTUnwrap(PrayerCalculator.times(year: 2026, month: 10, day: 10, at: baghdad))
        XCTAssertEqual(local, tenth)
    }

    // MARK: Qibla

    /// Published Qibla directions (true north): New York 58.5°, London 119.0°, Cairo 136.1°.
    func testQiblaBearing() {
        XCTAssertEqual(Qibla.bearing(from: Coordinates(latitude: 40.7128, longitude: -74.0060)), 58.48, accuracy: 0.05)
        XCTAssertEqual(Qibla.bearing(from: Coordinates(latitude: 51.5074, longitude: -0.1278)), 118.99, accuracy: 0.05)
        XCTAssertEqual(Qibla.bearing(from: Coordinates(latitude: 30.0444, longitude: 31.2357)), 136.14, accuracy: 0.05)
        XCTAssertEqual(Qibla.bearing(from: Coordinates(latitude: 33.3152, longitude: 44.3661)), 199.82, accuracy: 0.05)
        XCTAssertEqual(Qibla.bearing(from: Coordinates(latitude: -6.2088, longitude: 106.8456)), 295.15, accuracy: 0.05)
        XCTAssertEqual(Qibla.distance(from: Coordinates(latitude: 33.3152, longitude: 44.3661)), 1396, accuracy: 2)
        XCTAssertEqual(Qibla.distance(from: Qibla.kaaba), 0, accuracy: 0.001)
    }

    func testTurnAndCompassPoint() {
        XCTAssertEqual(Qibla.turn(bearing: 200, heading: 180), 20)
        XCTAssertEqual(Qibla.turn(bearing: 10, heading: 350), 20, "across north")
        XCTAssertEqual(Qibla.turn(bearing: 350, heading: 10), -20)
        XCTAssertEqual(Qibla.turn(bearing: 180, heading: 0), 180)
        XCTAssertEqual(Qibla.compassPoint(199.8), "الجنوب")
        XCTAssertEqual(Qibla.compassPoint(58.5), "الشمال الشرقي")
        XCTAssertEqual(Qibla.compassPoint(359), "الشمال")
    }

    // MARK: Schedule and format

    func testNextAndCurrentPrayer() throws {
        let zone = TimeZone(identifier: "Asia/Baghdad")!
        let schedule = PrayerSchedule(coordinates: Coordinates(latitude: 33.3152, longitude: 44.3661), timeZone: zone,
                                      parameters: PrayerParameters())
        let today = try XCTUnwrap(schedule.day(containing: Date(timeIntervalSince1970: 1_791_537_600)))
        let afterAsr = today.asr.addingTimeInterval(60)
        XCTAssertEqual(schedule.next(after: afterAsr)?.prayer, .maghrib)
        XCTAssertEqual(schedule.current(at: afterAsr), .asr)
        XCTAssertNil(schedule.current(at: today.sunrise.addingTimeInterval(60)), "between sunrise and Dhuhr")
        XCTAssertEqual(schedule.next(after: today.sunrise)?.prayer, .dhuhr, "sunrise is not a prayer")
        let afterIsha = today.isha.addingTimeInterval(60)
        let next = try XCTUnwrap(schedule.next(after: afterIsha))
        XCTAssertEqual(next.prayer, .fajr)
        XCTAssertEqual(next.time, schedule.day(containing: afterIsha, offset: 1)?.fajr, "tomorrow's Fajr")
    }

    func testFormat() {
        let zone = TimeZone(identifier: "Asia/Baghdad")!
        let date = Date(timeIntervalSince1970: 1_791_537_600) // 2026-10-09 09:20 UTC = 12:20 Baghdad
        XCTAssertEqual(PrayerFormat.clock(date, timeZone: zone), "12:20 م")
        XCTAssertEqual(PrayerFormat.clock(date.addingTimeInterval(-6 * 3600), timeZone: zone), "6:20 ص")
        XCTAssertEqual(PrayerFormat.clock(date, timeZone: zone, twentyFourHour: true), "12:20")
        XCTAssertEqual(PrayerFormat.remaining(from: date, to: date.addingTimeInterval(65 * 60)), "بعد 1:05")
        XCTAssertEqual(PrayerFormat.remaining(from: date, to: date.addingTimeInterval(5 * 60)), "بعد 5 دقائق")
        XCTAssertEqual(PrayerFormat.remaining(from: date, to: date.addingTimeInterval(20 * 60)), "بعد 20 دقيقة")
        XCTAssertEqual(PrayerFormat.remaining(from: date, to: date), "الآن")
        XCTAssertEqual(PrayerFormat.remaining(from: date, to: date.addingTimeInterval(30)), "بعد دقيقة")
        XCTAssertEqual(PrayerFormat.remaining(from: date, to: date.addingTimeInterval(2 * 60)), "بعد دقيقتين")
        XCTAssertEqual(PrayerFormat.remaining(from: date, to: date.addingTimeInterval(60 * 60)), "بعد 1:00")
        XCTAssertEqual(PrayerFormat.gregorian(date, timeZone: zone), "الجمعة 9 أكتوبر")
        XCTAssertTrue(PrayerFormat.hijri(date, timeZone: zone).hasSuffix("1448 هـ"))
    }

    func testSettingsStore() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "prayer.test"))
        defaults.removePersistentDomain(forName: "prayer.test")
        let store = PrayerSettingsStore(defaults: defaults)
        XCTAssertNil(store.place)
        XCTAssertNil(store.schedule)
        XCTAssertEqual(store.parameters, PrayerParameters(method: .muslimWorldLeague, asr: .standard), "defaults")
        let baghdad = try XCTUnwrap(PrayerCities.all.first { $0.name == "بغداد" })
        store.place = baghdad
        store.parameters = PrayerParameters(method: .ummAlQura, asr: .hanafi)
        let reopened = PrayerSettingsStore(defaults: defaults)
        XCTAssertEqual(reopened.place, baghdad)
        XCTAssertEqual(reopened.parameters.method, .ummAlQura)
        XCTAssertEqual(reopened.schedule?.timeZone.identifier, "Asia/Baghdad")
        defaults.removePersistentDomain(forName: "prayer.test")
    }

    func testManualCorrectionsMoveEachTimeByWholeMinutes() throws {
        let baghdad = Coordinates(latitude: 33.3152, longitude: 44.3661)
        let plain = try XCTUnwrap(PrayerCalculator.times(year: 2026, month: 10, day: 9, at: baghdad))
        let corrected = try XCTUnwrap(PrayerCalculator.times(
            year: 2026, month: 10, day: 9, at: baghdad,
            parameters: PrayerParameters(adjustments: [.fajr: 2, .isha: -3, .dhuhr: 0])))
        XCTAssertEqual(corrected.fajr.timeIntervalSince(plain.fajr), 120)
        XCTAssertEqual(corrected.isha.timeIntervalSince(plain.isha), -180)
        for prayer in [Prayer.sunrise, .dhuhr, .asr, .maghrib] {
            XCTAssertEqual(corrected.time(of: prayer), plain.time(of: prayer), "\(prayer) not moved")
        }
        var parameters = PrayerParameters(adjustments: [.asr: 99, .maghrib: -99, .dhuhr: 0])
        XCTAssertEqual(parameters.adjustments, [.asr: 30, .maghrib: -30], "kept within ±30, zeros dropped")
        parameters.adjustments[.fajr] = 45
        XCTAssertEqual(parameters.adjustment(for: .fajr), 30)
        parameters.adjustments[.fajr] = 0
        XCTAssertNil(parameters.adjustments[.fajr])
    }

    func testCorrectionsAreSaved() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "prayer.adjust.test"))
        defaults.removePersistentDomain(forName: "prayer.adjust.test")
        let store = PrayerSettingsStore(defaults: defaults)
        store.parameters = PrayerParameters(method: .egyptian, adjustments: [.fajr: -2, .isha: 5])
        XCTAssertEqual(PrayerSettingsStore(defaults: defaults).parameters.adjustments, [.fajr: -2, .isha: 5])
        store.parameters = PrayerParameters(method: .egyptian)
        XCTAssertNil(defaults.object(forKey: PrayerSettingsStore.adjustmentsKey))
        defaults.set(["fajr": 4, "unknown": 9], forKey: PrayerSettingsStore.adjustmentsKey)
        XCTAssertEqual(store.parameters.adjustments, [.fajr: 4], "unknown names are ignored")
        defaults.removePersistentDomain(forName: "prayer.adjust.test")
    }

    func testEveryCityHasValidCoordinatesAndTimeZone() {
        for city in PrayerCities.all {
            XCTAssertTrue(city.coordinates.isValid, city.name)
            XCTAssertNotNil(TimeZone(identifier: city.timeZoneID ?? ""), city.name)
            XCTAssertNotNil(PrayerCalculator.times(year: 2026, month: 10, day: 9, at: city.coordinates), city.name)
        }
        XCTAssertEqual(Set(PrayerCities.all.map(\.name)).count, PrayerCities.all.count)
    }
}
