import Foundation

/// The last PiP session: what it showed and how it ended. Saved when PiP starts, on every
/// navigation and when it closes. The reading position itself is saved by each section's reader
/// (PiP navigates through it), so closing PiP never loses progress.
public struct PiPSession: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case active
        case paused
        case closed
    }

    public let domain: PiPContentType
    public let contentID: String
    public let containerID: String
    public let index: Int
    public let page: Int
    public let status: Status
    public let savedAt: Date

    public init(domain: PiPContentType, contentID: String, containerID: String, index: Int, page: Int,
                status: Status, savedAt: Date) {
        self.domain = domain
        self.contentID = contentID
        self.containerID = containerID
        self.index = index
        self.page = page
        self.status = status
        self.savedAt = savedAt
    }
}

public protocol PiPSessionStore: AnyObject {
    func load() -> PiPSession?
    func save(_ session: PiPSession)
    func clear()
}

public final class InMemoryPiPSessionStore: PiPSessionStore {
    public private(set) var session: PiPSession?
    public private(set) var saves = 0
    public init() {}
    public func load() -> PiPSession? { session }
    public func save(_ session: PiPSession) { self.session = session; saves += 1 }
    public func clear() { session = nil }
}

/// The session as JSON in UserDefaults. Unreadable data is removed.
public final class UserDefaultsPiPSessionStore: PiPSessionStore {
    public static let defaultKey = "pip.session.v1"
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = UserDefaultsPiPSessionStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> PiPSession? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let session = try? JSONDecoder().decode(PiPSession.self, from: data) else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return session
    }

    public func save(_ session: PiPSession) {
        if let data = try? JSONEncoder().encode(session) { defaults.set(data, forKey: key) }
    }

    public func clear() { defaults.removeObject(forKey: key) }
}

/// Whether PiP may be offered at all.
public struct PiPAvailability: Equatable, Sendable {
    /// `UserDefaults` key of the «العرض العائم» setting (on by default).
    public static let settingKey = "pip.enabled"

    /// The build declares the background mode PiP needs (`UIBackgroundModes` contains `audio`,
    /// "Audio, AirPlay, and Picture in Picture"). Without it the system does not keep PiP
    /// running, so no PiP button is shown.
    public let backgroundModeDeclared: Bool
    /// The user's setting.
    public var userEnabled: Bool
    /// Automatic start when the app leaves the foreground. Off: PiP starts only from a button.
    public let allowsAutomaticStart: Bool

    public init(backgroundModeDeclared: Bool, userEnabled: Bool, allowsAutomaticStart: Bool = false) {
        self.backgroundModeDeclared = backgroundModeDeclared
        self.userEnabled = userEnabled
        self.allowsAutomaticStart = allowsAutomaticStart
    }

    public var isEnabled: Bool { backgroundModeDeclared && userEnabled }

    /// Reads the background mode from an Info.plist dictionary (`Bundle.main.infoDictionary`).
    public static func backgroundModeDeclared(in info: [String: Any]?) -> Bool {
        (info?["UIBackgroundModes"] as? [String])?.contains("audio") ?? false
    }
}
