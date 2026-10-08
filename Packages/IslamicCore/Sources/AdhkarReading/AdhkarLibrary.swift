import Foundation
import IslamicCore
import ContentKit

/// One dhikr or dua, as the reader, search and favorites see it. The text and source are the
/// stored ones, unchanged.
public struct DevotionalItem: Identifiable, Hashable, Sendable, RepeatableContent {
    public let ref: ContentRef
    public let collection: ContentRef
    /// 1-based position in its collection.
    public let order: Int
    public let text: String
    public let source: String
    /// Duas are said once.
    public let repeatCount: Int
    public let quranRef: QuranReference?
    public let reviewStatus: ContentReviewStatus

    public var id: String { ref.string }

    public init(dhikr item: DhikrItem) {
        ref = .dhikr(item.id)
        collection = .dhikrGroup(item.group.rawValue)
        order = item.order
        text = item.arabicText
        source = item.source
        repeatCount = max(1, item.repeatCount)
        quranRef = item.quranRef
        reviewStatus = item.reviewStatus
    }

    public init(dua item: DuaItem) {
        ref = .dua(item.id)
        collection = .duaCategory(item.category.rawValue)
        order = item.order
        text = item.arabicText
        source = item.source
        repeatCount = 1
        quranRef = item.quranRef
        reviewStatus = item.reviewStatus
    }
}

/// A dhikr group (morning, evening…) or a dua category, in book order.
public struct DevotionalCollection: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case adhkar
        case dua
    }

    public let kind: Kind
    public let ref: ContentRef
    public let title: String
    public let items: [DevotionalItem]

    public var id: String { ref.string }
    /// Total repetitions in the collection (a dhikr said 3 times counts 3).
    public var totalRepetitions: Int { items.reduce(0) { $0 + $1.repeatCount } }
}

/// The bundled adhkar and duas, loaded and checked once.
public struct AdhkarLibrary: Sendable {
    public let adhkar: [DevotionalCollection]
    public let duas: [DevotionalCollection]

    public init(adhkar: [DevotionalCollection], duas: [DevotionalCollection]) {
        self.adhkar = adhkar
        self.duas = duas
    }

    public static func load(dhikr: DhikrRepository = BundledDhikrRepository(),
                            dua: DuaRepository = BundledDuaRepository()) async throws -> AdhkarLibrary {
        var adhkar: [DevotionalCollection] = []
        for group in try await dhikr.loadGroups() {
            let items = try await dhikr.loadItems(group: group.id).map(DevotionalItem.init(dhikr:))
            adhkar.append(DevotionalCollection(kind: .adhkar, ref: .dhikrGroup(group.id.rawValue),
                                               title: group.titleArabic, items: items))
        }
        var duas: [DevotionalCollection] = []
        for category in try await dua.loadCategories() {
            let items = try await dua.loadItems(category: category.id).map(DevotionalItem.init(dua:))
            duas.append(DevotionalCollection(kind: .dua, ref: .duaCategory(category.id.rawValue),
                                             title: category.titleArabic, items: items))
        }
        return AdhkarLibrary(adhkar: adhkar, duas: duas)
    }

    /// Adhkar first, then duas.
    public var collections: [DevotionalCollection] { adhkar + duas }
    public var itemCount: Int { collections.reduce(0) { $0 + $1.items.count } }

    public func collection(_ ref: ContentRef) -> DevotionalCollection? {
        collections.first { $0.ref == ref }
    }

    /// The collection holding an item, and the item's index in it.
    public func locate(_ item: ContentRef) -> (collection: DevotionalCollection, index: Int)? {
        for collection in collections {
            if let index = collection.items.firstIndex(where: { $0.ref == item }) { return (collection, index) }
        }
        return nil
    }

    public func item(_ ref: ContentRef) -> DevotionalItem? {
        locate(ref).map { $0.collection.items[$0.index] }
    }
}
