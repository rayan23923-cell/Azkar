import Foundation

/// A calendar day in the user's current calendar and time zone ("2026-10-08"). Built from
/// date components, so a day is the same day the user sees on their clock, whatever the
/// time zone or daylight-saving change.
public struct DayKey: Hashable, Codable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Parses "YYYY-MM-DD".
    public init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public var string: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var description: String { string }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// The day `days` later (or earlier, when negative) in the calendar.
    public func adding(days: Int, calendar: Calendar = .current) -> DayKey {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = 12
        let noon = calendar.date(from: parts) ?? Date()
        return DayKey(date: calendar.date(byAdding: .day, value: days, to: noon) ?? noon, calendar: calendar)
    }
}

/// What was completed on which day: sections (a Hisn chapter, a dhikr group, a dua category,
/// a surah) finished by reading to the end. Only completion is recorded; nothing else.
public protocol DailyProgressStore: AnyObject {
    func completed(on day: DayKey) -> Set<ContentRef>
    func markCompleted(_ ref: ContentRef, on day: DayKey)
    func clear()
}

public extension DailyProgressStore {
    func isCompleted(_ ref: ContentRef, on day: DayKey) -> Bool { completed(on: day).contains(ref) }
}

/// Stored as one JSON value: `{"version":1,"days":{"2026-10-08":["hisn:hisn-ch-027"]}}`.
/// Only the last `retentionDays` days are kept. Unreadable or unsupported data is removed and
/// read as empty.
public final class UserDefaultsDailyProgressStore: DailyProgressStore {
    public static let defaultKey = "content.daily.v1"
    static let version = 1

    private struct Snapshot: Codable {
        let version: Int
        var days: [String: [ContentRef]]
    }

    private let defaults: UserDefaults
    private let key: String
    private let retentionDays: Int

    public init(defaults: UserDefaults = .standard, key: String = UserDefaultsDailyProgressStore.defaultKey,
                retentionDays: Int = 30) {
        self.defaults = defaults
        self.key = key
        self.retentionDays = max(1, retentionDays)
    }

    public func completed(on day: DayKey) -> Set<ContentRef> {
        Set(load().days[day.string] ?? [])
    }

    public func markCompleted(_ ref: ContentRef, on day: DayKey) {
        var snapshot = load()
        var refs = Set(snapshot.days[day.string] ?? [])
        guard refs.insert(ref).inserted else { return }
        snapshot.days[day.string] = refs.sorted()
        // Keep the newest days only.
        let oldest = day.adding(days: -(retentionDays - 1))
        snapshot.days = snapshot.days.filter { DayKey(string: $0.key).map { $0 >= oldest } ?? false }
        save(snapshot)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }

    private func load() -> Snapshot {
        guard let data = defaults.data(forKey: key) else { return Snapshot(version: Self.version, days: [:]) }
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data), snapshot.version == Self.version else {
            defaults.removeObject(forKey: key)
            return Snapshot(version: Self.version, days: [:])
        }
        return snapshot
    }

    private func save(_ snapshot: Snapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}

public final class InMemoryDailyProgressStore: DailyProgressStore {
    public private(set) var days: [DayKey: Set<ContentRef>] = [:]

    public init() {}

    public func completed(on day: DayKey) -> Set<ContentRef> { days[day] ?? [] }
    public func markCompleted(_ ref: ContentRef, on day: DayKey) { days[day, default: []].insert(ref) }
    public func clear() { days = [:] }
}
