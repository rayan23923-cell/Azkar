import Foundation

/// The sections PiP can show.
public enum PiPContentType: String, Codable, CaseIterable, Sendable {
    case quran
    case hisn
    case dhikr
    case dua
    case prayer

    /// The section name drawn in the PiP header.
    public var sectionTitle: String {
        switch self {
        case .quran: return "القرآن الكريم"
        case .hisn: return "حصن المسلم"
        case .dhikr: return "الأذكار"
        case .dua: return "الأدعية"
        case .prayer: return "مواقيت الصلاة"
        }
    }
}

/// Which typeface the text is drawn in: the bundled Quran font for verses, the system Arabic
/// font for everything else.
public enum PiPTextStyle: String, Codable, Sendable {
    case standard
    case quran
}

/// A repetition counter PiP can advance (Hisn Al-Muslim): the item's required count and how
/// many recitations are done. Read from the section's own counter, never from display text.
public struct PiPRepetition: Equatable, Sendable {
    public let completed: Int
    public let total: Int

    public init(completed: Int, total: Int) {
        self.total = max(1, total)
        self.completed = min(max(0, completed), self.total)
    }

    public var isComplete: Bool { completed >= total }
    /// The recitation in progress (1-based), or the total once complete.
    public var current: Int { min(completed + 1, total) }
}

/// The item a section puts in the PiP window, read from the section's own reader. PiP owns none
/// of it: the text is the stored one, unchanged.
public struct PiPContent: Equatable, Sendable {
    public let contentType: PiPContentType
    /// The item (`quran:2:10`, a Hisn item id, `adhkar:dhikr-morning-002`…).
    public let contentID: String
    /// What the item belongs to (a surah, a chapter, a collection).
    public let containerID: String
    /// «سورة البقرة», «أذكار الصباح»…
    public let title: String
    /// «الآية 10», «الذكر 4»…
    public let subtitle: String
    public let text: String
    public let textStyle: PiPTextStyle
    /// 0-based position in the container.
    public let index: Int
    public let total: Int
    /// A counter line such as «التكرار 2 من 3», or nil when the item has none.
    public let detail: String?
    /// The counter the skip-forward button advances in PiP; nil when PiP does not count this item.
    public let repetition: PiPRepetition?

    public init(contentType: PiPContentType, contentID: String, containerID: String, title: String,
                subtitle: String, text: String, textStyle: PiPTextStyle = .standard, index: Int, total: Int,
                detail: String? = nil, repetition: PiPRepetition? = nil) {
        self.contentType = contentType
        self.contentID = contentID
        self.containerID = containerID
        self.title = title
        self.subtitle = subtitle
        self.text = text
        self.textStyle = textStyle
        self.index = index
        self.total = max(1, total)
        self.detail = detail
        self.repetition = repetition
    }

    public var isFirst: Bool { index <= 0 }
    public var isLast: Bool { index >= total - 1 }
}

/// What the window draws for one frame: the item, the page of its text, and the playback state.
public struct PiPFrame: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        /// No recording: text only. Play shows the next page of a long text, pause the previous.
        case text
        /// A production recording is loaded for the item.
        case audio
    }

    public let content: PiPContent
    /// The text of the page shown (the whole text when it fits one page).
    public let pageText: String
    /// 0-based.
    public let page: Int
    public let pageCount: Int
    /// The point size the body is drawn at (the same for every page of an item).
    public let fontSize: Double
    public let mode: Mode
    /// What the system play / pause button shows: pause while this is true. With a recording,
    /// whether it plays. In text mode, true while the button's next tap goes back a page.
    public let isPlaying: Bool
    /// Where the system PiP progress bar stands: seconds, and the rate it moves at.
    public let time: Double
    public let duration: Double
    public let rate: Double

    public init(content: PiPContent, pageText: String, page: Int, pageCount: Int, fontSize: Double, mode: Mode,
                isPlaying: Bool, time: Double, duration: Double, rate: Double) {
        self.content = content
        self.pageText = pageText
        self.page = page
        self.pageCount = max(1, pageCount)
        self.fontSize = fontSize
        self.mode = mode
        self.isPlaying = isPlaying
        self.time = time
        self.duration = duration
        self.rate = rate
    }

    /// The counter line, drawn large near the top where no system control sits: the item's
    /// counter and what skip forward does with it. Nil when the item has no counter.
    public var counterLine: String? {
        var parts: [String] = []
        if let detail = content.detail { parts.append(detail) }
        // The skip-forward button counts a recitation, then moves on once the count is done.
        if let repetition = content.repetition { parts.append(repetition.isComplete ? "⏩ التالي" : "⏩ عُدّ") }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    /// The information line above the system progress bar: what play / pause does next, the
    /// position and the page.
    public var infoLine: String {
        var parts: [String] = []
        switch mode {
        case .audio: parts.append(isPlaying ? "▶︎ يُشغَّل" : "⏸ متوقف")
        // The play / pause button turns the pages: say which way its next tap goes.
        case .text: if pageCount > 1 { parts.append(isPlaying ? "⏸ الصفحة السابقة" : "▶︎ الصفحة التالية") }
        }
        parts.append("\(content.index + 1) من \(content.total)")
        if pageCount > 1 { parts.append("صفحة \(page + 1) من \(pageCount)") }
        return parts.joined(separator: "  ·  ")
    }

    /// Both lines, right to left: the counter first (it is what a reciter looks for), then the
    /// information line.
    public var footer: String {
        [counterLine, infoLine].compactMap { $0 }.joined(separator: "  ·  ")
    }

    /// 0...1 for the progress bar: the recording's position, or the item's place in its container.
    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(time / duration, 0), 1)
    }
}
