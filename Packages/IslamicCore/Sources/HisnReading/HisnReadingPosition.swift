import Foundation
import IslamicCore

/// Where the reader stopped: chapter, item and repetitions counted. The only state kept
/// between launches; it restores a `HisnReader`, it is not a second session model.
public struct HisnReadingPosition: Codable, Equatable, Sendable {
    public let chapterId: String
    public let itemId: String
    public let itemIndex: Int
    public let completedRepetitions: Int
    public let savedAt: Date

    public init(chapterId: String, itemId: String, itemIndex: Int, completedRepetitions: Int, savedAt: Date) {
        self.chapterId = chapterId
        self.itemId = itemId
        self.itemIndex = itemIndex
        self.completedRepetitions = completedRepetitions
        self.savedAt = savedAt
    }
}

/// Persistence adapter for the one saved position.
public protocol HisnReadingPositionStore: AnyObject {
    func load() -> HisnReadingPosition?
    func save(_ position: HisnReadingPosition)
    func clear()
}

/// The app's store: one JSON value in UserDefaults. Unreadable data is treated as no position.
public final class UserDefaultsHisnReadingPositionStore: HisnReadingPositionStore {
    public static let defaultKey = "hisn.reader.position.v1"
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = UserDefaultsHisnReadingPositionStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> HisnReadingPosition? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HisnReadingPosition.self, from: data)
    }

    public func save(_ position: HisnReadingPosition) {
        guard let data = try? JSONEncoder().encode(position) else { return }
        defaults.set(data, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}

/// For tests and previews.
public final class InMemoryHisnReadingPositionStore: HisnReadingPositionStore {
    public private(set) var position: HisnReadingPosition?

    public init(_ position: HisnReadingPosition? = nil) {
        self.position = position
    }

    public func load() -> HisnReadingPosition? { position }
    public func save(_ position: HisnReadingPosition) { self.position = position }
    public func clear() { position = nil }
}

/// Same-day resume.
public enum HisnResume {
    /// The saved position, when it was saved on the same calendar day as `now` and still
    /// points at an item of the bundled content; otherwise nil.
    public static func position(in store: HisnReadingPositionStore, library: HisnLibrary,
                                now: Date = Date(), calendar: Calendar = .current) -> HisnReadingPosition? {
        guard let position = store.load(),
              calendar.isDate(position.savedAt, inSameDayAs: now),
              reader(for: position, in: library) != nil else { return nil }
        return position
    }

    /// Rebuilds the reader at a saved position. The item is found by id (its index is only a
    /// check); repetitions beyond the item's count start the item again. Nil when the
    /// chapter or item no longer exists.
    public static func reader(for position: HisnReadingPosition, in library: HisnLibrary) -> HisnReader? {
        guard let chapter = library.chapter(id: position.chapterId) else { return nil }
        let index: Int
        if chapter.items.indices.contains(position.itemIndex), chapter.items[position.itemIndex].id == position.itemId {
            index = position.itemIndex
        } else if let found = chapter.items.firstIndex(where: { $0.id == position.itemId }) {
            index = found
        } else {
            return nil
        }
        return HisnReader(chapter: chapter, itemIndex: index, completedRepetitions: max(0, position.completedRepetitions))
    }

    /// Saves where the reader is, or clears the store once the chapter is complete.
    public static func record(_ reader: HisnReader, in store: HisnReadingPositionStore, now: Date = Date()) {
        if let position = reader.position(savedAt: now) {
            store.save(position)
        } else {
            store.clear()
        }
    }
}
