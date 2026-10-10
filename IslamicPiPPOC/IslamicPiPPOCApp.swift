import SwiftUI
import QuranText
import ContentKit

@main
struct IslamicPiPPOCApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #if DEBUG
    /// The PiP technical test engine; Debug builds only (see `PiPTestEngine`).
    @StateObject private var engine = PiPTestEngine()
    #endif
    @Environment(\.scenePhase) private var scenePhase
    /// The launch animation, once per launch.
    @State private var showsSplash = true

    init() {
        // The Quran font is bundled; registering it is local and fast.
        _ = QuranFont.register()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                root
                if showsSplash {
                    LaunchSplashView { showsSplash = false }
                        .transition(.identity)
                        .zIndex(1)
                }
            }
                // Keep the scheduled reminders equal to the saved settings (permission may
                // have changed in system Settings). Never asks for permission here.
                .task { await AppServices.shared.reminders.apply() }
                // azkarapp:// links from the widgets, shortcuts or another app. Unknown or
                // malformed links are ignored.
                .onOpenURL { url in
                    if let link = AppLink(url: url) { AppServices.shared.router.handle(link) }
                }
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
