import Foundation

extension HisnItem: RepeatableContent {
    /// The structured count, or 1 when none could be established (the text still says how often).
    public var repeatCount: Int { repetition.count ?? 1 }
}

/// Reading position in Hisn Al-Muslim: one chapter, or the whole book in order.
/// Content and a cursor only; no audio, PiP, timers or persistence.
public struct HisnSession: Equatable {
    public enum Scope: Equatable {
        case chapter(id: String)
        case book
    }

    public let scope: Scope
    public var cursor: SessionCursor<HisnItem>
    private let chapterTitles: [String: String]

    /// One chapter. Returns nil for an empty chapter or an out-of-range start index.
    public init?(chapter: HisnChapter, startIndex: Int = 0) {
        guard chapter.items.allSatisfy({ $0.chapterId == chapter.id }),
              let cursor = SessionCursor(items: chapter.items, startIndex: startIndex) else { return nil }
        self.scope = .chapter(id: chapter.id)
        self.cursor = cursor
        self.chapterTitles = [chapter.id: chapter.titleArabic]
    }

    /// The whole book, chapter after chapter. Returns nil for an empty book or a bad start index.
    public init?(book: HisnBook, startIndex: Int = 0) {
        guard let cursor = SessionCursor(items: book.allItems, startIndex: startIndex) else { return nil }
        self.scope = .book
        self.cursor = cursor
        self.chapterTitles = Dictionary(uniqueKeysWithValues: book.chapters.map { ($0.id, $0.titleArabic) })
    }

    public var currentItem: HisnItem { cursor.current }
    public var currentChapterId: String { cursor.current.chapterId }
    public var currentChapterTitle: String? { chapterTitles[currentChapterId] }
    /// 0...1 across the session.
    public var progress: Double { cursor.progress }

    @discardableResult
    public mutating func next() -> Bool { cursor.next() }

    @discardableResult
    public mutating func previous() -> Bool { cursor.previous() }

    /// Back to the first item with no repetitions counted.
    public mutating func restart() { cursor.restart() }
}
