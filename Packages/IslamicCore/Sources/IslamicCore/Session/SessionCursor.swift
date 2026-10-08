import Foundation

/// Content that a session may repeat before moving on.
public protocol RepeatableContent {
    /// How many times the item is said before the session moves on. Values below 1 count as 1.
    var repeatCount: Int { get }
}

extension QuranVerse: RepeatableContent {
    public var repeatCount: Int { 1 }
}

extension DuaItem: RepeatableContent {
    public var repeatCount: Int { 1 }
}

extension DhikrItem: RepeatableContent {}

/// Position inside an ordered, non-empty list of items, independent of UI, audio and PiP.
///
/// - `advance()` is the session step: it counts one repetition and moves to the
///   next item only after the current item's repetitions are complete.
/// - `next()` / `previous()` are explicit navigation: they move at once and reset
///   the repetition count. Both stop at the ends of the list.
public struct SessionCursor<Item: RepeatableContent & Equatable>: Equatable {
    public enum Step: Equatable {
        /// Counted a repetition; still on the same item with this many left.
        case repeated(remaining: Int)
        /// Repetitions done; now on the next item.
        case movedToNext
        /// Repetitions of the last item done; the session is complete.
        case finished
    }

    public let items: [Item]
    public private(set) var index: Int
    /// Repetitions already completed for the current item.
    public private(set) var completedRepetitions: Int
    public private(set) var isFinished: Bool

    /// Returns nil for an empty list or an out-of-range start index.
    public init?(items: [Item], startIndex: Int = 0) {
        guard items.indices.contains(startIndex) else { return nil }
        self.items = items
        self.index = startIndex
        self.completedRepetitions = 0
        self.isFinished = false
    }

    public var current: Item { items[index] }
    public var count: Int { items.count }
    public var isFirst: Bool { index == 0 }
    public var isLast: Bool { index == items.count - 1 }
    public var requiredRepetitions: Int { max(1, current.repeatCount) }
    public var remainingRepetitions: Int { isFinished ? 0 : requiredRepetitions - completedRepetitions }
    /// 0...1 across the whole list, counting completed items.
    public var progress: Double {
        isFinished ? 1 : Double(index) / Double(items.count)
    }

    @discardableResult
    public mutating func advance() -> Step {
        guard !isFinished else { return .finished }
        completedRepetitions += 1
        if completedRepetitions < requiredRepetitions {
            return .repeated(remaining: requiredRepetitions - completedRepetitions)
        }
        if isLast {
            isFinished = true
            return .finished
        }
        index += 1
        completedRepetitions = 0
        return .movedToNext
    }

    /// Moves to the next item. Returns false (and stays) on the last item.
    @discardableResult
    public mutating func next() -> Bool {
        guard !isLast else { return false }
        move(to: index + 1)
        return true
    }

    /// Moves to the previous item. Returns false (and stays) on the first item.
    @discardableResult
    public mutating func previous() -> Bool {
        guard !isFirst else { return false }
        move(to: index - 1)
        return true
    }

    /// Jumps to an item. Returns false for an out-of-range index.
    @discardableResult
    public mutating func jump(to newIndex: Int) -> Bool {
        guard items.indices.contains(newIndex) else { return false }
        move(to: newIndex)
        return true
    }

    private mutating func move(to newIndex: Int) {
        index = newIndex
        completedRepetitions = 0
        isFinished = false
    }
}
