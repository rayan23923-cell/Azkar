import SwiftUI
import QuranText

@main
struct IslamicPiPPOCApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #if DEBUG
    /// The PiP technical test engine; Debug builds only (see `PiPTestEngine`).
    @StateObject private var engine = PiPTestEngine()
    #endif
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The Quran font is bundled; registering it is local and fast.
        _ = QuranFont.register()
    }

    var body: some Scene {
        WindowGroup {
            root
                // Keep the scheduled reminders equal to the saved settings (permission may
                // have changed in system Settings). Never asks for permission here.
                .task { await AppServices.shared.reminders.apply() }
        }
        #if DEBUG
        .onChange(of: scenePhase) { _, phase in
            engine.log("scenePhase -> \(phase)")
        }
        #endif
    }

    @ViewBuilder
    private var root: some View {
        #if DEBUG
        AppRootView().environmentObject(engine)
        #else
        AppRootView()
        #endif
    }
}
