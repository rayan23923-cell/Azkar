import Foundation

/// A place on Earth, in degrees (north and east positive).
public struct Coordinates: Equatable, Codable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude) && latitude.isFinite && longitude.isFinite
    }
}

/// The five prayers and sunrise, in the day's order.
public enum Prayer: String, CaseIterable, Codable, Sendable {
    case fajr, sunrise, dhuhr, asr, maghrib, isha

    public var arabicName: String {
        switch self {
        case .fajr: return "الفجر"
        case .sunrise: return "الشروق"
        case .dhuhr: return "الظهر"
        case .asr: return "العصر"
        case .maghrib: return "المغرب"
        case .isha: return "العشاء"
        }
    }

    /// Sunrise is shown with the times but is not a prayer.
    public var isPrayer: Bool { self != .sunrise }
}

/// How the twilight prayers are reckoned: the sun's depression angle below the horizon for Fajr
/// and Isha (or a fixed interval after Maghrib for Isha), as the calculation authorities publish
/// them.
public enum CalculationMethod: String, CaseIterable, Codable, Sendable {
    /// Muslim World League: Fajr 18°, Isha 17°.
    case muslimWorldLeague
    /// Umm al-Qura, Makkah: Fajr 18.5°, Isha 90 minutes after Maghrib.
    case ummAlQura
    /// Egyptian General Authority of Survey: Fajr 19.5°, Isha 17.5°.
    case egyptian
    /// University of Islamic Sciences, Karachi: Fajr 18°, Isha 18°.
    case karachi
    /// Islamic Society of North America: Fajr 15°, Isha 15°.
    case northAmerica
    /// Institute of Geophysics, University of Tehran: Fajr 17.7°, Isha 14°, Maghrib 4.5°.
    case tehran
    /// Shia Ithna Ashari, Leva Institute, Qum: Fajr 16°, Isha 14°, Maghrib 4°.
    case jafari

    public var arabicName: String {
        switch self {
        case .muslimWorldLeague: return "رابطة العالم الإسلامي"
        case .ummAlQura: return "أم القرى (مكة المكرمة)"
        case .egyptian: return "الهيئة المصرية العامة للمساحة"
        case .karachi: return "جامعة العلوم الإسلامية، كراتشي"
        case .northAmerica: return "الجمعية الإسلامية لأمريكا الشمالية"
        case .tehran: return "معهد الجيوفيزياء، جامعة طهران"
        case .jafari: return "الشيعة الإثنا عشرية (مؤسسة ليفا، قم)"
        }
    }

    var fajrAngle: Double {
        switch self {
        case .muslimWorldLeague, .karachi: return 18
        case .ummAlQura: return 18.5
        case .egyptian: return 19.5
        case .northAmerica: return 15
        case .tehran: return 17.7
        case .jafari: return 16
        }
    }

    enum Isha: Equatable {
        case angle(Double)
        case minutesAfterMaghrib(Double)
    }

    var isha: Isha {
        switch self {
        case .muslimWorldLeague: return .angle(17)
        case .ummAlQura: return .minutesAfterMaghrib(90)
        case .egyptian: return .angle(17.5)
        case .karachi: return .angle(18)
        case .northAmerica: return .angle(15)
        case .tehran, .jafari: return .angle(14)
        }
    }

    /// Maghrib as a depression angle (after sunset); nil: Maghrib is sunset.
    var maghribAngle: Double? {
        switch self {
        case .tehran: return 4.5
        case .jafari: return 4
        default: return nil
        }
    }
}

/// When Asr begins: an object's shadow equals its length (plus the noon shadow), or twice it.
public enum AsrSchool: String, CaseIterable, Codable, Sendable {
    /// Shafi'i, Maliki, Hanbali.
    case standard
    case hanafi

    public var arabicName: String {
        switch self {
        case .standard: return "الجمهور (الشافعي والمالكي والحنبلي)"
        case .hanafi: return "الحنفي"
        }
    }

    var shadowFactor: Double { self == .standard ? 1 : 2 }
}

/// The calculation settings.
public struct PrayerParameters: Equatable, Codable, Sendable {
    /// The largest manual correction, in minutes either way.
    public static let adjustmentRange = -30...30

    public var method: CalculationMethod
    public var asr: AsrSchool
    /// Minutes added to each computed time (negative: earlier), to match a local timetable.
    /// Missing prayers are not moved; values are kept within `adjustmentRange`.
    public var adjustments: [Prayer: Int] {
        didSet { adjustments = Self.clamped(adjustments) }
    }

    public init(method: CalculationMethod = .muslimWorldLeague, asr: AsrSchool = .standard,
                adjustments: [Prayer: Int] = [:]) {
        self.method = method
        self.asr = asr
        self.adjustments = Self.clamped(adjustments)
    }

    public func adjustment(for prayer: Prayer) -> Int { adjustments[prayer] ?? 0 }

    static func clamped(_ adjustments: [Prayer: Int]) -> [Prayer: Int] {
        adjustments.compactMapValues { minutes in
            let value = min(max(minutes, adjustmentRange.lowerBound), adjustmentRange.upperBound)
            return value == 0 ? nil : value
        }
    }
}

/// One day's times, as instants (each rounded to the minute).
public struct PrayerDay: Equatable, Sendable {
    public let fajr: Date
    public let sunrise: Date
    public let dhuhr: Date
    public let asr: Date
    public let maghrib: Date
    public let isha: Date

    public func time(of prayer: Prayer) -> Date {
        switch prayer {
        case .fajr: return fajr
        case .sunrise: return sunrise
        case .dhuhr: return dhuhr
        case .asr: return asr
        case .maghrib: return maghrib
        case .isha: return isha
        }
    }

    public var all: [(prayer: Prayer, time: Date)] { Prayer.allCases.map { ($0, time(of: $0)) } }
}

/// Prayer times from the sun's position, computed on the device.
///
/// The sun's declination and the equation of time come from the standard low-precision solar
/// formulas (Astronomical Almanac), good to about a minute for the years an app is used in.
/// Each time is the moment the sun reaches the method's angle; Asr uses the shadow ratio; Dhuhr
/// is solar noon. Sunrise and sunset use 0.833° (refraction and the sun's radius), at sea level.
///
/// Where the twilight angle is never reached or comes too late (high latitudes in summer), Fajr
/// and Isha follow the angle-based rule: at most angle/60 of the night from sunrise / sunset.
public enum PrayerCalculator {
    /// The times for the calendar day `date` falls on in `timeZone`; nil where the sun does not
    /// rise or set that day (polar day or night) or the coordinates are invalid.
    public static func times(on date: Date, at coordinates: Coordinates, timeZone: TimeZone,
                             parameters: PrayerParameters = PrayerParameters()) -> PrayerDay? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return times(year: parts.year!, month: parts.month!, day: parts.day!, at: coordinates,
                     parameters: parameters)
    }

    /// The times for a calendar day (the date where the place is).
    public static func times(year: Int, month: Int, day: Int, at coordinates: Coordinates,
                             parameters: PrayerParameters = PrayerParameters()) -> PrayerDay? {
        guard coordinates.isValid else { return nil }
        let lat = coordinates.latitude
        let lng = coordinates.longitude
        // Julian day at 0h UT of the date, moved to local noon's longitude as a first estimate.
        let jd = julianDay(year: year, month: month, day: day) - lng / (15 * 24)
        let method = parameters.method

        // Hours of local apparent time; refined twice from rough first guesses.
        var t = (fajr: 5.0, sunrise: 6.0, dhuhr: 12.0, asr: 13.0, sunset: 18.0, maghrib: 18.0, isha: 18.0)
        for _ in 0..<2 {
            let portion = (fajr: t.fajr / 24, sunrise: t.sunrise / 24, dhuhr: t.dhuhr / 24, asr: t.asr / 24,
                           sunset: t.sunset / 24, maghrib: t.maghrib / 24, isha: t.isha / 24)
            t.fajr = sunAngleTime(method.fajrAngle, jd: jd, dayPortion: portion.fajr, latitude: lat, beforeNoon: true)
            t.sunrise = sunAngleTime(riseSetAngle, jd: jd, dayPortion: portion.sunrise, latitude: lat, beforeNoon: true)
            t.dhuhr = solarNoon(jd: jd, dayPortion: portion.dhuhr)
            t.asr = asrTime(parameters.asr.shadowFactor, jd: jd, dayPortion: portion.asr, latitude: lat)
            t.sunset = sunAngleTime(riseSetAngle, jd: jd, dayPortion: portion.sunset, latitude: lat, beforeNoon: false)
            t.maghrib = method.maghribAngle.map {
                sunAngleTime($0, jd: jd, dayPortion: portion.maghrib, latitude: lat, beforeNoon: false)
            } ?? t.sunset
            if case .angle(let angle) = method.isha {
                t.isha = sunAngleTime(angle, jd: jd, dayPortion: portion.isha, latitude: lat, beforeNoon: false)
            }
        }
        if case .minutesAfterMaghrib(let minutes) = method.isha { t.isha = t.maghrib + minutes / 60 }

        // High latitudes: no later than the angle-based share of the night.
        let night = 24 - (t.sunset - t.sunrise)
        if night.isFinite {
            func limit(_ time: Double, base: Double, angle: Double, before: Bool) -> Double {
                let share = angle / 60 * night
                let gap = before ? base - time : time - base
                return time.isNaN || gap > share ? (before ? base - share : base + share) : time
            }
            t.fajr = limit(t.fajr, base: t.sunrise, angle: method.fajrAngle, before: true)
            if case .angle(let angle) = method.isha {
                t.isha = limit(t.isha, base: t.sunset, angle: angle, before: false)
            }
            if let angle = method.maghribAngle {
                t.maghrib = limit(t.maghrib, base: t.sunset, angle: angle, before: false)
            }
        }

        let all = [t.fajr, t.sunrise, t.dhuhr, t.asr, t.sunset, t.maghrib, t.isha]
        guard all.allSatisfy(\.isFinite) else { return nil }

        // Local apparent hours to UTC hours of the date, then instants.
        let shift = -lng / 15
        let midnightUTC = utcMidnight(year: year, month: month, day: day)
        func instant(_ hours: Double) -> Date {
            let seconds = ((hours + shift) * 3600).rounded()
            // Rounded to the nearest minute, as timetables print them.
            let date = midnightUTC.addingTimeInterval(seconds)
            return Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
        }
        // The user's corrections, after rounding, so a +2 is exactly two minutes later.
        func adjusted(_ hours: Double, _ prayer: Prayer) -> Date {
            instant(hours).addingTimeInterval(Double(parameters.adjustment(for: prayer)) * 60)
        }
        return PrayerDay(fajr: adjusted(t.fajr, .fajr), sunrise: adjusted(t.sunrise, .sunrise),
                         dhuhr: adjusted(t.dhuhr, .dhuhr), asr: adjusted(t.asr, .asr),
                         maghrib: adjusted(t.maghrib, .maghrib), isha: adjusted(t.isha, .isha))
    }

    // MARK: Sun

    static let riseSetAngle = 0.833

    static func julianDay(year: Int, month: Int, day: Int) -> Double {
        var y = year
        var m = month
        if m <= 2 { y -= 1; m += 12 }
        let a = (Double(y) / 100).rounded(.down)
        let b = 2 - a + (a / 4).rounded(.down)
        return (365.25 * Double(y + 4716)).rounded(.down) + (30.6001 * Double(m + 1)).rounded(.down)
            + Double(day) + b - 1524.5
    }

    /// Declination (degrees) and equation of time (hours) for a Julian day.
    static func sunPosition(_ jd: Double) -> (declination: Double, equation: Double) {
        let d = jd - 2451545.0
        let g = fixAngle(357.529 + 0.98560028 * d)
        let q = fixAngle(280.459 + 0.98564736 * d)
        let l = fixAngle(q + 1.915 * sin(g * .pi / 180) + 0.020 * sin(2 * g * .pi / 180))
        let e = 23.439 - 0.00000036 * d
        let ra = fixHour(atan2(cos(e * .pi / 180) * sin(l * .pi / 180), cos(l * .pi / 180)) * 180 / .pi / 15)
        let equation = q / 15 - ra
        let declination = asin(sin(e * .pi / 180) * sin(l * .pi / 180)) * 180 / .pi
        return (declination, equation)
    }

    static func solarNoon(jd: Double, dayPortion: Double) -> Double {
        fixHour(12 - sunPosition(jd + dayPortion).equation)
    }

    /// When the sun is `angle` degrees below the horizon, before or after noon (NaN if never).
    static func sunAngleTime(_ angle: Double, jd: Double, dayPortion: Double, latitude: Double,
                             beforeNoon: Bool) -> Double {
        let declination = sunPosition(jd + dayPortion).declination * .pi / 180
        let lat = latitude * .pi / 180
        let noon = solarNoon(jd: jd, dayPortion: dayPortion)
        let cosine = (-sin(angle * .pi / 180) - sin(declination) * sin(lat)) / (cos(declination) * cos(lat))
        guard (-1...1).contains(cosine) else { return .nan }
        let hours = acos(cosine) * 180 / .pi / 15
        return noon + (beforeNoon ? -hours : hours)
    }

    /// When an object's shadow is `factor` times its length plus its noon shadow.
    static func asrTime(_ factor: Double, jd: Double, dayPortion: Double, latitude: Double) -> Double {
        let declination = sunPosition(jd + dayPortion).declination
        let altitude = atan(1 / (factor + tan(abs(latitude - declination) * .pi / 180))) * 180 / .pi
        return sunAngleTime(-altitude, jd: jd, dayPortion: dayPortion, latitude: latitude, beforeNoon: false)
    }

    static func fixAngle(_ a: Double) -> Double { let r = a.truncatingRemainder(dividingBy: 360); return r < 0 ? r + 360 : r }
    static func fixHour(_ h: Double) -> Double { let r = h.truncatingRemainder(dividingBy: 24); return r < 0 ? r + 24 : r }

    private static func utcMidnight(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
