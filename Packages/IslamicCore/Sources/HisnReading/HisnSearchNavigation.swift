import Foundation
import IslamicCore

/// Where opening a search result goes. Opening a result only moves the reader: it never
/// counts, completes or changes repetitions.
public struct HisnSearchDestination: Hashable, Sendable {
    public let chapterId: String
    public let itemIndex: Int
    /// Kept from the saved cursor when it is on this very item, otherwise zero.
    public let completedRepetitions: Int
    /// The item the reader marks briefly on arrival (item results only).
    public let highlightedItemId: String?

    /// Resolves a result against the loaded library. Nil when the result no longer points at
    /// a real chapter or item, so a stale result cannot open the wrong place.
    public static func resolve(_ result: HisnSearchResult, in library: HisnLibrary,
                               cursor: HisnReadingPosition?) -> HisnSearchDestination? {
        guard let chapter = library.chapter(id: result.chapterId), !chapter.items.isEmpty else { return nil }
        switch result.kind {
        case .chapter:
            // Like the index: the saved place when it is in this chapter, otherwise the start.
            if let cursor, cursor.chapterId == chapter.id,
               chapter.items.indices.contains(cursor.itemIndex),
               chapter.items[cursor.itemIndex].id == cursor.itemId {
                return HisnSearchDestination(chapterId: chapter.id, itemIndex: cursor.itemIndex,
                                             completedRepetitions: cursor.completedRepetitions,
                                             highlightedItemId: nil)
            }
            return HisnSearchDestination(chapterId: chapter.id, itemIndex: 0, completedRepetitions: 0,
                                         highlightedItemId: nil)
        case .item:
            guard let itemIndex = result.itemIndex, let itemId = result.itemId,
                  chapter.items.indices.contains(itemIndex), chapter.items[itemIndex].id == itemId else {
                return nil
            }
            let kept = cursor.flatMap { $0.chapterId == chapter.id && $0.itemId == itemId ? $0.completedRepetitions : nil }
            return HisnSearchDestination(chapterId: chapter.id, itemIndex: itemIndex,
                                         completedRepetitions: kept ?? 0, highlightedItemId: itemId)
        }
    }
}
