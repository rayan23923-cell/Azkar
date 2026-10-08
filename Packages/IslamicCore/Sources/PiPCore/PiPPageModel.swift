import Foundation

/// How one item's text is laid out in the PiP window: the size it is drawn at and its pages.
/// Pages are exact slices of the text; joined, they give back the text unchanged.
public struct PiPPagination: Equatable, Sendable {
    public let fontSize: Double
    public let pages: [String]

    public init(fontSize: Double, pages: [String]) {
        self.fontSize = fontSize
        self.pages = pages.isEmpty ? [""] : pages
    }
}

/// Measures text for the PiP window. The app and the tests use the Core Text paginator
/// (`PiPRendering`); engine tests may use a simple fake.
public protocol PiPPaginating {
    func paginate(_ text: String, style: PiPTextStyle) -> PiPPagination
}

/// The presentation level of PiP navigation: which page of the current item is shown. It never
/// changes the item; that is content navigation (`PiPNavigation`).
public struct PiPPageModel: Equatable, Sendable {
    public let contentID: String
    public let pagination: PiPPagination
    public private(set) var currentPage = 0

    public init(contentID: String, pagination: PiPPagination, currentPage: Int = 0) {
        self.contentID = contentID
        self.pagination = pagination
        self.currentPage = min(max(0, currentPage), pagination.pages.count - 1)
    }

    public var totalPages: Int { pagination.pages.count }
    public var hasPages: Bool { totalPages > 1 }
    public var isFirstPage: Bool { currentPage == 0 }
    public var isLastPage: Bool { currentPage == totalPages - 1 }
    public var pageText: String { pagination.pages[currentPage] }

    /// False (and no move) on the last page.
    @discardableResult
    public mutating func nextPage() -> Bool {
        guard !isLastPage else { return false }
        currentPage += 1
        return true
    }

    /// False (and no move) on the first page.
    @discardableResult
    public mutating func previousPage() -> Bool {
        guard !isFirstPage else { return false }
        currentPage -= 1
        return true
    }
}

/// Splits a text into pages without changing it: every page is a contiguous slice, broken only
/// just after whitespace, and the pages joined give back the text exactly.
public enum PiPTextPaginator {
    /// - Parameter fits: whether a slice fits one page.
    public static func pages(_ text: String, fits: (Substring) -> Bool) -> [String] {
        guard !text.isEmpty else { return [] }
        // Break opportunities: just after each whitespace run.
        var breaks: [String.Index] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            if text[index].isWhitespace && (next == text.endIndex || !text[next].isWhitespace) {
                breaks.append(next)
            }
            index = next
        }
        if breaks.last != text.endIndex { breaks.append(text.endIndex) }

        var pages: [String] = []
        var start = text.startIndex
        var cursor = 0
        while start < text.endIndex {
            var end: String.Index?
            while cursor < breaks.count {
                let candidate = breaks[cursor]
                if candidate <= start { cursor += 1; continue }
                if fits(text[start..<candidate]) {
                    end = candidate
                    cursor += 1
                } else {
                    break
                }
            }
            // A single word longer than a page still gets its own page; text is never dropped.
            let pageEnd = end ?? breaks.first { $0 > start } ?? text.endIndex
            pages.append(String(text[start..<pageEnd]))
            start = pageEnd
        }
        return pages
    }
}
