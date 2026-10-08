import Combine
import Foundation

/// One saved item: a Quran verse bookmark, or a favourite dhikr, dua or Hisn item.
public struct FavoriteEntry: Codable, Equatable, Hashable, Sendable {
    public let ref: ContentRef
    public let addedAt: Date

    public init(ref: ContentRef, addedAt: Date) {
        self.ref = ref
        self.addedAt = addedAt
    }
}

public protocol FavoritesStore: AnyObject {
    /// Newest first.
    func all() -> [FavoriteEntry]
    func add(_ ref: ContentRef, at date: Date)
    func remove(_ ref: ContentRef)
    func clear()
}

public extension FavoritesStore {
    func contains(_ ref: ContentRef) -> Bool { all().contains { $0.ref == ref } }

    /// Adds or removes; returns whether the item is saved afterwards.
    @discardableResult
    func toggle(_ ref: ContentRef, at date: Date = Date()) -> Bool {
        if contains(ref) {
            remove(ref)
            return false
        }
        add(ref, at: date)
        return true
    }

    func all(of kind: ContentRef.Kind) -> [FavoriteEntry] { all().filter { $0.ref.kind == kind } }
}

/// `{"version":1,"items":[{"ref":"quran:2:255","addedAt":…}]}` in UserDefaults (key
/// `favorites.v1`). Unreadable or unsupported data is removed and read as empty.
public final class UserDefaultsFavoritesStore: FavoritesStore {
    public static let defaultKey = "favorites.v1"
    static let version = 1

    private struct Snapshot: Codable {
        let version: Int
        var items: [FavoriteEntry]
    }

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = UserDefaultsFavoritesStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func all() -> [FavoriteEntry] {
        load().items.sorted { ($0.addedAt, $1.ref) > ($1.addedAt, $0.ref) }
    }

    public func add(_ ref: ContentRef, at date: Date) {
        var snapshot = load()
        guard !snapshot.items.contains(where: { $0.ref == ref }) else { return }
        snapshot.items.append(FavoriteEntry(ref: ref, addedAt: date))
        save(snapshot)
    }

    public func remove(_ ref: ContentRef) {
        var snapshot = load()
        snapshot.items.removeAll { $0.ref == ref }
        save(snapshot)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }

    private func load() -> Snapshot {
        guard let data = defaults.data(forKey: key) else { return Snapshot(version: Self.version, items: []) }
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data), snapshot.version == Self.version else {
            defaults.removeObject(forKey: key)
            return Snapshot(version: Self.version, items: [])
        }
        return snapshot
    }

    private func save(_ snapshot: Snapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        if let data = try? encoder.encode(snapshot) { defaults.set(data, forKey: key) }
    }
}

public final class InMemoryFavoritesStore: FavoritesStore {
    private var items: [FavoriteEntry] = []

    public init() {}

    public func all() -> [FavoriteEntry] { items.sorted { ($0.addedAt, $1.ref) > ($1.addedAt, $0.ref) } }
    public func add(_ ref: ContentRef, at date: Date) {
        if !items.contains(where: { $0.ref == ref }) { items.append(FavoriteEntry(ref: ref, addedAt: date)) }
    }
    public func remove(_ ref: ContentRef) { items.removeAll { $0.ref == ref } }
    public func clear() { items = [] }
}

/// Observable wrapper the screens share, so a star toggled in one place shows everywhere.
@MainActor
public final class FavoritesModel: ObservableObject {
    @Published public private(set) var entries: [FavoriteEntry] = []
    private let store: FavoritesStore

    public init(store: FavoritesStore) {
        self.store = store
        entries = store.all()
    }

    public func contains(_ ref: ContentRef) -> Bool { entries.contains { $0.ref == ref } }

    @discardableResult
    public func toggle(_ ref: ContentRef) -> Bool {
        let saved = store.toggle(ref, at: Date())
        entries = store.all()
        return saved
    }

    public func remove(_ ref: ContentRef) {
        store.remove(ref)
        entries = store.all()
    }

    public func clear() {
        store.clear()
        entries = []
    }
}
