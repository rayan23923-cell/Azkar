import SwiftUI
import QuranText

@main
struct IslamicPiPPOCApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var engine = PiPEngine()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The Quran font is bundled; registering it is local and fast.
        _ = QuranFont.register()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(engine)
                // Keep the scheduled reminders equal to the saved settings (permission may
                // have changed in system Settings). Never asks for permission here.
                .task { await AppServices.shared.reminders.apply() }
        }
        .onChange(of: scenePhase) { phase in
            engine.log("scenePhase -> \(phase)")
        }
    }
}
