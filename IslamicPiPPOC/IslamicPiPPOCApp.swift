import SwiftUI

@main
struct IslamicPiPPOCApp: App {
    @StateObject private var engine = PiPEngine()
    @Environment(\.scenePhase) private var scenePhase

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
