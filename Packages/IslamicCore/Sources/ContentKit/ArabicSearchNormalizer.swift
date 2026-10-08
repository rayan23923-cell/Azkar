import Foundation

/// A search key and, for each of its characters, where that character came from in the text.
public struct NormalizedSearchText: Hashable, Sendable {
    /// Arabic letters and single spaces only.
    public let key: String
    /// `sourceOffsets[i]` is the unicode-scalar offset in the original text of key scalar `i`
    /// (for a space, the first separator it replaces). Lets a match in the key be pointed back
    /// at the original, unchanged text.
    public let sourceOffsets: [Int]

    public init(key: String, sourceOffsets: [Int]) {
        self.key = key
        self.sourceOffsets = sourceOffsets
    }
}

/// Arabic search normalization shared by every content type. It only builds keys for
/// comparison: stored text is never changed.
///
/// The rules are those of `tools/content/build_content.py` (`search_text`):
/// - Arabic marks (tashkeel, Quranic annotation signs and small high letters, superscript
///   alef) are dropped;
/// - tatweel «ـ» is dropped;
/// - أ إ آ ٱ become ا;
/// - ى becomes ي;
/// - ة becomes ه;
/// - anything that is not an Arabic letter separates words, and runs of separators become one
///   space; none at either end.
public enum ArabicSearchNormalizer {
    public static func normalize(_ text: String) -> String {
        normalizeMapped(text).key
    }

    public static func normalizeMapped(_ text: String) -> NormalizedSearchText {
        var key = String.UnicodeScalarView()
        var offsets: [Int] = []
        var pendingSpace: Int?
        for (offset, scalar) in text.unicodeScalars.enumerated() {
            let value = scalar.value
            if isDropped(value) { continue }
            let letter = fold(scalar)
            if (0x0621...0x064A).contains(letter.value) {
                if let space = pendingSpace, !key.isEmpty {
                    key.append(" ")
                    offsets.append(space)
                }
                pendingSpace = nil
                key.append(letter)
                offsets.append(offset)
            } else if pendingSpace == nil {
                pendingSpace = offset
            }
        }
        return NormalizedSearchText(key: String(key), sourceOffsets: offsets)
    }

    private static func isDropped(_ value: UInt32) -> Bool {
        (0x0610...0x061A).contains(value) || (0x064B...0x065F).contains(value) || value == 0x0670
            || (0x06D6...0x06ED).contains(value) || value == 0x0640
    }

    private static func fold(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        switch scalar.value {
        case 0x0623, 0x0625, 0x0622, 0x0671: return "\u{0627}"
        case 0x0649: return "\u{064A}"
        case 0x0629: return "\u{0647}"
        default: return scalar
        }
    }
}
