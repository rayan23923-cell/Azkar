import Foundation
import ContentKit

/// The app's long-lived services, created once. Views read them from here; nothing in it
/// talks to the network.
@MainActor
final class AppServices: ObservableObject {
    static let shared = AppServices()

    let reminders: ReminderController
    let dailyProgress: DailyProgressStore

    private init() {
        reminders = ReminderController(store: UserDefaultsReminderStore(), scheduler: SystemReminderScheduler())
        dailyProgress = UserDefaultsDailyProgressStore()
    }
}
