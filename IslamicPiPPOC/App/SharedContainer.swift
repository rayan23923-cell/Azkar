import Foundation
import PrayerTimes

/// The App Group the widgets read from. Its id comes from the build (`AZKAR_APP_GROUP`, in the
/// Info.plist as `AzkarAppGroup`), so it follows the bundle identifier the owner signs with.
/// Only the prayer place and settings are copied there; nothing else leaves the app.
enum SharedContainer {
    static var groupID: String? {
        (Bundle.main.object(forInfoDictionaryKey: "AzkarAppGroup") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The widgets' copy of the prayer settings; nil when the build names no group.
    static func prayerStore() -> PrayerSettingsStore? {
        guard let groupID, let defaults = UserDefaults(suiteName: groupID) else { return nil }
        return PrayerSettingsStore(defaults: defaults)
    }
}
