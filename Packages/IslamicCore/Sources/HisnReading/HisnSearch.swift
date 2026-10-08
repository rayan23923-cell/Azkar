import Foundation
import IslamicCore

/// The search key rules of `tools/content/build_content.py` (`search_text`), applied to what
/// the reader types, so a query compares with the domain `searchText` fields: no marks or
/// tatweel, one alef form, ى→ي, ة→ه, Arabic letters and single spaces only.
public enum HisnSearchKey {
    public static func make(_ text: String) -> String {
        var key = String.UnicodeScalarView()
        var pendingSpace = false
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x0610...0x061A).contains(value) || (0x064B...0x065F).contains(value) || value == 0x0670
                || (0x06D6...0x06ED).contains(value) || value == 0x0640 {
                continue
            }
            let letter: Unicode.Scalar
            switch value {
            case 0x0623, 0x0625, 0x0622, 0x0671: letter = "\u{0627}"
            case 0x0649: letter = "\u{064A}"
            case 0x0629: letter = "\u{0647}"
            default: letter = scalar
            }
            if (0x0621...0x064A).contains(letter.value) {
                if pendingSpace && !key.isEmpty { key.append(" ") }
                pendingSpace = false
                key.append(letter)
            } else {
                pendingSpace = true
            }
        }
        return String(key)
    }
}

public struct HisnSearchResult: Identifiable, Hashable, Sendable {
    public enum Match: Int, Comparable, Sendable {
        /// The query appears as whole words, in order.
        case exact
        /// Every query word appears, possibly inside longer words.
        case partial

        public static func < (lhs: Match, rhs: Match) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public enum Kind: Hashable, Sendable {
        /// The chapter title matched; opens the chapter's first item.
        case chapter
        /// An item's text matched; opens that item.
        case item
    }

    public let kind: Kind
    public let match: Match
    public let chapterId: String
    public let chapterTitle: String
    /// The display item to open (0 for a chapter match).
    public let itemIndex: Int
    /// The item's text as bundled, for the result row. Nil for a chapter match.
    public let itemText: String?

    public var id: String { "\(kind == .chapter ? "c" : "i"):\(chapterId):\(itemIndex)" }
}

/// Offline search over the bundled `searchText` fields. No network, no second content copy:
/// it keeps the domain's keys and points back at chapters and display items.
public struct HisnSearchIndex: Sendable {
    private struct Entry: Sendable {
        let kind: HisnSearchResult.Kind
        let key: String
        let chapterId: String
        let chapterTitle: String
        let itemIndex: Int
        let itemText: String?
    }

    private let entries: [Entry]

    public init(book: HisnBook) {
        var entries: [Entry] = []
        for chapter in book.chapters {
            entries.append(Entry(kind: .chapter, key: chapter.searchText, chapterId: chapter.id,
                                 chapterTitle: chapter.titleArabic, itemIndex: 0, itemText: nil))
            for (index, item) in chapter.items.enumerated() {
                entries.append(Entry(kind: .item, key: item.searchText, chapterId: chapter.id,
                                     chapterTitle: chapter.titleArabic, itemIndex: index, itemText: item.arabicText))
            }
        }
        self.entries = entries
    }

    /// Exact matches first, then partial ones, each in book order. An empty query (or one
    /// with no Arabic letters) returns nothing.
    public func search(_ query: String) -> [HisnSearchResult] {
        let key = HisnSearchKey.make(query)
        guard !key.isEmpty else { return [] }
        let words = key.split(separator: " ")
        let phrase = " \(key) "
        var exact: [HisnSearchResult] = []
        var partial: [HisnSearchResult] = []
        for entry in entries {
            let match: HisnSearchResult.Match
            if " \(entry.key) ".contains(phrase) {
                match = .exact
            } else if words.allSatisfy({ entry.key.contains($0) }) {
                match = .partial
            } else {
                continue
            }
            let result = HisnSearchResult(kind: entry.kind, match: match, chapterId: entry.chapterId,
                                          chapterTitle: entry.chapterTitle, itemIndex: entry.itemIndex,
                                          itemText: entry.itemText)
            if match == .exact { exact.append(result) } else { partial.append(result) }
        }
        return exact + partial
    }
}
