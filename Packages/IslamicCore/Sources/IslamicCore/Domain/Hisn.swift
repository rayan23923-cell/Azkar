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

    /// The book's own chapters (132), each made of the presentation sections that show it.
    /// Chapter 27 is the only one shown as two sections (morning 27A, evening 27B).
    public var canonicalChapters: [HisnCanonicalChapter] {
        Dictionary(grouping: chapters.filter { $0.bookChapterNumber != nil }, by: { $0.bookChapterNumber! })
            .map { HisnCanonicalChapter(bookChapterNumber: $0.key, sections: $0.value.sorted { $0.number < $1.number }) }
            .sorted { $0.bookChapterNumber < $1.bookChapterNumber }
    }

    /// Every book item number carried by at least one display item.
    public var bookItemNumbers: Set<Int> { Set(allItems.compactMap(\.bookItemNumber)) }
}

/// One chapter of the printed book, independent of how the source splits it for display.
public struct HisnCanonicalChapter: Hashable, Sendable {
    public let bookChapterNumber: Int
    /// Presentation sections in display order; one, except for chapter 27.
    public let sections: [HisnChapter]

    /// Book item numbers in this chapter, ascending, each once.
    public var bookItemNumbers: [Int] {
        Array(Set(sections.flatMap { $0.items.compactMap(\.bookItemNumber) })).sorted()
    }
}

/// How a book chapter shown as several sections is divided. Not a canonical chapter.
public enum HisnPresentationSection: String, Codable, Sendable {
    case morning = "MORNING"
    case evening = "EVENING"
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
    /// Set only when one book chapter is shown as several sections (chapter 27).
    public let presentationSection: HisnPresentationSection?
    /// Display order, as in the source; never re-sorted.
    public let items: [HisnItem]

    public init(id: String, number: Int, titleArabic: String, searchText: String,
                bookChapterNumber: Int?, presentationSection: HisnPresentationSection? = nil, items: [HisnItem]) {
        self.id = id
        self.number = number
        self.titleArabic = titleArabic
        self.searchText = searchText
        self.bookChapterNumber = bookChapterNumber
        self.presentationSection = presentationSection
        self.items = items
    }

    public var itemCount: Int { items.count }

    /// "27A" / "27B" for a presentation section, otherwise the book chapter number.
    public var presentationLabel: String? {
        guard let bookChapterNumber else { return nil }
        switch presentationSection {
        case .morning: return "\(bookChapterNumber)A"
        case .evening: return "\(bookChapterNumber)B"
        case nil: return "\(bookChapterNumber)"
        }
    }

    /// The items in the book's order. Differs from `items` only where the source lists
    /// two book items the other way round (chapters 1, 4 and 10). An introduction comes
    /// first; an unnumbered item stays after the item before it.
    public var itemsInBookOrder: [HisnItem] {
        var last = 0
        let keyed = items.map { item -> (key: Int, order: Int, item: HisnItem) in
            if item.bookItemRelation == .chapterIntroduction { return (0, item.order, item) }
            last = item.bookItemNumber ?? last
            return (last, item.order, item)
        }
        return keyed.sorted { ($0.key, $0.order) < ($1.key, $1.order) }.map(\.item)
    }
}

public struct HisnItem: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let chapterId: String
    /// 1-based position inside the chapter.
    public let order: Int
    /// The book's own item number (1...267), after the Phase 2E corrections. Nil only for a
    /// chapter introduction or an evening variant whose number is still pending.
    public let bookItemNumber: Int?
    /// How this display item relates to the book item it carries.
    public let bookItemRelation: HisnBookItemRelation
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
    /// Correction manifest entries (tools/content/hisn.corrections.json) for this item.
    public let corrections: HisnItemCorrections
    public let reviewStatus: ContentReviewStatus

    public init(id: String, chapterId: String, order: Int, bookItemNumber: Int?,
                bookItemRelation: HisnBookItemRelation = .direct, arabicText: String,
                searchText: String, repetition: HisnRepetition, references: [HisnReference],
                quranCitations: [HisnQuranCitation], quranStatus: HisnQuranStatus,
                reviewFlags: [String], corrections: HisnItemCorrections = HisnItemCorrections(),
                reviewStatus: ContentReviewStatus) {
        self.id = id
        self.chapterId = chapterId
        self.order = order
        self.bookItemNumber = bookItemNumber
        self.bookItemRelation = bookItemRelation
        self.arabicText = arabicText
        self.searchText = searchText
        self.repetition = repetition
        self.references = references
        self.quranCitations = quranCitations
        self.quranStatus = quranStatus
        self.reviewFlags = reviewFlags
        self.corrections = corrections
        self.reviewStatus = reviewStatus
    }
}

public enum HisnBookItemRelation: String, Codable, Sendable {
    /// The display item is the book item.
    case direct = "DIRECT"
    /// One of several consecutive display items that together make one book item.
    case splitPart = "SPLIT_PART"
    /// Evening wording the book gives in a footnote for a morning item.
    case eveningVariant = "EVENING_VARIANT"
    /// The book's unnumbered opening line of a chapter.
    case chapterIntroduction = "CHAPTER_INTRODUCTION"
}

/// Manifest entry ids. Applied entries changed a value of this item; open ones are
/// pending decisions or recorded discrepancies that still need editorial review.
public struct HisnItemCorrections: Hashable, Codable, Sendable {
    public let applied: [String]
    public let open: [String]

    public init(applied: [String] = [], open: [String] = []) {
        self.applied = applied
        self.open = open
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
        /// The quoted letters occur exactly once in Tanzil, inside these verses, or an accepted
        /// manifest entry identified them verse for verse with spelling-only differences.
        case exact = "EXACT"
        /// Located through the book's footnote and close letter agreement; needs review.
        case fuzzy = "FUZZY"
    }

    public let reference: QuranReference
    /// False when the item quotes only part of the first or last verse.
    public let coversWholeVerses: Bool
    public let match: Match
    /// True when the item quotes only the opening of a surah and instructs reciting the
    /// whole surah. The surah text itself is not part of the item.
    public let recitesWholeSurah: Bool

    public init(reference: QuranReference, coversWholeVerses: Bool, match: Match, recitesWholeSurah: Bool = false) {
        self.reference = reference
        self.coversWholeVerses = coversWholeVerses
        self.match = match
        self.recitesWholeSurah = recitesWholeSurah
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

    /// Summary of the Phase 2E correction manifest applied by the content build.
    public struct Corrections: Hashable, Codable, Sendable {
        public let manifest: String
        public let sha256: String
        public let total: Int
        /// Correction decisions accepted and applied. Not an editorial review.
        public let accepted: Int
        public let observationOnly: Int
        public let pendingDecision: Int
        public let p0Accepted: Int
        public let p0Pending: Int
        public let canonicalBookChapters: Int
        public let canonicalBookItems: Int
        public let presentationSections: Int
        public let displayItems: Int
    }

    public let primarySource: PrimarySource
    public let crossCheck: CrossCheck
    public let canonicalEdition: CanonicalEdition
    public let corrections: Corrections
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
