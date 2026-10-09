import Foundation

/// The repetitions counted on each item of a chapter or collection today, so an item gone back
/// to after the app was closed shows its count again. Counts belong to the day they were
/// counted: a new day starts every item at zero. Keys are item ids within the container.
public protocol ItemCountStore: AnyObject {
    func counts(in container: ContentRef, on day: DayKey) -> [String: Int]
    /// Replaces the container's counts for the day; an empty map removes them.
    func save(_ counts: [String: Int], in container: ContentRef, on day: DayKey)
    func clear(_ container: ContentRef)
    func clearAll()
}

/// `{"day":"2026-10-09","containers":{"hisn:hisn-ch-027":{"hisn-027-04":3}},"version":1}` in
/// UserDefaults (key `itemCounts.v1`). Only one day is kept: writing on a new day drops the
/// previous day's counts. Unreadable data is removed and read as empty.
public final class UserDefaultsItemCountStore: ItemCountStore {
    public static let defaultKey = "itemCounts.v1"

    private struct File: Codable {
        var version = 1
        var day: String
        var containers: [String: [String: Int]] = [:]
    }

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = UserDefaultsItemCountStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func counts(in container: ContentRef, on day: DayKey) -> [String: Int] {
        guard let file = read(), file.day == day.string else { return [:] }
        return file.containers[container.string] ?? [:]
    }

    public func save(_ counts: [String: Int], in container: ContentRef, on day: DayKey) {
        var file = read().flatMap { $0.day == day.string ? $0 : nil } ?? File(day: day.string)
        let kept = counts.filter { $0.value > 0 }
        file.containers[container.string] = kept.isEmpty ? nil : kept
        write(file)
    }

    public func clear(_ container: ContentRef) {
        guard var file = read() else { return }
        file.containers[container.string] = nil
        write(file)
    }

    public func clearAll() { defaults.removeObject(forKey: key) }

    private func read() -> File? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let file = try? JSONDecoder().decode(File.self, from: data), file.version == 1 else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return file
    }

    private func write(_ file: File) {
        if file.containers.isEmpty {
            defaults.removeObject(forKey: key)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        if let data = try? encoder.encode(file) { defaults.set(data, forKey: key) }
    }
}

public final class InMemoryItemCountStore: ItemCountStore {
    public private(set) var stored: [ContentRef: (day: DayKey, counts: [String: Int])] = [:]
    public init() {}

    public func counts(in container: ContentRef, on day: DayKey) -> [String: Int] {
        guard let entry = stored[container], entry.day == day else { return [:] }
        return entry.counts
    }

    public func save(_ counts: [String: Int], in container: ContentRef, on day: DayKey) {
        let kept = counts.filter { $0.value > 0 }
        stored[container] = kept.isEmpty ? nil : (day, kept)
    }

    public func clear(_ container: ContentRef) { stored[container] = nil }
    public func clearAll() { stored = [:] }
}
