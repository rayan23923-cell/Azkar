import Foundation

/// What the reader can narrow results to. The content has no reliable dhikr / dua split, so
/// texts are not divided further.
public enum HisnSearchFilter: String, CaseIterable, Hashable, Sendable {
    case all
    case chapters
    case texts
}

/// One search result. Everything the UI shows or opens is a field here; nothing is parsed
/// back out of text.
public struct HisnSearchResult: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// A section title matched; opens the chapter.
        case chapter
        /// A display item's text matched; opens that item.
        case item
    }

    /// Lower ranks come first.
    public enum Rank: Int, Comparable, CaseIterable, Sendable {
        /// The chapter title is the query.
        case chapterExact = 1
        /// The chapter title starts with the query.
        case chapterPrefix
        /// The text is the query.
        case textExact
        /// The text starts with the query.
        case textPrefix
        /// Every query word appears somewhere in the chapter title.
        case chapterPartial
        /// Every query word appears somewhere in the text.
        case textPartial

        public static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let kind: Kind
    public let rank: Rank
    /// Book order of the matched title or item: equal ranks keep this order.
    public let order: Int
    public let chapterId: String
    public let chapterTitle: String
    /// Display items in the chapter, for «الذكر n من m».
    public let chapterItemCount: Int
    /// Nil for a chapter result.
    public let itemId: String?
    /// The display item's index in its chapter; nil for a chapter result.
    public let itemIndex: Int?
    /// What the row shows: the chapter title, or the stored item text (an excerpt of it with
    /// «…» at a cut end when the text is long). Characters are copied, never changed.
    public let matchedText: String
    /// The whole words of `matchedText` that contain the match, as character offsets. Whole
    /// words only, so highlighting never splits a word's letters (and their joining).
    public let highlight: Range<Int>?

    public var id: String { kind == .chapter ? "c:\(chapterId)" : "i:\(itemId ?? "")" }
}
