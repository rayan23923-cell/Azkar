import Foundation

/// A place in the app a widget, a shortcut or another app can open, as an `azkarapp://` URL.
/// Opening a link only shows the place: it never counts a repetition or marks anything done.
///
/// - `azkarapp://home`, `azkarapp://prayer`, `azkarapp://qibla`
/// - `azkarapp://resume`: the most recent place read (see `ResumePoint`)
/// - `azkarapp://quran`: the Quran at the saved position, or its index
/// - `azkarapp://open?ref=adhkar:group:morning`: one item or collection by its `ContentRef`
///
/// Anything else, including a ref that does not parse, is not a link (nil), so a malformed URL
/// from outside opens nothing rather than a wrong place.
public enum AppLink: Hashable, Sendable {
    case home
    case prayerTimes
    case qibla
    case resume
    case quran
    case content(ContentRef)

    public static let scheme = "azkarapp"
    /// Longer URLs are refused before parsing; no real link comes close.
    static let maximumLength = 300

    public init?(url: URL) {
        guard url.absoluteString.count <= Self.maximumLength,
              url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else { return nil }
        // Only the bare host forms below; a path or stray query is not ours.
        let path = components.path
        guard path.isEmpty || path == "/" else { return nil }
        let query = components.queryItems ?? []
        if host == "open" {
            guard query.count == 1, query[0].name == "ref", let raw = query[0].value,
                  let ref = ContentRef(string: raw) else { return nil }
            self = .content(ref)
            return
        }
        guard query.isEmpty else { return nil }
        switch host {
        case "home": self = .home
        case "prayer": self = .prayerTimes
        case "qibla": self = .qibla
        case "resume": self = .resume
        case "quran": self = .quran
        default: return nil
        }
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .home: components.host = "home"
        case .prayerTimes: components.host = "prayer"
        case .qibla: components.host = "qibla"
        case .resume: components.host = "resume"
        case .quran: components.host = "quran"
        case .content(let ref):
            components.host = "open"
            components.queryItems = [URLQueryItem(name: "ref", value: ref.string)]
        }
        // Every case above is a valid URL.
        return components.url!
    }
}
