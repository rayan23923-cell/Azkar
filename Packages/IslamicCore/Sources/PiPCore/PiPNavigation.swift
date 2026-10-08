import Foundation

/// The two levels of PiP navigation behind the one pair of system skip buttons.
///
/// - Presentation: the pages of a long item.
/// - Content: the previous / next item (verse, dhikr, dua, Hisn item).
///
/// Next shows the next page while the item has one, and only then the next item; previous
/// mirrors it. A single-page item has no page step. Nothing moves past the first or last item:
/// PiP never completes a chapter or opens another surah or collection.
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
        /// At the first / last page of the first / last item.
        case none
    }

    public static func resolve(_ direction: Direction, pages: PiPPageModel, content: PiPContent) -> Action {
        switch direction {
        case .next:
            if !pages.isLastPage { return .nextPage }
            return content.isLast ? .none : .nextItem
        case .previous:
            if !pages.isFirstPage { return .previousPage }
            return content.isFirst ? .none : .previousItem
        }
    }
}
