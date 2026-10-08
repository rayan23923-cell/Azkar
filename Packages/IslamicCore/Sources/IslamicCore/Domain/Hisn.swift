import Foundation

// Hisn Al-Muslim as its own domain. It shares only `ContentReviewStatus`,
// `QuranReference` and `SessionCursor` with the rest of IslamicCore and is
// independent of `DhikrItem`.

/// Rights state of bundled third-party content. Internal provenance only, not a
/// legal determination. Only states that have actually been established belong here.
public enum ContentRightsStatus: String, Codable, Sendable, CaseIterable {
    case pendingPreReleaseReview = "PENDING_PRE_RELEASE_REVIEW"
}

/// The whole book, immutable. User state (favorites, progress) is kept elsewhere.
public struct HisnBook: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let titleArabic: String
    public let author: String
    public let provenance: HisnProvenance
    public let attribution: HisnAttribution
    /// Canonical order; never re-sorted.
    public let chapters: [HisnChapter]

    public init(id: String, titleArabic: String, author: String, provenance: HisnProvenance,
                attribution: HisnAttribution, chapters: [HisnChapter]) {
        self.id = id
        self.titleArabic = titleArabic
        self.author = author
        self.provenance = provenance
        self.attribution = attribution
        self.chapters = chapters
    }

    public var itemCount: Int { chapters.reduce(0) { $0 + $1.items.count } }
    /// Every item in reading order.
    public var allItems: [HisnItem] { chapters.flatMap(\.items) }
}

public struct HisnChapter: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    /// 1-based position in this content (the source splits morning and evening, so
    /// this can differ from `bookChapterNumber`).
    public let number: Int
    public let titleArabic: String
    /// Diacritic-free search key. Never displayed.
    public let searchText: String
    /// Matching chapter number in the cross-check transcription of the book, if any.
    public let bookChapterNumber: Int?
    public let items: [HisnItem]

    public init(id: String, number: Int, titleArabic: String, searchText: String,
                bookChapterNumber: Int?, items: [HisnItem]) {
        self.id = id
        self.number = number
        self.titleArabic = titleArabic
        self.searchText = searchText
        self.bookChapterNumber = bookChapterNumber
        self.items = items
    }

    public var itemCount: Int { items.count }
}

public struct HisnItem: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let chapterId: String
    /// 1-based position inside the chapter.
    public let order: Int
    /// The book's own item number (1...267 in the cross-check print), when matched with confidence.
    public let bookItemNumber: Int?
    /// Source text exactly as received. The only text to display.
    public let arabicText: String
    /// Diacritic-free search key derived from `arabicText`. Never displayed.
    public let searchText: String
    public let repetition: HisnRepetition
    public let references: [HisnReference]
    public let quranCitations: [HisnQuranCitation]
    public let quranStatus: HisnQuranStatus
    /// Machine findings a reviewer must look at (book mismatch, repeat conflict, ...).
    public let reviewFlags: [String]
    public let reviewStatus: ContentReviewStatus

    public init(id: String, chapterId: String, order: Int, bookItemNumber: Int?, arabicText: String,
                searchText: String, repetition: HisnRepetition, references: [HisnReference],
                quranCitations: [HisnQuranCitation], quranStatus: HisnQuranStatus,
                reviewFlags: [String], reviewStatus: ContentReviewStatus) {
        self.id = id
        self.chapterId = chapterId
        self.order = order
        self.bookItemNumber = bookItemNumber
        self.arabicText = arabicText
        self.searchText = searchText
        self.repetition = repetition
        self.references = references
        self.quranCitations = quranCitations
        self.quranStatus = quranStatus
        self.reviewFlags = reviewFlags
        self.reviewStatus = reviewStatus
    }
}

/// How often an item is said. The wording in `arabicText` stays authoritative.
public struct HisnRepetition: Hashable, Codable, Sendable {
    /// Structured count, or nil when it could not be established without guessing
    /// (the source and the book disagree).
    public let count: Int?
    /// The count given by the primary source, kept even when `count` is nil.
    public let sourceCount: Int
    /// Counts the cross-check book text states in words for this item (e.g. ثلاثاً → 3).
    public let bookStatedCounts: [Int]
    public let reviewStatus: ContentReviewStatus

    public init(count: Int?, sourceCount: Int, bookStatedCounts: [Int], reviewStatus: ContentReviewStatus) {
        self.count = count
        self.sourceCount = sourceCount
        self.bookStatedCounts = bookStatedCounts
        self.reviewStatus = reviewStatus
    }
}

/// Source/takhrij of an item. `originalText` is complete and verbatim; the rest is an index.
public struct HisnReference: Hashable, Codable, Sendable {
    public let originalText: String
    /// Hadith collections named in `originalText`, for search and filtering.
    public let collections: [String]

    public init(originalText: String, collections: [String]) {
        self.originalText = originalText
        self.collections = collections
    }
}

/// A Quran passage quoted inside an item, pointing at the canonical Tanzil verses.
public struct HisnQuranCitation: Hashable, Codable, Sendable {
    public enum Match: String, Codable, Sendable {
        /// The quoted letters occur exactly once in Tanzil, inside these verses.
        case exact = "EXACT"
        /// Located through the book's footnote and close letter agreement; needs review.
        case fuzzy = "FUZZY"
    }

    public let reference: QuranReference
    /// False when the item quotes only part of the first or last verse.
    public let coversWholeVerses: Bool
    public let match: Match

    public init(reference: QuranReference, coversWholeVerses: Bool, match: Match) {
        self.reference = reference
        self.coversWholeVerses = coversWholeVerses
        self.match = match
    }
}

public enum HisnQuranStatus: String, Codable, Sendable {
    /// No Quran passage detected.
    case none = "NONE"
    case resolved = "RESOLVED"
    /// Some quoted passages could not be located; see `reviewFlags`.
    case partial = "PARTIAL"
    case unresolved = "UNRESOLVED"
}

public struct HisnProvenance: Hashable, Codable, Sendable {
    public struct PrimarySource: Hashable, Codable, Sendable {
        public let name: String
        public let url: String
        public let license: String
        public let edition: String
        public let upstreamFile: String
        public let sha256: String
        public let retrieved: String
    }

    public struct CrossCheck: Hashable, Codable, Sendable {
        public let name: String
        public let urls: [String]
        public let bookChapters: Int
        public let bookItems: Int
    }

    public struct CanonicalEdition: Hashable, Codable, Sendable {
        public let name: String
        public let url: String
        public let sha256: String
        /// e.g. NOT_YET_COMPARED until the bundled text is checked against this edition.
        public let comparison: String
    }

    public let primarySource: PrimarySource
    public let crossCheck: CrossCheck
    public let canonicalEdition: CanonicalEdition
}

/// Placeholder until the pre-release rights review fills it in.
public struct HisnAttribution: Hashable, Codable, Sendable {
    public let sourceTitle: String
    public let author: String
    public let edition: String?
    public let sourceURL: String
    public let attributionText: String?
    public let rightsStatus: ContentRightsStatus
}
