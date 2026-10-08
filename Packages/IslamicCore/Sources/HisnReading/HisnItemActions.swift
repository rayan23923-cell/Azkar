import Foundation
import IslamicCore

/// What the item actions copy and share: the current item's stored Arabic text, exactly as
/// the domain holds it and the reader shows it, and the chapter title for the share card.
/// Nothing else: no ids, review state, corrections, provenance or references.
///
/// The text is `HisnItem.arabicText` unchanged. For the three items whose text carries
/// classified non-recitation parts (narration, closing, labels), those parts stay where the
/// source puts them: removing them would rewrite the stored text, which this layer never does.
public struct HisnShareContent: Equatable, Sendable {
    public let text: String
    public let chapterTitle: String

    public init(item: HisnItem, chapterTitle: String) {
        text = item.arabicText
        self.chapterTitle = chapterTitle
    }
}

extension HisnReader {
    /// The share content of the item on screen.
    public var shareContent: HisnShareContent {
        HisnShareContent(item: currentItem, chapterTitle: chapter.titleArabic)
    }
}

/// Feedback moments. Only these produce haptics; nothing is played per frame or per tap.
public enum HisnHapticEvent: Equatable, Sendable {
    /// The last required recitation of an item.
    case itemCompleted
    /// The chapter is complete.
    case chapterCompleted
    /// The text reached the clipboard.
    case copied
    /// The share card was generated.
    case cardReady
}

/// Plays haptic feedback. The app's implementation uses the system generators and honours
/// the haptics setting; tests record events. Feedback is never required for anything to work.
@MainActor
public protocol HisnHaptics: AnyObject {
    func play(_ event: HisnHapticEvent)
}

/// The clipboard, behind a protocol so copying can be tested.
@MainActor
public protocol HisnTextPasteboard: AnyObject {
    var string: String? { get set }
}

/// Copy and share bookkeeping for the item actions. Sharing itself is the system share
/// sheet, driven by the app.
@MainActor
public final class HisnItemActions {
    private let pasteboard: HisnTextPasteboard
    private let haptics: HisnHaptics?

    public init(pasteboard: HisnTextPasteboard, haptics: HisnHaptics?) {
        self.pasteboard = pasteboard
        self.haptics = haptics
    }

    /// Puts the text on the clipboard. True, with the copy feedback, only when the clipboard
    /// holds exactly that text afterwards.
    @discardableResult
    public func copy(_ content: HisnShareContent) -> Bool {
        guard !content.text.isEmpty else { return false }
        pasteboard.string = content.text
        guard pasteboard.string == content.text else { return false }
        haptics?.play(.copied)
        return true
    }

    /// The text share payload: the dhikr text alone.
    public func textPayload(_ content: HisnShareContent) -> String? {
        content.text.isEmpty ? nil : content.text
    }

    /// Reports the card generation result; feedback only on success.
    public func cardGenerated(_ succeeded: Bool) {
        if succeeded { haptics?.play(.cardReady) }
    }
}
