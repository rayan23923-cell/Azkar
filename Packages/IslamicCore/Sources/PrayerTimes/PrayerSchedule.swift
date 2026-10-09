import Foundation

/// Today's (or any day's) times for a place, and what comes next.
public struct PrayerSchedule: Equatable, Sendable {
    public let coordinates: Coordinates
    public let timeZone: TimeZone
    public let parameters: PrayerParameters

    public init(coordinates: Coordinates, timeZone: TimeZone, parameters: PrayerParameters) {
        self.coordinates = coordinates
        self.timeZone = timeZone
        self.parameters = parameters
    }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The times of the day `date` falls on, `offset` days later (or earlier).
    public func day(containing date: Date, offset: Int = 0) -> PrayerDay? {
        guard let shifted = calendar.date(byAdding: .day, value: offset, to: date) else { return nil }
        return PrayerCalculator.times(on: shifted, at: coordinates, timeZone: timeZone, parameters: parameters)
    }

    /// The first prayer (sunrise excluded) after `date`: later today, or tomorrow's Fajr.
    public func next(after date: Date) -> (prayer: Prayer, time: Date)? {
        for offset in 0...1 {
            guard let day = day(containing: date, offset: offset) else { continue }
            if let next = day.all.first(where: { $0.prayer.isPrayer && $0.time > date }) { return next }
        }
        return nil
    }

    /// The prayer whose time has come and not yet passed to the next (sunrise ends Fajr's
    /// time); nil between sunrise and Dhuhr.
    public func current(at date: Date) -> Prayer? {
        guard let today = day(containing: date) else { return nil }
        if date < today.fajr { return .isha }
        if date < today.sunrise { return .fajr }
        if date < today.dhuhr { return nil }
        if date < today.asr { return .dhuhr }
        if date < today.maghrib { return .asr }
        if date < today.isha { return .maghrib }
        return .isha
    }
}

/// How times and the time left are written: Western digits, as the rest of the app.
public enum PrayerFormat {
    /// «4:52 ص» or «16:52».
    public static func clock(_ date: Date, timeZone: TimeZone, twentyFourHour: Bool = false) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = String(format: "%02d", parts.minute ?? 0)
        if twentyFourHour { return "\(hour):\(minute)" }
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return "\(twelve):\(minute) \(hour < 12 ? "ص" : "م")"
    }

    /// «بعد 1:05» (hours and minutes), «بعد 12 دقيقة», «بعد دقيقتين»; «الآن» once the time comes.
    public static func remaining(from now: Date, to time: Date) -> String {
        let minutes = Int((time.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "الآن" }
        if minutes == 1 { return "بعد دقيقة" }
        if minutes == 2 { return "بعد دقيقتين" }
        if minutes < 60 { return "بعد \(minutes) \(minutes <= 10 && minutes >= 3 ? "دقائق" : "دقيقة")" }
        return "بعد \(minutes / 60):\(String(format: "%02d", minutes % 60))"
    }

    /// «17 ربيع الآخر 1448 هـ», Umm al-Qura calendar.
    public static func hijri(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let months = ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة", "رجب", "شعبان",
                      "رمضان", "شوال", "ذو القعدة", "ذو الحجة"]
        let month = months[max(0, min(11, (parts.month ?? 1) - 1))]
        return "\(parts.day ?? 1) \(month) \(parts.year ?? 0) هـ"
    }

    /// «الجمعة 9 أكتوبر».
    public static func gregorian(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.weekday, .month, .day], from: date)
        let days = ["الأحد", "الإثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"]
        let months = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر",
                      "نوفمبر", "ديسمبر"]
        return "\(days[(parts.weekday ?? 1) - 1]) \(parts.day ?? 1) \(months[(parts.month ?? 1) - 1])"
    }
}
