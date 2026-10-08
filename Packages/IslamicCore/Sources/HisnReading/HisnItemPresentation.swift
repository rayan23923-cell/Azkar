import Foundation
import IslamicCore

/// What the reader screen shows for one item, and nothing else. Review state, correction
/// and decision ids, hashes, source counts and provenance stay in the domain.
public struct HisnItemPresentation: Equatable, Sendable {
    /// The bundled Arabic text, unchanged.
    public let text: String
    /// Each reference exactly as the source prints it (shown under «المصدر»).
    public let sources: [String]

    public init(item: HisnItem) {
        text = item.arabicText
        sources = item.references.map(\.originalText).filter { !$0.isEmpty }
    }
}

extension HisnReader {
    public var presentation: HisnItemPresentation { HisnItemPresentation(item: currentItem) }
}
