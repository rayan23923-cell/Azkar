import Foundation

/// What the system PiP buttons do. A sample-buffer PiP window has three: play / pause and skip
/// back / forward. Nothing drawn inside the window can be tapped.
///
/// - Presentation (play / pause, text without a recording): play shows the next page of a long
///   item, pause the previous one. They stop at the first and last page and never change the
///   item; a one-page item has nothing to turn.
/// - Content (skip back / forward): the previous / next item (verse, dhikr, dua, Hisn item).
///   Skip forward on an item PiP counts (`PiPContent.repetition`) records one recitation until
///   the count is complete; only then does it move on.
///
/// Nothing moves past the first or last item: PiP never opens another surah or collection.
public enum PiPNavigation {
    public enum Direction: Equatable, Sendable {
        case previous
        case next

        /// The system skip buttons report ±seconds; their sign is the direction.
        public init?(skip seconds: Double) {
            guard seconds.isFinite, seconds != 0 else { return nil }
            self = seconds > 0 ? .next : .previous
        }
    }

    public enum Action: Equatable, Sendable {
        case previousPage
        case nextPage
        case previousItem
        case nextItem
        case countRepetition
        /// At a boundary, or nothing to do (a one-page item has no page step).
        case none
    }

    /// Play / pause in text mode: play → next page, pause → previous page.
    public static func page(playing: Bool, pages: PiPPageModel) -> Action {
        if playing { return pages.isLastPage ? .none : .nextPage }
        return pages.isFirstPage ? .none : .previousPage
    }

    /// Skip back / forward.
    public static func resolve(_ direction: Direction, content: PiPContent) -> Action {
        switch direction {
        case .next:
            if let repetition = content.repetition {
                // Counting first; a complete count moves on (the provider decides what is next).
                return repetition.isComplete ? .nextItem : .countRepetition
            }
            return content.isLast ? .none : .nextItem
        case .previous:
            return content.isFirst ? .none : .previousItem
        }
    }
}
