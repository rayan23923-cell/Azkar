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

/// What the next-prayer widget can show, decided from what it can read. Kept apart from the
/// view so each case is tested: the widget never shows a time it cannot back.
/// What the user set in the next-prayer widget's own settings; nil means "as in the app".
public struct NextPrayerWidgetChoice: Equatable, Sendable {
    public var place: PrayerPlace?
    public var method: CalculationMethod?
    public var asr: AsrSchool?

    public init(place: PrayerPlace? = nil, method: CalculationMethod? = nil, asr: AsrSchool? = nil) {
        self.place = place
        self.method = method
        self.asr = asr
    }
}

public enum NextPrayerWidgetState: Equatable, Sendable {
    /// The App Group cannot be opened (an unsigned build, or a group not registered for this
    /// signing team): the widget cannot see the app's settings, which is not the same as no
    /// place being chosen.
    case sharedSettingsUnavailable
    /// The app has not saved a place.
    case noPlace
    /// The sun does not rise or set there on this day.
    case noTimes(place: String)
    /// A city was chosen in the widget, but no calculation method is known for it: none was
    /// chosen in the widget and the app's settings cannot be read. No default is assumed.
    case needsMethod(place: String)
    case moments([PrayerMoment], place: String, timeZone: TimeZone, twentyFourHour: Bool, notice: PrayerPlaceNotice?)

    /// - Parameters:
    ///   - store: the App Group copy of the settings; nil when the group is unavailable.
    ///   - choice: what the user set in the widget itself («تعديل الودجة»). A city chosen there
    ///     is used instead of the app's place, so the widget works where the App Group does not
    ///     (a build signed without it). The method and Asr school come from the widget when set,
    ///     else from the app's shared settings, and are never assumed.
    public static func resolve(store: PrayerSettingsStore?, choice: NextPrayerWidgetChoice = NextPrayerWidgetChoice(),
                               deviceTimeZone: TimeZone, now: Date, limit: Int = 16) -> NextPrayerWidgetState {
        if let place = choice.place {
            // The app's settings count only when it shared a place: then they were read and copied
            // whole (see `PrayerSettingsStore.copy(to:)`).
            let app = store?.place != nil ? store : nil
            guard let method = choice.method ?? app?.parameters.method else { return .needsMethod(place: place.name) }
            let parameters = PrayerParameters(method: method, asr: choice.asr ?? app?.parameters.asr ?? .standard,
                                              adjustments: app?.parameters.adjustments ?? [:])
            let schedule = PrayerSchedule(coordinates: place.coordinates, timeZone: place.timeZone, parameters: parameters)
            let moments = schedule.moments(from: now, limit: limit)
            guard !moments.isEmpty else { return .noTimes(place: place.name) }
            return .moments(moments, place: place.name, timeZone: schedule.timeZone,
                            twentyFourHour: app?.twentyFourHour ?? false, notice: nil)
        }
        guard let store else { return .sharedSettingsUnavailable }
        guard let place = store.place, let schedule = store.schedule else { return .noPlace }
        let moments = schedule.moments(from: now, limit: limit)
        guard !moments.isEmpty else { return .noTimes(place: place.name) }
        return .moments(moments, place: place.name, timeZone: schedule.timeZone, twentyFourHour: store.twentyFourHour,
                        notice: PrayerPlaceNotice.check(place, deviceTimeZone: deviceTimeZone, at: now))
    }
}
