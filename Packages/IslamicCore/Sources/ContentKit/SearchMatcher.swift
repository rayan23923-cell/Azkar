import Foundation

/// How a normalized text matches a normalized query.
public enum SearchMatchKind: Int, Comparable, Sendable {
    /// The text is the query.
    case exact
    /// The text starts with the query.
    case prefix
    /// Every query word appears somewhere in the text.
    case partial

    public static func < (lhs: SearchMatchKind, rhs: SearchMatchKind) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Matching and preview helpers shared by the search engines. Keys come from
/// `ArabicSearchNormalizer`; previews are cut from the stored text, never edited.
public enum SearchMatcher {
    /// The query's words, in order.
    public static func words(_ key: String) -> [String] {
        key.split(separator: " ").map(String.init)
    }

    public static func match(_ text: String, key: String, words: [String]) -> SearchMatchKind? {
        if text == key { return .exact }
        if text.hasPrefix(key) { return .prefix }
        if !words.isEmpty, words.allSatisfy({ text.contains($0) }) { return .partial }
        return nil
    }

    /// The stored text (or a run of it around the match when it is longer than `limit`
    /// characters, with «… » / « …» at a cut end) and the character range of the whole words
    /// that contain the match.
    public static func excerpt(_ text: String, normalized: NormalizedSearchText, key: String, words: [String],
                               limit: Int = 160, lead: Int = 50) -> (text: String, highlight: Range<Int>?) {
        let characters = Array(text)
        guard let scalars = matchScalarRange(normalized, key: key, words: words) else { return (text, nil) }
        let matched = wordRange(characters, coveringScalars: scalars)
        guard characters.count > limit, let matched else { return (text, matched) }
        var start = max(0, matched.lowerBound - lead)
        var end = min(characters.count, max(matched.upperBound, start + limit))
        while start > 0, !isSeparator(characters[start - 1]) { start -= 1 }
        while end < characters.count, !isSeparator(characters[end]) { end += 1 }
        let prefix = start > 0 ? "… " : ""
        let suffix = end < characters.count ? " …" : ""
        let shift = prefix.count - start
        return (prefix + String(characters[start..<end]) + suffix,
                (matched.lowerBound + shift)..<(matched.upperBound + shift))
    }

    static func matchScalarRange(_ normalized: NormalizedSearchText, key: String, words: [String]) -> Range<Int>? {
        let target = normalized.key.range(of: key, options: .literal) != nil ? key : (words.first ?? key)
        guard !target.isEmpty, let found = normalized.key.range(of: target, options: .literal) else { return nil }
        let scalars = normalized.key.unicodeScalars
        let lower = scalars.distance(from: normalized.key.startIndex, to: found.lowerBound)
        let upper = scalars.distance(from: normalized.key.startIndex, to: found.upperBound)
        guard lower < upper, upper <= normalized.sourceOffsets.count else { return nil }
        return normalized.sourceOffsets[lower]..<(normalized.sourceOffsets[upper - 1] + 1)
    }

    static func wordRange(_ characters: [Character], coveringScalars scalars: Range<Int>) -> Range<Int>? {
        var offset = 0
        var first: Int?
        var last: Int?
        for (index, character) in characters.enumerated() {
            let width = character.unicodeScalars.count
            if offset < scalars.upperBound, offset + width > scalars.lowerBound {
                if first == nil { first = index }
                last = index
            }
            offset += width
        }
        guard var lower = first, var upper = last.map({ $0 + 1 }) else { return nil }
        while lower > 0, !isSeparator(characters[lower - 1]) { lower -= 1 }
        while upper < characters.count, !isSeparator(characters[upper]) { upper += 1 }
        return lower..<upper
    }

    public static func isSeparator(_ character: Character) -> Bool {
        character.isWhitespace || character.isPunctuation || character.isSymbol
    }
}
