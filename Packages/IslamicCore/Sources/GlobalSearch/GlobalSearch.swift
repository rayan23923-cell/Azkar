import Foundation
import IslamicCore
import ContentKit
import QuranReading
import HisnReading
import AdhkarReading

/// One result of the search across the whole app.
public struct GlobalSearchResult: Identifiable, Hashable, Sendable {
    /// Section order on screen.
    public enum Source: Int, Comparable, CaseIterable, Sendable {
        case quran
        case hisn
        case adhkar
        case dua

        public static func < (lhs: Source, rhs: Source) -> Bool { lhs.rawValue < rhs.rawValue }

        public var title: String {
            switch self {
            case .quran: return "القرآن الكريم"
            case .hisn: return "حصن المسلم"
            case .adhkar: return "الأذكار"
            case .dua: return "الأدعية"
            }
        }
    }

    /// Where a tap opens.
    public enum Destination: Hashable, Sendable {
        case quran(QuranVerseRef, highlights: Bool)
        case hisn(HisnSearchResult)
        case devotional(collection: ContentRef, item: ContentRef?)
    }

    public let source: Source
    public let strength: SearchMatchKind
    /// A surah name, chapter title or collection title rather than a text.
    public let isTitle: Bool
    /// Book order inside the source.
    public let order: Int
    /// The surah, chapter or collection, and for a text its position («الآية 255»).
    public let title: String
    public let matchedText: String
    public let highlight: Range<Int>?
    public let destination: Destination

    public var id: String {
        switch destination {
        case .quran(let ref, let highlights): return "quran:\(ref)\(highlights ? "" : ":s")"
        case .hisn(let result): return "hisn:\(result.id)"
        case .devotional(let collection, let item): return (item ?? collection).string
        }
    }
}

/// All results of one query, with a spelling suggestion when nothing matched as typed.
public struct GlobalSearchResponse: Equatable, Sendable {
    public let query: String
    public let results: [GlobalSearchResult]
    /// How many results each source had before the per-source limit.
    public let totals: [GlobalSearchResult.Source: Int]
    /// Set when the typed query found nothing and a close spelling did; `results` are its.
    public let correctedQuery: String?

    public static let empty = GlobalSearchResponse(query: "", results: [], totals: [:], correctedQuery: nil)

    public var totalCount: Int { totals.values.reduce(0, +) }
}

/// Searches the Quran, Hisn Al-Muslim, the adhkar and the duas together, offline, with the
/// engines each section already uses. Ranking: match strength (exact, prefix, every word),
/// then titles before texts, then source order, then book order. The same query always gives
/// the same list.
public struct GlobalSearchEngine: Sendable {
    let quran: QuranSearchEngine?
    let quranLibrary: QuranLibrary?
    let hisn: HisnSearchEngine?
    let devotional: DevotionalSearchIndex?
    let vocabulary: SearchVocabulary

    public init(quran: (QuranLibrary, QuranSearchEngine)?, hisn: (HisnBook, HisnSearchEngine)?,
                adhkar: (AdhkarLibrary, DevotionalSearchIndex)?) {
        self.quran = quran?.1
        quranLibrary = quran?.0
        self.hisn = hisn?.1
        devotional = adhkar?.1
        var texts: [String] = []
        if let library = quran?.0 {
            for surah in library.surahs {
                texts.append(surah.nameArabic)
                texts.append(contentsOf: library.verses(of: surah.id).map(\.arabicText))
            }
        }
        if let book = hisn?.0 {
            for chapter in book.chapters {
                texts.append(chapter.titleArabic)
                texts.append(contentsOf: chapter.items.map(\.arabicText))
            }
        }
        if let library = adhkar?.0 {
            for collection in library.collections {
                texts.append(collection.title)
                texts.append(contentsOf: collection.items.map(\.text))
            }
        }
        vocabulary = SearchVocabulary(texts: texts)
    }

    /// `limit` caps each source's list (the counts in `totals` are not capped).
    public func search(_ query: String, source: GlobalSearchResult.Source? = nil, limit: Int = 50) -> GlobalSearchResponse {
        let key = ArabicSearchNormalizer.normalize(query)
        guard !key.isEmpty else { return .empty }
        let exact = run(key, source: source, limit: limit)
        if !exact.results.isEmpty { return GlobalSearchResponse(query: key, results: exact.results, totals: exact.totals,
                                                                correctedQuery: nil) }
        guard let corrected = vocabulary.correction(for: key) else {
            return GlobalSearchResponse(query: key, results: [], totals: [:], correctedQuery: nil)
        }
        let retry = run(corrected, source: source, limit: limit)
        guard !retry.results.isEmpty else { return GlobalSearchResponse(query: key, results: [], totals: [:], correctedQuery: nil) }
        return GlobalSearchResponse(query: key, results: retry.results, totals: retry.totals, correctedQuery: corrected)
    }

    private func run(_ key: String, source: GlobalSearchResult.Source?, limit: Int)
        -> (results: [GlobalSearchResult], totals: [GlobalSearchResult.Source: Int]) {
        var all: [GlobalSearchResult] = []
        var totals: [GlobalSearchResult.Source: Int] = [:]
        func include(_ candidate: GlobalSearchResult.Source) -> Bool { source == nil || source == candidate }

        if include(.quran), let quran {
            let found = quran.search(key)
            totals[.quran] = found.count
            all += found.prefix(limit).map { result in
                let strength: SearchMatchKind
                switch result.rank {
                case .surahExact, .verseExact: strength = .exact
                case .surahPrefix, .versePrefix: strength = .prefix
                case .surahPartial, .versePartial: strength = .partial
                }
                let isTitle = result.kind == .surah
                return GlobalSearchResult(source: .quran, strength: strength, isTitle: isTitle, order: result.order,
                                          title: isTitle ? "سورة \(result.surahName)"
                                                         : "سورة \(result.surahName)، الآية \(result.ayah ?? 1)",
                                          matchedText: result.matchedText, highlight: result.highlight,
                                          destination: .quran(result.ref, highlights: !isTitle))
            }
        }
        if include(.hisn), let hisn {
            let found = hisn.search(key)
            totals[.hisn] = found.count
            all += found.prefix(limit).map { result in
                let strength: SearchMatchKind
                switch result.rank {
                case .chapterExact, .textExact: strength = .exact
                case .chapterPrefix, .textPrefix: strength = .prefix
                case .chapterPartial, .textPartial: strength = .partial
                }
                let isTitle = result.kind == .chapter
                return GlobalSearchResult(source: .hisn, strength: strength, isTitle: isTitle, order: result.order,
                                          title: result.chapterTitle, matchedText: result.matchedText,
                                          highlight: result.highlight, destination: .hisn(result))
            }
        }
        if let devotional {
            for kind in [DevotionalCollection.Kind.adhkar, .dua] {
                let mapped: GlobalSearchResult.Source = kind == .adhkar ? .adhkar : .dua
                guard include(mapped) else { continue }
                let found = devotional.search(key, kind: kind)
                totals[mapped] = found.count
                all += found.prefix(limit).map { result in
                    GlobalSearchResult(source: mapped, strength: result.match, isTitle: result.kind == .collection,
                                       order: result.order, title: result.collectionTitle,
                                       matchedText: result.matchedText, highlight: result.highlight,
                                       destination: .devotional(collection: result.collection, item: result.item))
                }
            }
        }
        all.sort {
            ($0.strength, $0.isTitle ? 0 : 1, $0.source.rawValue, $0.order)
                < ($1.strength, $1.isTitle ? 0 : 1, $1.source.rawValue, $1.order)
        }
        return (all, totals)
    }
}

/// Every normalized word of the content with its frequency, for spelling suggestions.
///
/// A suggestion is offered only when the typed query found nothing. Each query word of four
/// letters or more that is not a content word may be replaced by a content word one edit away
/// (one letter changed, added, removed, or two neighbours swapped); the most frequent wins,
/// then the alphabetically first. Shorter words are never changed, and if any word has no
/// such neighbour there is no suggestion. So a suggestion is always a real content word and
/// never replaces a query that already matched.
struct SearchVocabulary: Sendable {
    let frequency: [String: Int]
    let byLength: [Int: [String]]

    init(texts: [String]) {
        var frequency: [String: Int] = [:]
        for text in texts {
            var keys = [ArabicSearchNormalizer.normalize(text)]
            let alternate = ArabicSearchNormalizer.normalizeMapped(text, daggerAlefAsAlef: true).key
            if alternate != keys[0] { keys.append(alternate) }
            for key in keys {
                for word in key.split(separator: " ") { frequency[String(word), default: 0] += 1 }
            }
        }
        self.frequency = frequency
        var byLength: [Int: [String]] = [:]
        for word in frequency.keys { byLength[word.count, default: []].append(word) }
        self.byLength = byLength.mapValues { $0.sorted() }
    }

    var wordCount: Int { frequency.count }

    func correction(for key: String) -> String? {
        let words = key.split(separator: " ").map(String.init)
        var changed = false
        var corrected: [String] = []
        for word in words {
            if frequency[word] != nil || word.count < 4 {
                corrected.append(word)
                continue
            }
            guard let best = closest(to: word) else { return nil }
            corrected.append(best)
            changed = true
        }
        return changed ? corrected.joined(separator: " ") : nil
    }

    func closest(to word: String) -> String? {
        let target = Array(word)
        var best: (word: String, count: Int)?
        for length in (target.count - 1)...(target.count + 1) {
            for candidate in byLength[length] ?? [] where Self.isOneEditAway(target, Array(candidate)) {
                let count = frequency[candidate] ?? 0
                if let current = best, current.count > count || (current.count == count && current.word < candidate) {
                    continue
                }
                best = (candidate, count)
            }
        }
        return best?.word
    }

    /// One substitution, insertion, deletion or swap of neighbours.
    static func isOneEditAway(_ a: [Character], _ b: [Character]) -> Bool {
        if a == b { return false }
        if a.count == b.count {
            let diffs = a.indices.filter { a[$0] != b[$0] }
            if diffs.count == 1 { return true }
            if diffs.count == 2, diffs[1] == diffs[0] + 1 {
                return a[diffs[0]] == b[diffs[1]] && a[diffs[1]] == b[diffs[0]]
            }
            return false
        }
        let (short, long) = a.count < b.count ? (a, b) : (b, a)
        guard long.count - short.count == 1 else { return false }
        var i = 0
        var j = 0
        var skipped = false
        while i < short.count, j < long.count {
            if short[i] == long[j] {
                i += 1
                j += 1
            } else {
                if skipped { return false }
                skipped = true
                j += 1
            }
        }
        return true
    }
}
