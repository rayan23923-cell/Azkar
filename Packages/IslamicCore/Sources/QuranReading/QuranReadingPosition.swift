import Foundation
import ContentKit

/// Where the Quran reader last stopped. JSON in UserDefaults (key `quran.position.v1`):
/// `{"ayah":255,"savedAt":…,"surah":2,"version":1}`. Unreadable, unsupported or invalid data is
/// removed and read as no position.
public struct QuranReadingPosition: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let surah: Int
    public let ayah: Int
    public let savedAt: Date
    private let version: Int

    public init(_ ref: QuranVerseRef, savedAt: Date) {
        surah = ref.surah
        ayah = ref.ayah
        self.savedAt = savedAt
        version = Self.currentVersion
    }

    public var ref: QuranVerseRef { QuranVerseRef(surah: surah, ayah: ayah) }
}

public protocol QuranPositionStore: AnyObject {
    func load() -> QuranReadingPosition?
    func save(_ position: QuranReadingPosition)
    func clear()
}

public extension QuranPositionStore {
    /// The saved position when it still points at a real verse; otherwise it is cleared.
    func validPosition(in library: QuranLibrary) -> QuranReadingPosition? {
        guard let position = load() else { return nil }
        guard library.contains(position.ref) else {
            clear()
            return nil
        }
        return position
    }
}

public final class UserDefaultsQuranPositionStore: QuranPositionStore {
    public static let defaultKey = "quran.position.v1"
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = UserDefaultsQuranPositionStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> QuranReadingPosition? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let position = try? JSONDecoder().decode(QuranReadingPosition.self, from: data),
              position.versionIsCurrent, position.surah >= 1, position.ayah >= 1 else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return position
    }

    public func save(_ position: QuranReadingPosition) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        if let data = try? encoder.encode(position) { defaults.set(data, forKey: key) }
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}

public final class InMemoryQuranPositionStore: QuranPositionStore {
    public private(set) var position: QuranReadingPosition?
    public init(_ position: QuranReadingPosition? = nil) { self.position = position }
    public func load() -> QuranReadingPosition? { position }
    public func save(_ position: QuranReadingPosition) { self.position = position }
    public func clear() { position = nil }
}

extension QuranReadingPosition {
    var versionIsCurrent: Bool { version == Self.currentVersion }
}
