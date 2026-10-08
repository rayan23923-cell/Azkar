import Foundation

/// Runs queries against a prebuilt `HisnSearchIndex`. It normalizes the query, ranks every
/// entry (see `HisnSearchResult.Rank`), and orders equal ranks by book order. Deterministic,
/// offline, and it never rebuilds the index.
public struct HisnSearchEngine: Sendable {
    public let index: HisnSearchIndex

    /// Longer texts are shown as an excerpt around the match.
    static let excerptLimit = 160
    static let excerptLead = 50

    public init(index: HisnSearchIndex) {
        self.index = index
    }

    /// True when the query has something to search for (at least one Arabic letter).
    public static func isSearchable(_ query: String) -> Bool {
        !HisnSearchNormalizer.normalize(query).isEmpty
    }

    public func search(_ query: String, filter: HisnSearchFilter = .all) -> [HisnSearchResult] {
        let key = HisnSearchNormalizer.normalize(query)
        guard !key.isEmpty else { return [] }
        let words = key.split(separator: " ").map(String.init)
        var results: [HisnSearchResult] = []
        for entry in index.entries {
            switch (filter, entry.kind) {
            case (.chapters, .item), (.texts, .chapter): continue
            default: break
            }
            guard let rank = Self.rank(entry, key: key, words: words) else { continue }
            results.append(Self.result(entry, rank: rank, key: key, words: words))
        }
        return results.sorted { ($0.rank, $0.order) < ($1.rank, $1.order) }
    }

    static func rank(_ entry: HisnSearchIndex.Entry, key: String, words: [String]) -> HisnSearchResult.Rank? {
        let text = entry.normalized.key
        let chapter = entry.kind == .chapter
        if text == key { return chapter ? .chapterExact : .textExact }
        if text.hasPrefix(key) { return chapter ? .chapterPrefix : .textPrefix }
        if words.allSatisfy({ text.contains($0) }) { return chapter ? .chapterPartial : .textPartial }
        return nil
    }

    static func result(_ entry: HisnSearchIndex.Entry, rank: HisnSearchResult.Rank, key: String,
                       words: [String]) -> HisnSearchResult {
        let excerpt = Self.excerpt(entry, key: key, words: words)
        return HisnSearchResult(kind: entry.kind, rank: rank, order: entry.order, chapterId: entry.chapterId,
                                chapterTitle: entry.chapterTitle, chapterItemCount: entry.chapterItemCount,
                                itemId: entry.itemId, itemIndex: entry.itemIndex,
                                matchedText: excerpt.text, highlight: excerpt.highlight)
    }

    // MARK: Excerpt and highlight

    /// The matched words in the original text, and a window around them when the text is long.
    static func excerpt(_ entry: HisnSearchIndex.Entry, key: String,
                        words: [String]) -> (text: String, highlight: Range<Int>?) {
        let characters = Array(entry.text)
        guard let scalars = matchScalarRange(entry.normalized, key: key, words: words) else {
            return (entry.text, nil)
        }
        let matched = wordRange(characters, coveringScalars: scalars)
        guard characters.count > excerptLimit, let matched else {
            return (entry.text, matched)
        }
        var start = max(0, matched.lowerBound - excerptLead)
        var end = min(characters.count, max(matched.upperBound, start + excerptLimit))
        // Cut only between words.
        while start > 0, !isSeparator(characters[start - 1]) { start -= 1 }
        while end < characters.count, !isSeparator(characters[end]) { end += 1 }
        let prefix = start > 0 ? "… " : ""
        let suffix = end < characters.count ? " …" : ""
        let body = String(characters[start..<end])
        let shift = prefix.count - start
        return (prefix + body + suffix, (matched.lowerBound + shift)..<(matched.upperBound + shift))
    }

    /// The match in the original text, in unicode-scalar offsets: the whole query when it
    /// appears as one run, otherwise the first query word.
    static func matchScalarRange(_ normalized: HisnNormalizedText, key: String,
                                 words: [String]) -> Range<Int>? {
        let target = normalized.key.range(of: key, options: .literal) != nil ? key : (words.first ?? key)
        guard let found = normalized.key.range(of: target, options: .literal) else { return nil }
        let lower = normalized.key.unicodeScalars.distance(from: normalized.key.startIndex, to: found.lowerBound)
        let upper = normalized.key.unicodeScalars.distance(from: normalized.key.startIndex, to: found.upperBound)
        guard lower < upper, upper <= normalized.sourceOffsets.count else { return nil }
        return normalized.sourceOffsets[lower]..<(normalized.sourceOffsets[upper - 1] + 1)
    }

    /// The character range of the whole words that overlap the scalar range.
    static func wordRange(_ characters: [Character], coveringScalars scalars: Range<Int>) -> Range<Int>? {
        var scalarOffset = 0
        var first: Int?
        var last: Int?
        for (index, character) in characters.enumerated() {
            let width = character.unicodeScalars.count
            if scalarOffset < scalars.upperBound, scalarOffset + width > scalars.lowerBound {
                if first == nil { first = index }
                last = index
            }
            scalarOffset += width
        }
        guard var lower = first, var upper = last.map({ $0 + 1 }) else { return nil }
        while lower > 0, !isSeparator(characters[lower - 1]) { lower -= 1 }
        while upper < characters.count, !isSeparator(characters[upper]) { upper += 1 }
        return lower..<upper
    }

    static func isSeparator(_ character: Character) -> Bool {
        character.isWhitespace || character.isPunctuation || character.isSymbol
    }
}
