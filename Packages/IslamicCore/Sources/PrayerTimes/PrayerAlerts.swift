import Foundation

/// Which prayers announce their time with a notification («حان الآن وقت صلاة الظهر»). Off
/// until the user turns them on; sunrise is never one.
public struct PrayerAlertSettings: Equatable, Sendable {
    public var prayers: Set<Prayer>

    public init(prayers: Set<Prayer> = []) {
        self.prayers = prayers.filter(\.isPrayer)
    }

    public var anyEnabled: Bool { !prayers.isEmpty }

    public func isEnabled(_ prayer: Prayer) -> Bool { prayers.contains(prayer) }

    public mutating func set(_ prayer: Prayer, enabled: Bool) {
        guard prayer.isPrayer else { return }
        if enabled { prayers.insert(prayer) } else { prayers.remove(prayer) }
    }

    /// The five prayers.
    public static let all = PrayerAlertSettings(prayers: Set(Prayer.allCases))
}

/// The alert settings in UserDefaults (key `prayer.alerts`, the enabled prayers' raw names);
/// anything unreadable reads as none, so no alert is ever turned on by itself.
public final class PrayerAlertStore {
    public static let key = "prayer.alerts"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var settings: PrayerAlertSettings {
        get {
            let names = defaults.stringArray(forKey: Self.key) ?? []
            return PrayerAlertSettings(prayers: Set(names.compactMap(Prayer.init(rawValue:))))
        }
        set {
            defaults.set(Prayer.allCases.filter(newValue.isEnabled).map(\.rawValue), forKey: Self.key)
        }
    }
}

/// One notification at a prayer's time.
public struct PrayerAlertRequest: Equatable, Sendable {
    public let identifier: String
    public let prayer: Prayer
    public let date: Date
    public let title: String
    public let body: String
}

public enum PrayerAlertPlanner {
    /// Every alert identifier starts with this, so all of them are found and removed before
    /// scheduling again (the place, the method or a correction may have moved the times).
    public static let identifierPrefix = "azkar.adhan."

    /// iOS keeps at most 64 pending notifications per app; the two adhkar reminders and some
    /// room are left, so the five prayers fit nine days ahead.
    public static let maximumRequests = 45

    /// The alerts from `now` on: each enabled prayer's time on the following days, soonest
    /// first, up to `limit`. Times are the schedule's own, corrections included. The app
    /// schedules them again each time it opens, so they keep running ahead.
    public static func requests(schedule: PrayerSchedule, settings: PrayerAlertSettings, placeName: String,
                                from now: Date, limit: Int = maximumRequests) -> [PrayerAlertRequest] {
        guard settings.anyEnabled, limit > 0 else { return [] }
        let calendar = schedule.calendar
        var requests: [PrayerAlertRequest] = []
        var offset = 0
        // Days without times (polar days) are skipped; a bound keeps that from looping.
        while requests.count < limit && offset < 60 {
            defer { offset += 1 }
            guard let day = schedule.day(containing: now, offset: offset) else { continue }
            for entry in day.all where settings.isEnabled(entry.prayer) && entry.time > now {
                guard requests.count < limit else { break }
                let parts = calendar.dateComponents([.year, .month, .day], from: entry.time)
                let stamp = String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
                requests.append(PrayerAlertRequest(
                    identifier: "\(identifierPrefix)\(stamp).\(entry.prayer.rawValue)",
                    prayer: entry.prayer,
                    date: entry.time,
                    title: "صلاة \(entry.prayer.arabicName)",
                    body: "حان الآن وقت صلاة \(entry.prayer.arabicName) في \(placeName)"))
            }
        }
        return requests
    }
}

public extension PrayerSchedule {
    /// The prayer whose time came less than `window` ago, with that time: shown as «حان الآن
    /// وقت صلاة …» right when the adhan is due, before the screen moves on to the next one.
    func justEntered(at date: Date, within window: TimeInterval = 15 * 60) -> (prayer: Prayer, time: Date)? {
        for offset in [0, -1] {
            guard let day = day(containing: date, offset: offset) else { continue }
            if let last = day.all.last(where: { $0.prayer.isPrayer && $0.time <= date }) {
                return date.timeIntervalSince(last.time) < window ? last : nil
            }
        }
        return nil
    }
}
