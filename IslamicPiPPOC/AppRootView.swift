import SwiftUI

/// The app's navigation: Hisn Al-Muslim is the main tab; the PiP technical test screen
/// (PiPEngine, unchanged) stays available as the second tab.
struct AppRootView: View {
    private enum Tab: String {
        case hisn
        case pipTest
    }

    @SceneStorage("app.selectedTab") private var selection: Tab = .hisn

    var body: some View {
        TabView(selection: $selection) {
            HisnRootView()
                .tabItem { Label("حصن المسلم", systemImage: "book") }
                .tag(Tab.hisn)
            ContentView()
                .tabItem { Label("اختبار العرض العائم", systemImage: "pip") }
                .tag(Tab.pipTest)
        }
    }
}
