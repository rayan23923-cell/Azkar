import Foundation
import IslamicCore

/// One row of the chapter index: a presentation section (133 in all), in the book's display order.
/// Everything here is read from the domain; nothing is typed in by the UI.
public struct HisnSectionEntry: Identifiable, Hashable, Sendable {
    public let id: String
    /// The domain title, shown as it is (chapter 27 arrives as «أذكار الصباح» and «أذكار المساء»).
    public let title: String
    public let itemCount: Int
    /// Set only for the morning / evening halves of chapter 27.
    public let timeOfDay: HisnPresentationSection?
    /// The canonical book chapter number: 27 for both halves of chapter 27.
    public let bookChapterNumber: Int?

    init(chapter: HisnChapter) {
        id = chapter.id
        title = chapter.titleArabic
        itemCount = chapter.itemCount
        timeOfDay = chapter.presentationSection
        bookChapterNumber = chapter.bookChapterNumber
    }
}

/// The loaded book as the reader sees it: the index and chapter lookup.
public struct HisnLibrary: Sendable {
    public let book: HisnBook
    public let sections: [HisnSectionEntry]
    private let chaptersById: [String: HisnChapter]

    public init(book: HisnBook) {
        self.book = book
        sections = book.chapters.map(HisnSectionEntry.init)
        chaptersById = Dictionary(uniqueKeysWithValues: book.chapters.map { ($0.id, $0) })
    }

    public func chapter(id: String) -> HisnChapter? { chaptersById[id] }

    /// The first section (in index order) holding the item, and its place there; nil for an
    /// unknown id. Used to open a saved item.
    public func locate(itemId: String) -> (chapter: HisnChapter, itemIndex: Int)? {
        for entry in sections {
            guard let chapter = chaptersById[entry.id],
                  let index = chapter.items.firstIndex(where: { $0.id == itemId }) else { continue }
            return (chapter, index)
        }
        return nil
    }

    /// The section after this one in index order (for «الباب التالي»); nil after the last.
    public func section(after id: String) -> HisnSectionEntry? {
        guard let index = sections.firstIndex(where: { $0.id == id }), index + 1 < sections.count else { return nil }
        return sections[index + 1]
    }
}
