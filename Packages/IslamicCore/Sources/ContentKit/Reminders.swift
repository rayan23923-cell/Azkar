import Combine
import Foundation

/// The two daily reminders: morning and evening adhkar.
public enum ReminderKind: String, Codable, CaseIterable, Sendable {
    case morning
    case evening

    /// The notification identifier; stable, so rescheduling replaces rather than duplicates.
    public var identifier: String { "azkar.reminder.\(rawValue)" }

    public var title: String {
        switch self {
        case .morning: return "أذكار الصباح"
        case .evening: return "أذكار المساء"
        }
    }

    public var body: String {
        switch self {
        case .morning: return "حان وقت أذكار الصباح"
        case .evening: return "حان وقت أذكار المساء"
        }
    }

    /// What the notification opens.
    public var target: ContentRef {
        switch self {
        case .morning: return .dhikrGroup("morning")
        case .evening: return .dhikrGroup("evening")
        }
    }
}

public struct Reminder: Codable, Equatable, Sendable, Identifiable {
    public let kind: ReminderKind
    public var isEnabled: Bool
    /// Local wall-clock time, 0...23 and 0...59.
    public var hour: Int
    public var minute: Int

    public var id: ReminderKind { kind }

    public init(kind: ReminderKind, isEnabled: Bool, hour: Int, minute: Int) {
        self.kind = kind
        self.isEnabled = isEnabled
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public static func defaultReminder(_ kind: ReminderKind) -> Reminder {
        switch kind {
        case .morning: return Reminder(kind: .morning, isEnabled: false, hour: 6, minute: 0)
        case .evening: return Reminder(kind: .evening, isEnabled: false, hour: 17, minute: 0)
        }
    }
}

public struct ReminderSettings: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var reminders: [Reminder]

    public init(reminders: [Reminder]) {
        version = Self.currentVersion
        // One per kind, in kind order; missing kinds get their defaults.
        self.reminders = ReminderKind.allCases.map { kind in
            reminders.first { $0.kind == kind } ?? Reminder.defaultReminder(kind)
        }
    }

    public static let defaults = ReminderSettings(reminders: [])

    public subscript(kind: ReminderKind) -> Reminder {
        get { reminders.first { $0.kind == kind } ?? Reminder.defaultReminder(kind) }
        set {
            if let index = reminders.firstIndex(where: { $0.kind == kind }) {
                reminders[index] = Reminder(kind: kind, isEnabled: newValue.isEnabled, hour: newValue.hour,
                                            minute: newValue.minute)
            }
        }
    }

    public var anyEnabled: Bool { reminders.contains { $0.isEnabled } }
}

/// One local notification to schedule: repeating every day at a wall-clock time, so it follows
/// the device's time zone and daylight-saving changes.
public struct ReminderRequest: Equatable, Sendable {
    public let identifier: String
    public let title: String
    public let body: String
    public let hour: Int
    public let minute: Int
    public let target: ContentRef
}

public enum ReminderPlanner {
    /// The requests for the enabled reminders.
    public static func requests(for settings: ReminderSettings) -> [ReminderRequest] {
        settings.reminders.filter(\.isEnabled).map { reminder in
            ReminderRequest(identifier: reminder.kind.identifier, title: reminder.kind.title,
                            body: reminder.kind.body, hour: reminder.hour, minute: reminder.minute,
                            target: reminder.kind.target)
        }
    }

    /// Every identifier this app ever schedules (removed before scheduling again).
    public static var allIdentifiers: [String] { ReminderKind.allCases.map(\.identifier) }
}

public protocol ReminderStore: AnyObject {
    func load() -> ReminderSettings
    func save(_ settings: ReminderSettings)
}

/// JSON in UserDefaults (key `reminders.v1`); unreadable or unsupported data reads as the defaults.
public final class UserDefaultsReminderStore: ReminderStore {
    public static let defaultKey = "reminders.v1"
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = UserDefaultsReminderStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> ReminderSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(ReminderSettings.self, from: data),
              settings.version == ReminderSettings.currentVersion else { return .defaults }
        return ReminderSettings(reminders: settings.reminders.map {
            Reminder(kind: $0.kind, isEnabled: $0.isEnabled, hour: $0.hour, minute: $0.minute)
        })
    }

    public func save(_ settings: ReminderSettings) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        if let data = try? encoder.encode(settings) { defaults.set(data, forKey: key) }
    }
}

public enum ReminderAuthorization: Equatable, Sendable {
    case notDetermined
    case allowed
    case denied
}

/// The platform notification centre (the app wraps `UNUserNotificationCenter`; tests use a fake).
@MainActor
public protocol ReminderScheduling: AnyObject {
    func authorization() async -> ReminderAuthorization
    /// Asks the user; only ever called when they turn a reminder on.
    func requestAuthorization() async -> Bool
    func removeRequests(identifiers: [String]) async
    func add(_ request: ReminderRequest) async throws
}

/// Keeps the scheduled notifications equal to the saved settings. Permission is asked only
/// when a reminder is turned on; with permission denied nothing is scheduled and the screen
/// says so.
@MainActor
public final class ReminderController: ObservableObject {
    @Published public private(set) var settings: ReminderSettings
    @Published public private(set) var authorization: ReminderAuthorization = .notDetermined
    /// Set when scheduling failed; cleared by the next successful apply.
    @Published public private(set) var lastError: String?

    private let store: ReminderStore
    private let scheduler: ReminderScheduling

    public init(store: ReminderStore, scheduler: ReminderScheduling) {
        self.store = store
        self.scheduler = scheduler
        settings = store.load()
    }

    public func refreshAuthorization() async {
        authorization = await scheduler.authorization()
    }

    public func setEnabled(_ enabled: Bool, for kind: ReminderKind) async {
        settings[kind].isEnabled = enabled
        await persistAndApply(askingPermission: enabled)
    }

    public func setTime(hour: Int, minute: Int, for kind: ReminderKind) async {
        var reminder = settings[kind]
        reminder.hour = hour
        reminder.minute = minute
        settings[kind] = reminder
        await persistAndApply(askingPermission: false)
    }

    /// Re-schedules from the saved settings (at launch and when permission may have changed).
    public func apply() async {
        await persistAndApply(askingPermission: false)
    }

    private func persistAndApply(askingPermission: Bool) async {
        store.save(settings)
        authorization = await scheduler.authorization()
        if settings.anyEnabled && authorization == .notDetermined && askingPermission {
            authorization = await scheduler.requestAuthorization() ? .allowed : .denied
        }
        await scheduler.removeRequests(identifiers: ReminderPlanner.allIdentifiers)
        guard authorization == .allowed else {
            lastError = nil
            return
        }
        do {
            for request in ReminderPlanner.requests(for: settings) {
                try await scheduler.add(request)
            }
            lastError = nil
        } catch {
            lastError = "تعذّر جدولة التذكير"
        }
    }
}
