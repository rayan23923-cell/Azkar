import Foundation
import UserNotifications
import ContentKit

/// `UNUserNotificationCenter` behind `ReminderScheduling`. Local notifications only; nothing
/// leaves the device. Each reminder repeats daily at a wall-clock time (calendar trigger), so
/// it follows time-zone and daylight-saving changes.
@MainActor
final class SystemReminderScheduler: ReminderScheduling {
    private var center: UNUserNotificationCenter { .current() }

    func authorization() async -> ReminderAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .allowed
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func removeRequests(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func add(_ request: ReminderRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = [AppNotificationKeys.target: request.target.string]
        var time = DateComponents()
        time.hour = request.hour
        time.minute = request.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        try await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
    }
}

enum AppNotificationKeys {
    /// `ContentRef.string` of what the notification opens.
    static let target = "target"
    /// `AppLink` URL of the screen the notification opens (the adhan alerts open the times).
    static let link = "link"
}
