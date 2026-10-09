import SwiftUI
import WidgetKit
import PrayerTimes

/// The app's widgets: the next prayer (Home Screen and Lock Screen) and the dhikr of the day.
/// Both are computed on the device; nothing is fetched.
@main
struct AzkarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextPrayerWidget()
        DailyDhikrWidget()
    }
}

/// The prayer settings the app copies into the App Group (`AzkarAppGroup` in Info.plist).
enum WidgetSettings {
    static func prayerStore() -> PrayerSettingsStore? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "AzkarAppGroup") as? String, !group.isEmpty,
              let defaults = UserDefaults(suiteName: group) else { return nil }
        return PrayerSettingsStore(defaults: defaults)
    }
}
