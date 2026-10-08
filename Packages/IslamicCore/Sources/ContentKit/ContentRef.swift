import Foundation

/// A stable reference to one piece of content, by kind and id (never by order or text).
/// Stored as "kind:id", e.g. "hisn:hisn-001-01", "quran:2:255", "adhkar:morning-01".
public struct ContentRef: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// A Quran verse ("surah:ayah") or a surah ("surah").
        case quran
        /// A Hisn item ("hisn-001-01") or a presentation section ("hisn-ch-001").
        case hisn
        /// A dhikr item or a dhikr group.
        case adhkar
        /// A dua item or a dua category.
        case dua
    }

    public let kind: Kind
    public let id: String

    public init(_ kind: Kind, _ id: String) {
        self.kind = kind
        self.id = id
    }

    /// Parses "kind:id"; nil for anything else.
    public init?(string: String) {
        guard let colon = string.firstIndex(of: ":"),
              let kind = Kind(rawValue: String(string[..<colon])) else { return nil }
        let id = String(string[string.index(after: colon)...])
        guard !id.isEmpty else { return nil }
        self.init(kind, id)
    }

    public var string: String { "\(kind.rawValue):\(id)" }
    public var description: String { string }

    public static func < (lhs: ContentRef, rhs: ContentRef) -> Bool { lhs.string < rhs.string }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let ref = ContentRef(string: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "bad content reference \(raw)")
        }
        self = ref
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }
}

public extension ContentRef {
    static func quranVerse(surah: Int, ayah: Int) -> ContentRef { ContentRef(.quran, "\(surah):\(ayah)") }
    static func quranSurah(_ surah: Int) -> ContentRef { ContentRef(.quran, "\(surah)") }
    static func hisnItem(_ id: String) -> ContentRef { ContentRef(.hisn, id) }
    static func hisnSection(_ id: String) -> ContentRef { ContentRef(.hisn, id) }
    static func dhikr(_ id: String) -> ContentRef { ContentRef(.adhkar, id) }
    static func dhikrGroup(_ id: String) -> ContentRef { ContentRef(.adhkar, "group:\(id)") }
    static func dua(_ id: String) -> ContentRef { ContentRef(.dua, id) }
    static func duaCategory(_ id: String) -> ContentRef { ContentRef(.dua, "category:\(id)") }
}
