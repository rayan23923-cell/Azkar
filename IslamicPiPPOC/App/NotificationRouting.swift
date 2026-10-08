import UIKit
import UserNotifications
import ContentKit

/// Opens the adhkar a reminder points at when the user taps it, and shows reminders that
/// arrive while the app is open.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo[AppNotificationKeys.target] as? String,
              let ref = ContentRef(string: raw) else { return }
        await MainActor.run {
            AppServices.shared.router.open(ref, library: nil)
        }
    }
}
