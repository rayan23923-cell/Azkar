import Foundation

/// Hisn Al-Muslim content. Implementations may be bundled (V1) or remote (later).
public protocol HisnRepository: Sendable {
    func loadBook() async throws -> HisnBook
    func loadChapters() async throws -> [HisnChapter]
    func loadChapter(id: String) async throws -> HisnChapter
    func loadItem(id: String) async throws -> HisnItem
}

/// Reads `Content/hisn.json`.
public actor BundledHisnRepository: HisnRepository {
    private let source: BundledContentSource
    private var cache: HisnBook?

    public init(source: BundledContentSource = .bundled) {
        self.source = source
    }

    public func loadBook() async throws -> HisnBook {
        try content()
    }

    public func loadChapters() async throws -> [HisnChapter] {
        try content().chapters
    }

    public func loadChapter(id: String) async throws -> HisnChapter {
        guard let chapter = try content().chapters.first(where: { $0.id == id }) else {
            throw ContentError.notFound("hisn chapter \(id)")
        }
        return chapter
    }

    public func loadItem(id: String) async throws -> HisnItem {
        guard let item = try content().chapters.lazy.flatMap(\.items).first(where: { $0.id == id }) else {
            throw ContentError.notFound("hisn item \(id)")
        }
        return item
    }

    private func content() throws -> HisnBook {
        if let cache { return cache }
        let file = try source.decode(HisnFile.self, resource: "hisn")
        let book = HisnBook(id: file.book.id, titleArabic: file.book.titleArabic, author: file.book.author,
                            provenance: file.book.provenance, attribution: file.book.attribution,
                            chapters: file.chapters)
        try validateHisn(book)
        cache = book
        return book
    }
}

private struct HisnFile: Decodable {
    struct Header: Decodable {
        let id: String
        let titleArabic: String
        let author: String
        let provenance: HisnProvenance
        let attribution: HisnAttribution
    }

    let book: Header
    let chapters: [HisnChapter]
}

func validateHisn(_ book: HisnBook) throws {
    try requireContent(!book.titleArabic.isEmpty && !book.author.isEmpty, "hisn: book title or author empty")
    try requireContent(!book.chapters.isEmpty, "hisn: no chapters")
    var chapterIds = Set<String>()
    var itemIds = Set<String>()
    for (offset, chapter) in book.chapters.enumerated() {
        try requireContent(chapterIds.insert(chapter.id).inserted, "hisn: duplicate chapter id \(chapter.id)")
        try requireContent(chapter.number == offset + 1, "hisn: \(chapter.id) number")
        try requireContent(isWellFormedArabic(chapter.titleArabic), "hisn: \(chapter.id) title")
        try requireContent(!chapter.items.isEmpty, "hisn: \(chapter.id) is empty")
        let siblings = book.chapters.filter { $0.bookChapterNumber != nil && $0.bookChapterNumber == chapter.bookChapterNumber }
        if siblings.count > 1 {
            try requireContent(chapter.presentationSection != nil
                               && Set(siblings.compactMap(\.presentationSection)).count == siblings.count,
                               "hisn: \(chapter.id) presentation section")
        } else {
            try requireContent(chapter.presentationSection == nil, "hisn: \(chapter.id) presentation section")
        }
        for (index, item) in chapter.items.enumerated() {
            try requireContent(itemIds.insert(item.id).inserted, "hisn: duplicate item id \(item.id)")
            try requireContent(item.chapterId == chapter.id, "hisn: \(item.id) is in the wrong chapter")
            try requireContent(item.order == index + 1, "hisn: \(item.id) order")
            try requireContent(isWellFormedArabic(item.arabicText), "hisn: \(item.id) text")
            try requireContent(!item.searchText.isEmpty, "hisn: \(item.id) search text")
            try requireContent(item.bookItemNumber.map { $0 >= 1 && $0 <= book.provenance.corrections.canonicalBookItems } ?? true,
                               "hisn: \(item.id) book item number")
            switch item.bookItemRelation {
            case .direct, .splitPart:
                try requireContent(item.bookItemNumber != nil, "hisn: \(item.id) relation needs a book item number")
            case .chapterIntroduction:
                try requireContent(item.bookItemNumber == nil && item.order == 1, "hisn: \(item.id) chapter introduction")
            case .eveningVariant:
                try requireContent(chapter.presentationSection == .evening, "hisn: \(item.id) evening variant outside the evening section")
            }
            try requireContent((item.corrections.applied + item.corrections.open).allSatisfy { $0.hasPrefix("HISN-CORR-") },
                               "hisn: \(item.id) correction ids")
            try requireContent(item.nonRecitationText.allSatisfy {
                !$0.text.isEmpty && item.arabicText.components(separatedBy: $0.text).count == 2
            }, "hisn: \(item.id) non-recitation text must be one exact span of the text")
            try requireContent(item.editorialReviews.allSatisfy { $0.id.hasPrefix("HISN-REVIEW-") }, "hisn: \(item.id) review ids")
            try requireContent(item.repetition.sourceCount >= 1 && (item.repetition.count.map { $0 >= 1 } ?? true),
                               "hisn: \(item.id) repeat count")
            try requireContent(item.references.allSatisfy { !$0.originalText.isEmpty }, "hisn: \(item.id) empty reference")
            for citation in item.quranCitations {
                let ref = citation.reference
                try requireContent((1...114).contains(ref.surah) && 1 <= ref.fromAyah && ref.fromAyah <= ref.toAyah,
                                   "hisn: \(item.id) quran citation")
                // A whole-surah instruction cites the surah's opening verses only.
                try requireContent(!citation.recitesWholeSurah || ref.fromAyah == 1, "hisn: \(item.id) whole-surah citation")
            }
            let hasCitations = !item.quranCitations.isEmpty
            switch item.quranStatus {
            case .none, .unresolved:
                try requireContent(!hasCitations, "hisn: \(item.id) quran status")
            case .resolved, .partial:
                try requireContent(hasCitations, "hisn: \(item.id) quran status")
            }
            // Hisn text is not Tanzil text, so it can never carry the Tanzil verbatim status.
            try requireContent(item.reviewStatus != .quranVerbatimTanzil && item.repetition.reviewStatus != .quranVerbatimTanzil,
                               "hisn: \(item.id) review status")
        }
    }
    let corrections = book.provenance.corrections
    try requireContent(book.canonicalChapters.map(\.bookChapterNumber) == Array(1...corrections.canonicalBookChapters),
                       "hisn: canonical chapters")
    try requireContent(book.bookItemNumbers == Set(1...corrections.canonicalBookItems), "hisn: canonical book items")
}

/// Non-empty, no U+FFFD, and contains Arabic letters.
func isWellFormedArabic(_ text: String) -> Bool {
    !text.isEmpty
        && !text.unicodeScalars.contains("\u{FFFD}")
        && text.unicodeScalars.contains { (0x0621...0x064A).contains($0.value) }
}
