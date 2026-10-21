import Foundation

/// The time between each adhan and its iqama, as the local mosque keeps it. Off until turned
/// on; sunrise has none.
public struct IqamaSettings: Equatable, Sendable {
    public static let minutesRange = 1...60
    /// Common waits, used until the user changes them.
    public static let defaultMinutes: [Prayer: Int] = [.fajr: 25, .dhuhr: 20, .asr: 20, .maghrib: 10, .isha: 20]

    public var isEnabled: Bool
    private var stored: [Prayer: Int]

    public init(isEnabled: Bool = false, minutes: [Prayer: Int] = [:]) {
        self.isEnabled = isEnabled
        stored = minutes.filter { $0.key.isPrayer }.mapValues(Self.clamped)
    }

    public func minutes(for prayer: Prayer) -> Int {
        stored[prayer] ?? Self.defaultMinutes[prayer] ?? 0
    }

    public mutating func setMinutes(_ minutes: Int, for prayer: Prayer) {
        guard prayer.isPrayer else { return }
        stored[prayer] = Self.clamped(minutes)
    }

    /// The iqama after an adhan at `adhan`; nil when turned off, or for sunrise.
    public func time(of prayer: Prayer, adhan: Date) -> Date? {
        guard isEnabled, prayer.isPrayer else { return nil }
        return adhan.addingTimeInterval(TimeInterval(minutes(for: prayer) * 60))
    }

    /// Only the waits the user changed, by raw name.
    var storedByName: [String: Int] { Dictionary(uniqueKeysWithValues: stored.map { ($0.key.rawValue, $0.value) }) }

    private static func clamped(_ minutes: Int) -> Int {
        min(max(minutes, minutesRange.lowerBound), minutesRange.upperBound)
    }
}

/// The iqama settings in UserDefaults (`prayer.iqama.enabled`, `prayer.iqama.minutes`);
/// anything unreadable reads as off with the default waits.
public final class IqamaStore {
    public static let enabledKey = "prayer.iqama.enabled"
    public static let minutesKey = "prayer.iqama.minutes"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var settings: IqamaSettings {
        get {
            let names = defaults.dictionary(forKey: Self.minutesKey) as? [String: Int] ?? [:]
            let minutes = Dictionary(uniqueKeysWithValues: names.compactMap { name, value in
                Prayer(rawValue: name).map { ($0, value) }
            })
            return IqamaSettings(isEnabled: defaults.bool(forKey: Self.enabledKey), minutes: minutes)
        }
        set {
            defaults.set(newValue.isEnabled, forKey: Self.enabledKey)
            defaults.set(newValue.storedByName, forKey: Self.minutesKey)
        }
    }
}

public extension PrayerSchedule {
    /// The prayer whose adhan has come and whose iqama has not yet, with both times.
    func pendingIqama(at date: Date, settings: IqamaSettings) -> (prayer: Prayer, adhan: Date, iqama: Date)? {
        guard settings.isEnabled else { return nil }
        for offset in [0, -1] {
            guard let day = day(containing: date, offset: offset) else { continue }
            if let last = day.all.last(where: { $0.prayer.isPrayer && $0.time <= date }) {
                guard let iqama = settings.time(of: last.prayer, adhan: last.time), iqama > date else { return nil }
                return (last.prayer, last.time, iqama)
            }
        }
        return nil
    }
}
