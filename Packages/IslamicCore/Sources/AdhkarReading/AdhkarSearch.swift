import Foundation
import IslamicCore
import ContentKit

public struct DevotionalSearchResult: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case collection
        case item
    }

    public let kind: Kind
    public let match: SearchMatchKind
    public let order: Int
    public let collection: ContentRef
    public let collectionTitle: String
    public let collectionKind: DevotionalCollection.Kind
    public let item: ContentRef?
    public let itemOrder: Int?
    public let matchedText: String
    public let highlight: Range<Int>?

    public var id: String { item?.string ?? collection.string }
}

/// Offline search over collection titles and every dhikr and dua. Titles before texts at the
/// same match strength; equal results keep book order.
public final class DevotionalSearchIndex: Sendable {
    struct Entry: Sendable {
        let kind: DevotionalSearchResult.Kind
        let order: Int
        let collection: DevotionalCollection
        let item: DevotionalItem?
        let text: String
        let normalized: NormalizedSearchText
    }

    let entries: [Entry]

    public init(library: AdhkarLibrary) {
        var entries: [Entry] = []
        for collection in library.collections {
            entries.append(Entry(kind: .collection, order: entries.count, collection: collection, item: nil,
                                 text: collection.title,
                                 normalized: ArabicSearchNormalizer.normalizeMapped(collection.title)))
            for item in collection.items {
                entries.append(Entry(kind: .item, order: entries.count, collection: collection, item: item,
                                     text: item.text,
                                     normalized: ArabicSearchNormalizer.normalizeMapped(item.text,
                                                                                         daggerAlefAsAlef: true)))
            }
        }
        self.entries = entries
    }

    public var entryCount: Int { entries.count }

    public func search(_ query: String, kind: DevotionalCollection.Kind? = nil) -> [DevotionalSearchResult] {
        let key = ArabicSearchNormalizer.normalize(query)
        guard !key.isEmpty else { return [] }
        let words = SearchMatcher.words(key)
        var results: [DevotionalSearchResult] = []
        for entry in entries {
            if let kind, entry.collection.kind != kind { continue }
            guard let match = SearchMatcher.match(entry.normalized.key, key: key, words: words) else { continue }
            let excerpt = SearchMatcher.excerpt(entry.text, normalized: entry.normalized, key: key, words: words)
            results.append(DevotionalSearchResult(kind: entry.kind, match: match, order: entry.order,
                                                  collection: entry.collection.ref,
                                                  collectionTitle: entry.collection.title,
                                                  collectionKind: entry.collection.kind,
                                                  item: entry.item?.ref, itemOrder: entry.item?.order,
                                                  matchedText: excerpt.text, highlight: excerpt.highlight))
        }
        return results.sorted {
            ($0.match, $0.kind == .collection ? 0 : 1, $0.order) < ($1.match, $1.kind == .collection ? 0 : 1, $1.order)
        }
    }
}

/// Arabic text for VoiceOver and the screens.
public enum DevotionalAccessibility {
    public static func itemPosition(_ index: Int, of count: Int) -> String { "\(index + 1) من \(count)" }

    /// «مرة واحدة», «مرتان», «3 مرات», «33 مرة».
    public static func repetitions(_ count: Int) -> String {
        switch count {
        case 1: return "مرة واحدة"
        case 2: return "مرتان"
        case 3...10: return "\(count) مرات"
        default: return "\(count) مرة"
        }
    }

    public static func remaining(_ count: Int) -> String {
        count == 0 ? "اكتمل" : "متبقٍّ \(repetitions(count))"
    }

    public static func collectionLabel(_ collection: DevotionalCollection, completedToday: Bool) -> String {
        let noun = collection.kind == .adhkar ? "أذكار" : "أدعية"
        var label = "\(collection.title)، \(collection.items.count) \(noun)"
        if completedToday { label += "، أُتمّت اليوم" }
        return label
    }

    public static func searchResultLabel(_ result: DevotionalSearchResult) -> String {
        switch result.kind {
        case .collection: return "قسم، \(result.collectionTitle)"
        case .item:
            let noun = result.collectionKind == .adhkar ? "ذكر" : "دعاء"
            return "\(noun) \(result.itemOrder ?? 1)، \(result.collectionTitle)"
        }
    }

    public static let counterHint = "اضغط مرتين للعدّ"
    public static let reviewNotice = "هذا النص لم يُراجَع بعد مراجعةً علمية."
}
