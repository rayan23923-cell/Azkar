import Foundation
import IslamicCore
import ContentKit

public struct QuranSearchResult: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case surah
        case verse
    }

    /// Lower ranks come first; equal ranks keep mushaf order.
    public enum Rank: Int, Comparable, Sendable {
        case surahExact = 1
        case surahPrefix
        case verseExact
        case versePrefix
        case surahPartial
        case versePartial

        public static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let kind: Kind
    public let rank: Rank
    public let order: Int
    public let surah: Int
    public let surahName: String
    /// Nil for a surah result.
    public let ayah: Int?
    /// The surah name, or the verse text (an excerpt with «…» when long). Never edited.
    public let matchedText: String
    /// Whole matched words in `matchedText`, as character offsets.
    public let highlight: Range<Int>?

    public var id: String { ayah.map { "v:\(surah):\($0)" } ?? "s:\(surah)" }
    public var ref: QuranVerseRef { QuranVerseRef(surah: surah, ayah: ayah ?? 1) }
}

public enum QuranSearchFilter: String, CaseIterable, Hashable, Sendable {
    case all
    case surahs
    case verses
}

/// Offline search over surah names and every verse. Built once (6236 verses + 114 names) and
/// reused by every query. Each verse is indexed twice, with the dagger alef dropped and read as
/// alef, so standard spelling finds Uthmani words («العالمين», «الرحمن»). Words whose mushaf
/// spelling differs in other ways (for example «الصلوٰة») match their Uthmani form only.
public final class QuranSearchIndex: Sendable {
    struct Entry: Sendable {
        let kind: QuranSearchResult.Kind
        let order: Int
        let surah: Int
        let surahName: String
        let ayah: Int?
        let text: String
        let normalized: NormalizedSearchText
        /// The same text with the dagger alef read as alef (verses only).
        let alternate: NormalizedSearchText?
    }

    let entries: [Entry]

    public init(library: QuranLibrary) {
        var entries: [Entry] = []
        entries.reserveCapacity(QuranLibrary.verseCount + QuranLibrary.surahCount)
        for surah in library.surahs {
            entries.append(Entry(kind: .surah, order: entries.count, surah: surah.id, surahName: surah.nameArabic,
                                 ayah: nil, text: surah.nameArabic,
                                 normalized: ArabicSearchNormalizer.normalizeMapped(surah.nameArabic), alternate: nil))
            for verse in library.verses(of: surah.id) {
                let alternate = ArabicSearchNormalizer.normalizeMapped(verse.arabicText, daggerAlefAsAlef: true)
                let normalized = ArabicSearchNormalizer.normalizeMapped(verse.arabicText)
                entries.append(Entry(kind: .verse, order: entries.count, surah: surah.id, surahName: surah.nameArabic,
                                     ayah: verse.ayahNumber, text: verse.arabicText, normalized: normalized,
                                     alternate: alternate.key == normalized.key ? nil : alternate))
            }
        }
        self.entries = entries
    }

    public var surahEntryCount: Int { entries.lazy.filter { $0.kind == .surah }.count }
    public var verseEntryCount: Int { entries.lazy.filter { $0.kind == .verse }.count }
}

public struct QuranSearchEngine: Sendable {
    public let index: QuranSearchIndex

    public init(index: QuranSearchIndex) {
        self.index = index
    }

    public func search(_ query: String, filter: QuranSearchFilter = .all) -> [QuranSearchResult] {
        let key = ArabicSearchNormalizer.normalize(query)
        guard !key.isEmpty else { return [] }
        let words = SearchMatcher.words(key)
        var results: [QuranSearchResult] = []
        for entry in index.entries {
            switch (filter, entry.kind) {
            case (.surahs, .verse), (.verses, .surah): continue
            default: break
            }
            // The better of the two spellings wins.
            let primary = SearchMatcher.match(entry.normalized.key, key: key, words: words)
            let secondary = entry.alternate.flatMap { SearchMatcher.match($0.key, key: key, words: words) }
            let useAlternate: Bool
            let match: SearchMatchKind
            switch (primary, secondary) {
            case (nil, nil): continue
            case (let first?, nil): match = first; useAlternate = false
            case (nil, let second?): match = second; useAlternate = true
            case (let first?, let second?): match = min(first, second); useAlternate = second < first
            }
            let matchedForm = useAlternate ? (entry.alternate ?? entry.normalized) : entry.normalized
            let rank: QuranSearchResult.Rank
            switch (entry.kind, match) {
            case (.surah, .exact): rank = .surahExact
            case (.surah, .prefix): rank = .surahPrefix
            case (.surah, .partial): rank = .surahPartial
            case (.verse, .exact): rank = .verseExact
            case (.verse, .prefix): rank = .versePrefix
            case (.verse, .partial): rank = .versePartial
            }
            let excerpt = SearchMatcher.excerpt(entry.text, normalized: matchedForm, key: key, words: words)
            results.append(QuranSearchResult(kind: entry.kind, rank: rank, order: entry.order, surah: entry.surah,
                                             surahName: entry.surahName, ayah: entry.ayah,
                                             matchedText: excerpt.text, highlight: excerpt.highlight))
        }
        return results.sorted { ($0.rank, $0.order) < ($1.rank, $1.order) }
    }
}
