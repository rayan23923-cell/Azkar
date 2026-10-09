import Foundation
import IslamicCore

/// Reading state for one chapter. Navigation and repetition are the domain `HisnSession`
/// and its `SessionCursor`; this type only names their states for the reader screen.
public struct HisnReader: Equatable {
    /// How the current item's repetition is shown.
    public enum Repetition: Equatable {
        /// The content states a count above one: shown as "completed / total".
        case counted(completed: Int, total: Int)
        /// The content states a count of one.
        case once
        /// The content states no count: read once, and no number is shown.
        case unstated
    }

    /// Result of a recitation tap.
    public enum Step: Equatable {
        /// Counted; still on the same item with this many left.
        case counted(remaining: Int)
        /// The item is done; now on the next one.
        case movedToNext
        /// The last item is done; the chapter is complete. The reader stays in this chapter.
        case completed
    }

    public let chapter: HisnChapter
    public private(set) var session: HisnSession
    /// Set when the reader pressed «التالي» on the last item: the chapter is complete
    /// without counting repetitions that were not recited.
    private var endedByNavigation = false

    /// Opens a chapter at a display item, optionally with repetitions already counted.
    /// Returns nil for an empty chapter or an out-of-range item. Counts at or beyond the
    /// item's total start the item again.
    public init?(chapter: HisnChapter, itemIndex: Int = 0, completedRepetitions: Int = 0) {
        guard var session = HisnSession(chapter: chapter, startIndex: itemIndex) else { return nil }
        let required = session.cursor.requiredRepetitions
        if completedRepetitions > 0 && completedRepetitions < required {
            for _ in 0..<completedRepetitions { session.cursor.advance() }
        }
        self.chapter = chapter
        self.session = session
    }

    public var currentItem: HisnItem { session.currentItem }
    /// 0-based position among the chapter's display items.
    public var itemIndex: Int { session.cursor.index }
    /// 1-based, for "item n of m".
    public var itemNumber: Int { itemIndex + 1 }
    public var itemCount: Int { session.cursor.count }
    public var isFirstItem: Bool { session.cursor.isFirst }
    public var isLastItem: Bool { session.cursor.isLast }
    public var isCompleted: Bool { session.cursor.isFinished || endedByNavigation }
    public var completedRepetitions: Int { session.cursor.completedRepetitions }

    /// 0...1 over display items (not book item numbers): items finished so far.
    public var progress: Double { isCompleted ? 1 : session.progress }

    public var repetition: Repetition {
        switch currentItem.repetition.count {
        case nil: return .unstated
        case let count? where count > 1: return .counted(completed: completedRepetitions, total: count)
        default: return .once
        }
    }

    /// One recitation of the current item. Moves on only after the stated count; an item
    /// without a stated count is read once. Never moves into another chapter.
    @discardableResult
    public mutating func recite() -> Step {
        guard !isCompleted else { return .completed }
        switch session.cursor.advance() {
        case .repeated(let remaining): return .counted(remaining: remaining)
        case .movedToNext: return .movedToNext
        case .finished: return .completed
        }
    }

    /// Next item, or the completion state after the last one.
    public mutating func next() {
        guard !isCompleted else { return }
        if !session.next() { endedByNavigation = true }
    }

    /// Previous item. From the completion state, back to the last item.
    public mutating func previous() {
        if isCompleted {
            endedByNavigation = false
            session.cursor.jump(to: itemIndex)
            return
        }
        session.previous()
    }

    /// «إعادة»: the first item, nothing counted.
    public mutating func restart() {
        endedByNavigation = false
        session.restart()
    }

    /// Repetitions counted on each item of the chapter, by item id, to keep across launches.
    public var itemCounts: [String: Int] {
        let items = session.cursor.items
        return Dictionary(session.cursor.counts.map { (items[$0.key].id, $0.value) }, uniquingKeysWith: { Swift.max($0, $1) })
    }

    /// Puts back counts saved from `itemCounts`: going back to an item shows its count, and a
    /// finished item is not counted again. Unknown ids are ignored.
    public mutating func restore(itemCounts: [String: Int]) {
        guard !itemCounts.isEmpty else { return }
        var byIndex: [Int: Int] = [:]
        for (index, item) in session.cursor.items.enumerated() {
            if let count = itemCounts[item.id] { byIndex[index] = count }
        }
        session.cursor.restoreCounts(byIndex)
    }

    /// Where to resume; nil once the chapter is complete.
    public func position(savedAt date: Date) -> HisnReadingPosition? {
        guard !isCompleted else { return nil }
        return HisnReadingPosition(chapterId: chapter.id, itemId: currentItem.id, itemIndex: itemIndex,
                                   completedRepetitions: completedRepetitions, savedAt: date)
    }
}
