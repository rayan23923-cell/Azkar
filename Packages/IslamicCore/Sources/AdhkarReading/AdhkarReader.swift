import Foundation
import IslamicCore
import ContentKit

/// Where the reader stopped in each collection: the item and the repetitions already said.
public struct DevotionalPosition: Codable, Equatable, Sendable {
    public let item: ContentRef
    public let repetitions: Int
    public let savedAt: Date

    public init(item: ContentRef, repetitions: Int, savedAt: Date) {
        self.item = item
        self.repetitions = max(0, repetitions)
        self.savedAt = savedAt
    }
}

public protocol DevotionalPositionStore: AnyObject {
    func position(in collection: ContentRef) -> DevotionalPosition?
    func save(_ position: DevotionalPosition, in collection: ContentRef)
    func clear(_ collection: ContentRef)
    func clearAll()
}

/// Positions in UserDefaults as `{"positions":{"adhkar:group:morning":{…}},"version":1}`.
/// Unreadable data is removed and reading starts over.
public final class UserDefaultsDevotionalPositionStore: DevotionalPositionStore {
    public static let defaultKey = "adhkar.positions.v1"

    private struct File: Codable {
        var version = 1
        var positions: [String: DevotionalPosition] = [:]
    }

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = UserDefaultsDevotionalPositionStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    private func read() -> File {
        guard let data = defaults.data(forKey: key) else { return File() }
        guard let file = try? JSONDecoder().decode(File.self, from: data), file.version == 1 else {
            defaults.removeObject(forKey: key)
            return File()
        }
        return file
    }

    private func write(_ file: File) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        if let data = try? encoder.encode(file) { defaults.set(data, forKey: key) }
    }

    public func position(in collection: ContentRef) -> DevotionalPosition? { read().positions[collection.string] }

    public func save(_ position: DevotionalPosition, in collection: ContentRef) {
        var file = read()
        file.positions[collection.string] = position
        write(file)
    }

    public func clear(_ collection: ContentRef) {
        var file = read()
        file.positions[collection.string] = nil
        write(file)
    }

    public func clearAll() { defaults.removeObject(forKey: key) }
}

public final class InMemoryDevotionalPositionStore: DevotionalPositionStore {
    public private(set) var positions: [ContentRef: DevotionalPosition] = [:]
    public init() {}
    public func position(in collection: ContentRef) -> DevotionalPosition? { positions[collection] }
    public func save(_ position: DevotionalPosition, in collection: ContentRef) { positions[collection] = position }
    public func clear(_ collection: ContentRef) { positions[collection] = nil }
    public func clearAll() { positions = [:] }
}

/// The adhkar / dua reader: one item at a time with its counter. Counting moves on after the
/// item's repetitions; the last one completes the collection for today.
@MainActor
public final class DevotionalReaderController: ObservableObject {
    @Published public private(set) var cursor: SessionCursor<DevotionalItem>
    /// Set when the last repetition of the collection was said.
    @Published public private(set) var isComplete = false
    public let collection: DevotionalCollection
    private let store: DevotionalPositionStore
    private let dailyProgress: DailyProgressStore?
    private let counts: ItemCountStore?
    private let now: () -> Date

    /// Opens at `start` when given (a search result or favorite; no repetitions), otherwise at
    /// the saved position, otherwise at the first item. Nil for an empty collection. Each
    /// item's count today comes back from `counts`, so a finished item gone back to shows it.
    public init?(collection: DevotionalCollection, start: ContentRef? = nil, store: DevotionalPositionStore,
                 dailyProgress: DailyProgressStore? = nil, counts: ItemCountStore? = nil,
                 now: @escaping () -> Date = Date.init) {
        guard var cursor = SessionCursor(items: collection.items) else { return nil }
        if let start, let index = collection.items.firstIndex(where: { $0.ref == start }) {
            cursor.jump(to: index)
            if let saved = store.position(in: collection.ref), saved.item == start {
                Self.restore(saved.repetitions, in: &cursor)
            }
        } else if let saved = store.position(in: collection.ref),
                  let index = collection.items.firstIndex(where: { $0.ref == saved.item }) {
            cursor.jump(to: index)
            Self.restore(saved.repetitions, in: &cursor)
        }
        if let counts {
            let saved = counts.counts(in: collection.ref, on: DayKey(date: now()))
            var byIndex: [Int: Int] = [:]
            for (index, item) in collection.items.enumerated() {
                if let count = saved[item.ref.string] { byIndex[index] = count }
            }
            cursor.restoreCounts(byIndex)
        }
        self.cursor = cursor
        self.collection = collection
        self.store = store
        self.dailyProgress = dailyProgress
        self.counts = counts
        self.now = now
    }

    private static func restore(_ repetitions: Int, in cursor: inout SessionCursor<DevotionalItem>) {
        let count = min(repetitions, cursor.requiredRepetitions - 1)
        guard count > 0 else { return }
        for _ in 0..<count { cursor.advance() }
    }

    public var current: DevotionalItem { cursor.current }
    public var index: Int { cursor.index }
    public var count: Int { cursor.count }
    public var remaining: Int { cursor.remainingRepetitions }

    /// Counts one repetition.
    @discardableResult
    public func recite() -> SessionCursor<DevotionalItem>.Step {
        let step = cursor.advance()
        if step == .finished {
            isComplete = true
            dailyProgress?.markCompleted(collection.ref, on: DayKey(date: now()))
            store.clear(collection.ref)
            // Done for today: the next opening starts afresh.
            counts?.clear(collection.ref)
        } else {
            persist()
        }
        return step
    }

    public func next() {
        if cursor.next() { isComplete = false; persist() }
    }

    public func previous() {
        if cursor.previous() { isComplete = false; persist() }
    }

    public func jump(to index: Int) {
        if cursor.jump(to: index) { isComplete = false; persist() }
    }

    /// Back to the first item with no repetitions; the saved position is removed.
    public func restart() {
        cursor.restart()
        isComplete = false
        store.clear(collection.ref)
        counts?.clear(collection.ref)
    }

    public func persist() {
        guard !isComplete else { return }
        // A finished item (gone back to) is saved as not started, as Hisn resumes it.
        let repetitions = cursor.remainingRepetitions == 0 ? 0 : cursor.completedRepetitions
        store.save(DevotionalPosition(item: current.ref, repetitions: repetitions, savedAt: now()),
                   in: collection.ref)
        let items = cursor.items
        counts?.save(Dictionary(cursor.counts.map { (items[$0.key].ref.string, $0.value) }, uniquingKeysWith: { Swift.max($0, $1) }),
                     in: collection.ref, on: DayKey(date: now()))
    }
}
