import Foundation
import PrayerTimes

/// The App Group the widgets read from. Its id comes from the build (`AZKAR_APP_GROUP`, in the
/// Info.plist as `AzkarAppGroup`), so it follows the bundle identifier the owner signs with.
/// Only the prayer place and settings are copied there; nothing else leaves the app.
enum SharedContainer {
    /// The widgets' copy of the prayer settings; nil when the build names no group, or when
    /// iOS gives no container for it (an unsigned build, or a group not registered for the
    /// signing team). Then nothing is written: `UserDefaults(suiteName:)` would otherwise
    /// write to a private file the widget never sees.
    /// A re-signed installation may share a renamed group, found in its provisioning profile
    /// (`AppGroupLocator`); the widget looks it up the same way.
    static func prayerStore() -> PrayerSettingsStore? {
        guard let group = AppGroupLocator.resolve(), let defaults = UserDefaults(suiteName: group) else { return nil }
        return PrayerSettingsStore(defaults: defaults)
    }
}
