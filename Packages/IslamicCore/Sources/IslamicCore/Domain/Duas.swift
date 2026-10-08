import Foundation

public struct DuaCategory: Identifiable, Hashable, Sendable {
    public struct ID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }

        public static let quranic: ID = "quranic"
        public static let prophetic: ID = "prophetic"
    }

    public let id: ID
    public let titleArabic: String

    public init(id: ID, titleArabic: String) {
        self.id = id
        self.titleArabic = titleArabic
    }
}

public struct DuaItem: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let category: DuaCategory.ID
    /// 1-based position inside the category.
    public let order: Int
    public let arabicText: String
    public let source: String
    public let quranRef: QuranReference?
    public let reviewStatus: ContentReviewStatus

    public init(id: String, category: DuaCategory.ID, order: Int, arabicText: String, source: String,
                quranRef: QuranReference?, reviewStatus: ContentReviewStatus) {
        self.id = id
        self.category = category
        self.order = order
        self.arabicText = arabicText
        self.source = source
        self.quranRef = quranRef
        self.reviewStatus = reviewStatus
    }
}
