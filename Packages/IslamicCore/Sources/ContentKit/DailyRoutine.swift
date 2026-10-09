import Foundation

/// An optional daily routine: the steps the user wants to see on Home, in their order. Off
/// until turned on. There is no streak, no missed-day count and nothing carried over: each
/// day only shows what is done today.
public struct DailyRoutine: Codable, Equatable, Sendable {
    public enum Step: String, Codable, CaseIterable, Sendable {
        case morningAdhkar
        case quran
        case afterPrayerAdhkar
        case eveningAdhkar
        case sleepAdhkar

        /// The adhkar collection the step opens; nil for the Quran.
        public var collection: ContentRef? {
            switch self {
            case .morningAdhkar: return .dhikrGroup("morning")
            case .afterPrayerAdhkar: return .dhikrGroup("afterPrayer")
            case .eveningAdhkar: return .dhikrGroup("evening")
            case .sleepAdhkar: return .dhikrGroup("sleep")
            case .quran: return nil
            }
        }

        public var arabicTitle: String {
            switch self {
            case .morningAdhkar: return "أذكار الصباح"
            case .quran: return "ورد القرآن"
            case .afterPrayerAdhkar: return "أذكار بعد الصلاة"
            case .eveningAdhkar: return "أذكار المساء"
            case .sleepAdhkar: return "أذكار النوم"
            }
        }
    }

    public struct Entry: Codable, Equatable, Hashable, Sendable {
        public let step: Step
        public var isOn: Bool

        public init(step: Step, isOn: Bool) {
            self.step = step
            self.isOn = isOn
        }
    }

    public var isEnabled: Bool
    /// Every step exactly once, in the user's order.
    public private(set) var entries: [Entry]

    public static let standard = DailyRoutine(isEnabled: false, entries: Step.allCases.map { Entry(step: $0, isOn: true) })

    public init(isEnabled: Bool, entries: [Entry]) {
        self.isEnabled = isEnabled
        self.entries = Self.normalized(entries)
    }

    public var activeSteps: [Step] { isEnabled ? entries.filter(\.isOn).map(\.step) : [] }

    public mutating func set(_ step: Step, on: Bool) {
        guard let index = entries.firstIndex(where: { $0.step == step }) else { return }
        entries[index].isOn = on
    }

    /// As `List.onMove` gives it.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.filter { entries.indices.contains($0) }.sorted()
        guard !moving.isEmpty, destination >= 0, destination <= entries.count else { return }
        let items = moving.map { entries[$0] }
        let before = moving.filter { $0 < destination }.count
        for index in moving.reversed() { entries.remove(at: index) }
        entries.insert(contentsOf: items, at: destination - before)
    }

    /// Each known step once (the first time it appears), then any missing ones, off.
    static func normalized(_ entries: [Entry]) -> [Entry] {
        var seen: Set<Step> = []
        var result: [Entry] = []
        for entry in entries where seen.insert(entry.step).inserted { result.append(entry) }
        for step in Step.allCases where !seen.contains(step) { result.append(Entry(step: step, isOn: false)) }
        return result
    }

    private enum CodingKeys: String, CodingKey { case version, isEnabled, entries }
    private struct StoredEntry: Codable { let step: String; let isOn: Bool }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Int.self, forKey: .version) == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container, debugDescription: "unsupported")
        }
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        // A step a later version added and this one does not know is dropped, not an error.
        let stored = try container.decode([StoredEntry].self, forKey: .entries)
        entries = Self.normalized(stored.compactMap { item in Step(rawValue: item.step).map { Entry(step: $0, isOn: item.isOn) } })
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(1, forKey: .version)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(entries.map { StoredEntry(step: $0.step.rawValue, isOn: $0.isOn) }, forKey: .entries)
    }
}

/// The routine in UserDefaults (key `routine.v1`); unreadable data is removed and the
/// routine is off again.
public final class DailyRoutineStore {
    public static let defaultKey = "routine.v1"
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = DailyRoutineStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public var routine: DailyRoutine {
        get {
            guard let data = defaults.data(forKey: key) else { return .standard }
            guard let routine = try? JSONDecoder().decode(DailyRoutine.self, from: data) else {
                defaults.removeObject(forKey: key)
                return .standard
            }
            return routine
        }
        set {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            if let data = try? encoder.encode(newValue) { defaults.set(data, forKey: key) }
        }
    }

    public func clear() { defaults.removeObject(forKey: key) }
}
