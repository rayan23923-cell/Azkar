import Foundation

/// Whether a text has been checked. Quranic text copied from Tanzil needs no
/// review; anything transcribed stays `reviewRequired` until a qualified
/// person checks text, diacritics, source and repeat count.
public enum ContentReviewStatus: String, Codable, Sendable, CaseIterable {
    case quranVerbatimTanzil = "QURAN_VERBATIM_TANZIL"
    case reviewRequired = "CONTENT_REVIEW_REQUIRED"
    case reviewed = "REVIEWED"
}

public struct DhikrGroup: Identifiable, Hashable, Sendable {
    public struct ID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }

        public static let morning: ID = "morning"
        public static let evening: ID = "evening"
        public static let afterPrayer: ID = "afterPrayer"
        public static let sleep: ID = "sleep"
        public static let general: ID = "general"
    }

    public let id: ID
    public let titleArabic: String

    public init(id: ID, titleArabic: String) {
        self.id = id
        self.titleArabic = titleArabic
    }
}

public struct DhikrItem: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let group: DhikrGroup.ID
    /// 1-based position inside the group.
    public let order: Int
    public let arabicText: String
    public let source: String
    public let repeatCount: Int
    /// Set when the text is Quran; the text then equals those verses joined by a space.
    public let quranRef: QuranReference?
    public let reviewStatus: ContentReviewStatus

    public init(id: String, group: DhikrGroup.ID, order: Int, arabicText: String, source: String,
                repeatCount: Int, quranRef: QuranReference?, reviewStatus: ContentReviewStatus) {
        self.id = id
        self.group = group
        self.order = order
        self.arabicText = arabicText
        self.source = source
        self.repeatCount = repeatCount
        self.quranRef = quranRef
        self.reviewStatus = reviewStatus
    }
}
