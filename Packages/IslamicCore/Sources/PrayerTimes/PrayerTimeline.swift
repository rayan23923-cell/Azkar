import Foundation

/// What the next-prayer widget shows from one moment until the next change.
public struct PrayerMoment: Equatable, Sendable {
    /// From when this is shown.
    public let date: Date
    public let next: Prayer
    public let nextTime: Date
    /// The prayer whose time it is; nil between sunrise and Dhuhr.
    public let current: Prayer?
    /// The day's times in the place's calendar, for the list.
    public let day: PrayerDay

    public init(date: Date, next: Prayer, nextTime: Date, current: Prayer?, day: PrayerDay) {
        self.date = date
        self.next = next
        self.nextTime = nextTime
        self.current = current
        self.day = day
    }
}

public extension PrayerSchedule {
    /// The moments from `start` on: `start` itself, then every time the next prayer, the
    /// current one or the day changes (each prayer and sunrise, and each midnight in the
    /// place's time zone), up to `limit`. The widget's countdown runs by itself between them
    /// (`Text(date, style: .timer)`), so nothing is updated every second.
    func moments(from start: Date, limit: Int = 16) -> [PrayerMoment] {
        var changes: [Date] = [start]
        for offset in 0...2 {
            if let day = day(containing: start, offset: offset) {
                changes += day.all.map(\.time).filter { $0 > start }
            }
            if let shifted = calendar.date(byAdding: .day, value: offset + 1, to: start) {
                let midnight = calendar.startOfDay(for: shifted)
                if midnight > start { changes.append(midnight) }
            }
        }
        var moments: [PrayerMoment] = []
        for date in Set(changes).sorted() {
            guard moments.count < limit else { break }
            guard let next = next(after: date), let today = day(containing: date) else { continue }
            moments.append(PrayerMoment(date: date, next: next.prayer, nextTime: next.time,
                                        current: current(at: date), day: today))
        }
        return moments
    }
}

/// Something to say about the saved place before trusting its times.
public enum PrayerPlaceNotice: Equatable, Sendable {
    /// The device's location was saved in another time zone: the user may have travelled,
    /// so the times may be for the old place.
    case locationMayBeOld
    /// A city in another time zone was chosen: its times are shown in its own local time.
    case cityInOtherTimeZone

    /// Compares UTC offsets at `date`, so two zones with the same clock (Riyadh and Kuwait)
    /// raise nothing. The place is never changed here; the screen offers to update it.
    public static func check(_ place: PrayerPlace, deviceTimeZone: TimeZone, at date: Date) -> PrayerPlaceNotice? {
        guard place.timeZoneID != nil,
              place.timeZone.secondsFromGMT(for: date) != deviceTimeZone.secondsFromGMT(for: date) else { return nil }
        return place.isCurrentLocation ? .locationMayBeOld : .cityInOtherTimeZone
    }
}
