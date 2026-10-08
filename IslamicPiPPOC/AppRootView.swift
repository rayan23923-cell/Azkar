import SwiftUI

/// The app's tabs: Home, Quran, Hisn Al-Muslim, Adhkar and Duas, Settings. The PiP technical
/// test screen (PiPEngine, unchanged) is a tab in Debug builds only.
struct AppRootView: View {
    @ObservedObject private var router = AppServices.shared.router
    @AppStorage(AppAppearance.key) private var appearance: AppAppearance = .system

    var body: some View {
        TabView(selection: $router.tab) {
            HomeView()
                .tabItem { Label("الرئيسية", systemImage: "house") }
                .tag(AppRouter.Tab.home)
            QuranRootView()
                .tabItem { Label("القرآن", systemImage: "book") }
                .tag(AppRouter.Tab.quran)
            HisnRootView()
                .tabItem { Label("حصن المسلم", systemImage: "shield") }
                .tag(AppRouter.Tab.hisn)
            AdhkarRootView()
                .tabItem { Label("الأذكار", systemImage: "hands.sparkles") }
                .tag(AppRouter.Tab.adhkar)
            NavigationStack {
                SettingsView(reminders: AppServices.shared.reminders)
            }
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar"))
            .tabItem { Label("الإعدادات", systemImage: "gearshape") }
            .tag(AppRouter.Tab.settings)
            #if DEBUG
            ContentView()
                .tabItem { Label("اختبار العرض العائم", systemImage: "pip") }
                .tag(AppRouter.Tab.pipTest)
            #endif
        }
        .environment(\.layoutDirection, .rightToLeft)
        .preferredColorScheme(appearance.colorScheme)
    }
}
