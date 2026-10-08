import Foundation
import ContentKit

/// A search key and the map back to the original text (see `NormalizedSearchText`).
public typealias HisnNormalizedText = NormalizedSearchText

/// Hisn search normalization: the app-wide Arabic rules of `ArabicSearchNormalizer`, which are
/// those of the content builder's `search_text`, so a typed query compares with the bundled
/// `searchText` fields. It only builds keys; the stored text is never changed.
public enum HisnSearchNormalizer {
    public static func normalize(_ text: String) -> String {
        ArabicSearchNormalizer.normalize(text)
    }

    public static func normalizeMapped(_ text: String) -> HisnNormalizedText {
        ArabicSearchNormalizer.normalizeMapped(text)
    }
}
