import Foundation
import IslamicCore

/// The searchable form of the book, built once when the book loads and shared by every query.
/// Each presentation section's title and each display item's text has one entry, in book
/// order. Entries point back at the domain; the index keeps no edited copy of any text.
public final class HisnSearchIndex: Sendable {
    struct Entry: Sendable {
        let kind: HisnSearchResult.Kind
        /// Position in book order: the tie-breaker for equal ranks.
        let order: Int
        let chapterId: String
        let chapterTitle: String
        let chapterItemCount: Int
        let itemId: String?
        let itemIndex: Int?
        /// The domain text as stored (the title for a chapter entry).
        let text: String
        let normalized: HisnNormalizedText
    }

    let entries: [Entry]

    public init(book: HisnBook) {
        var entries: [Entry] = []
        for chapter in book.chapters {
            entries.append(Entry(kind: .chapter, order: entries.count, chapterId: chapter.id,
                                 chapterTitle: chapter.titleArabic, chapterItemCount: chapter.itemCount,
                                 itemId: nil, itemIndex: nil, text: chapter.titleArabic,
                                 normalized: HisnSearchNormalizer.normalizeMapped(chapter.titleArabic)))
            for (index, item) in chapter.items.enumerated() {
                entries.append(Entry(kind: .item, order: entries.count, chapterId: chapter.id,
                                     chapterTitle: chapter.titleArabic, chapterItemCount: chapter.itemCount,
                                     itemId: item.id, itemIndex: index, text: item.arabicText,
                                     normalized: HisnSearchNormalizer.normalizeMapped(item.arabicText)))
            }
        }
        self.entries = entries
    }

    /// Chapter (section title) entries.
    public var chapterEntryCount: Int { entries.lazy.filter { $0.kind == .chapter }.count }
    /// Display item entries.
    public var itemEntryCount: Int { entries.lazy.filter { $0.kind == .item }.count }
}
