import Foundation

/// The four sections PiP can show.
public enum PiPContentType: String, Codable, CaseIterable, Sendable {
    case quran
    case hisn
    case dhikr
    case dua

    /// The section name drawn in the PiP header.
    public var sectionTitle: String {
        switch self {
        case .quran: return "القرآن الكريم"
        case .hisn: return "حصن المسلم"
        case .dhikr: return "الأذكار"
        case .dua: return "الأدعية"
        }
    }
}

/// Which typeface the text is drawn in: the bundled Quran font for verses, the system Arabic
/// font for everything else.
public enum PiPTextStyle: String, Codable, Sendable {
    case standard
    case quran
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

    public init(contentType: PiPContentType, contentID: String, containerID: String, title: String,
                subtitle: String, text: String, textStyle: PiPTextStyle = .standard, index: Int, total: Int,
                detail: String? = nil) {
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
    }

    public var isFirst: Bool { index <= 0 }
    public var isLast: Bool { index >= total - 1 }
}

/// What the window draws for one frame: the item, the page of its text, and the playback state.
public struct PiPFrame: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        /// No recording: text only. Play turns the pages of a long text.
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

    /// The footer line: state, counter, position and page, right to left.
    public var footer: String {
        var parts: [String] = []
        switch mode {
        case .audio: parts.append(isPlaying ? "▶︎ يُشغَّل" : "⏸ متوقف")
        case .text: if pageCount > 1 && isPlaying { parts.append("▶︎ تقليب الصفحات") }
        }
        if let detail = content.detail { parts.append(detail) }
        parts.append("\(content.index + 1) من \(content.total)")
        if pageCount > 1 { parts.append("صفحة \(page + 1) من \(pageCount)") }
        return parts.joined(separator: "  ·  ")
    }

    /// 0...1 for the progress bar: the recording's position, or the item's place in its container.
    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(time / duration, 0), 1)
    }
}
