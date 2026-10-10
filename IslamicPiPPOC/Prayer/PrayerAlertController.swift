import ContentKit
import Foundation
import PrayerTimes
import UserNotifications

/// The adhan alerts: one local notification at each chosen prayer's time («حان الآن وقت صلاة
/// الظهر»), so the time is announced even with the app closed. Nothing leaves the device.
///
/// Each alert is a one-off notification at that day's computed time (times move every day),
/// scheduled nine days ahead and again each time the app opens or the place, the method or a
/// correction changes. Permission is asked only when the user turns an alert on.
@MainActor
final class PrayerAlertController: ObservableObject {
    @Published private(set) var settings: PrayerAlertSettings
    @Published private(set) var authorization: ReminderAuthorization = .notDetermined
    /// Set when scheduling failed; cleared by the next successful apply.
    @Published private(set) var lastError: String?

    private let store: PrayerAlertStore
    private var center: UNUserNotificationCenter { .current() }
    /// The latest apply; a newer one cancels it so two never interleave their removals and adds.
    private var applying: Task<Void, Never>?

    init(store: PrayerAlertStore = PrayerAlertStore()) {
        self.store = store
        settings = store.settings
    }

    func refreshAuthorization() async {
        authorization = await Self.authorization(center)
    }

    func setEnabled(_ enabled: Bool, for prayer: Prayer, schedule: PrayerSchedule?, placeName: String?) async {
        settings.set(prayer, enabled: enabled)
        store.settings = settings
        authorization = await Self.authorization(center)
        if enabled && authorization == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            authorization = granted ? .allowed : .denied
        }
        apply(schedule: schedule, placeName: placeName)
    }

    /// Replaces the pending alerts with the ones for `schedule` from now on.
    func apply(schedule: PrayerSchedule?, placeName: String?) {
        let settings = settings
        applying?.cancel()
        let previous = applying
        applying = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            let center = self.center
            let pending = await center.pendingNotificationRequests()
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(PrayerAlertPlanner.identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            self.authorization = await Self.authorization(center)
            guard self.authorization == .allowed, let schedule, let placeName else {
                self.lastError = nil
                return
            }
            let requests = PrayerAlertPlanner.requests(schedule: schedule, settings: settings,
                                                       placeName: placeName, from: Date())
            do {
                for request in requests {
                    guard !Task.isCancelled else { return }
                    try await center.add(Self.notification(request, timeZone: schedule.timeZone))
                }
                self.lastError = nil
            } catch {
                self.lastError = "تعذّر جدولة تنبيه الأذان"
            }
        }
    }

    private static func notification(_ request: PrayerAlertRequest, timeZone: TimeZone) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = [AppNotificationKeys.link: AppLink.prayerTimes.url.absoluteString]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: request.date)
        parts.calendar = calendar
        parts.timeZone = timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger)
    }

    private static func authorization(_ center: UNUserNotificationCenter) async -> ReminderAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .allowed
        }
    }
}
