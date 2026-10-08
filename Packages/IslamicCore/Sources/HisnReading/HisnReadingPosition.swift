import Foundation
import IslamicCore

/// The persistent reading cursor: where the reader last stopped (chapter, item, repetitions
/// counted) and when. Long-lived and stored on the device; it is not the reading session.
/// The session (`HisnReader` / `HisnSession`) lives only while a chapter is open and is
/// rebuilt from this cursor by `HisnResume.reader(for:in:)`.
///
/// Stored as JSON (format in PHASE_3D_HISN_PRODUCT_INTEGRATION.md):
/// `{"version":1,"chapterId":…,"itemId":…,"itemIndex":…,"completedRepetitions":…,"savedAt":…}`.
/// Data without `version` was written by Phase 3A in the same shape and reads as version 1.
/// Any other version, a missing field, an empty id or a negative number fails to decode.
public struct HisnReadingPosition: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let chapterId: String
    public let itemId: String
    public let itemIndex: Int
    public let completedRepetitions: Int
    /// The last reading activity (opening, moving or counting).
    public let savedAt: Date

    public init(chapterId: String, itemId: String, itemIndex: Int, completedRepetitions: Int, savedAt: Date) {
        self.chapterId = chapterId
        self.itemId = itemId
        self.itemIndex = itemIndex
        self.completedRepetitions = completedRepetitions
        self.savedAt = savedAt
    }

    private enum CodingKeys: String, CodingKey {
        case version, chapterId, itemId, itemIndex, completedRepetitions, savedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard version == Self.currentVersion else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container,
                                                   debugDescription: "unsupported version \(version)")
        }
        chapterId = try container.decode(String.self, forKey: .chapterId)
        itemId = try container.decode(String.self, forKey: .itemId)
        itemIndex = try container.decode(Int.self, forKey: .itemIndex)
        completedRepetitions = try container.decode(Int.self, forKey: .completedRepetitions)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        guard !chapterId.isEmpty, !itemId.isEmpty, itemIndex >= 0, completedRepetitions >= 0 else {
            throw DecodingError.dataCorruptedError(forKey: .chapterId, in: container,
                                                   debugDescription: "invalid reading position")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(chapterId, forKey: .chapterId)
        try container.encode(itemId, forKey: .itemId)
        try container.encode(itemIndex, forKey: .itemIndex)
        try container.encode(completedRepetitions, forKey: .completedRepetitions)
        try container.encode(savedAt, forKey: .savedAt)
    }

    /// The same place with nothing counted.
    func withoutRepetitions() -> HisnReadingPosition {
        HisnReadingPosition(chapterId: chapterId, itemId: itemId, itemIndex: itemIndex, completedRepetitions: 0,
                            savedAt: savedAt)
    }
}

/// Persistence adapter for the one saved position.
public protocol HisnReadingPositionStore: AnyObject {
    func load() -> HisnReadingPosition?
    func save(_ position: HisnReadingPosition)
    func clear()
}

/// The app's store: one JSON value in UserDefaults (local, offline; written only on reading
/// transitions). Unreadable, incomplete or unsupported data counts as no position and is removed.
public final class UserDefaultsHisnReadingPositionStore: HisnReadingPositionStore {
    public static let defaultKey = "hisn.reader.position.v1"
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = UserDefaultsHisnReadingPositionStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> HisnReadingPosition? {
        guard let stored = defaults.object(forKey: key) else { return nil }
        guard let data = stored as? Data,
              let position = try? JSONDecoder().decode(HisnReadingPosition.self, from: data) else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return position
    }

    public func save(_ position: HisnReadingPosition) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(position) else { return }
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

/// Resume from the persistent cursor.
///
/// - The cursor (chapter and item) is kept across days and launches until the chapter is
///   completed or the cursor becomes invalid.
/// - Repetitions counted belong to the day's reading: they are restored on the same calendar
///   day and start from zero on a later day.
/// - A cursor whose chapter or item no longer exists is removed; the index opens instead.
public enum HisnResume {
    /// The position to offer as «متابعة القراءة», or nil (open the index). An invalid saved
    /// cursor is cleared from the store.
    public static func position(in store: HisnReadingPositionStore, library: HisnLibrary,
                                now: Date = Date(), calendar: Calendar = .current) -> HisnReadingPosition? {
        guard let position = store.load() else { return nil }
        guard reader(for: position, in: library) != nil else {
            store.clear()
            return nil
        }
        return calendar.isDate(position.savedAt, inSameDayAs: now) ? position : position.withoutRepetitions()
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
