import SwiftUI
import IslamicCore
import ContentKit
import QuranReading
import AdhkarReading
import GlobalSearch

/// The first tab: the adhkar for this time of day, where reading stopped, today's progress,
/// search across everything, and Favorites.
struct HomeView: View {
    @ObservedObject private var router = AppServices.shared.router
    @ObservedObject private var favorites = AppServices.shared.favorites
    @State private var quranResume: (position: QuranReadingPosition, surah: QuranSurah)?
    @State private var adhkar: AdhkarLibrary?
    @State private var completedToday: Set<ContentRef> = []
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        GlobalSearchView()
                    } label: {
                        Label("البحث في القرآن والأذكار والأدعية", systemImage: "magnifyingglass")
                    }
                }

                if let adhkar {
                    Section("أذكار اليوم") {
                        ForEach(suggested(in: adhkar)) { collection in
                            let done = completedToday.contains(collection.ref)
                            Button {
                                router.open(.devotional(collection: collection.ref, item: nil))
                            } label: {
                                HStack {
                                    Label(collection.title, systemImage: icon(for: collection.ref))
                                    Spacer()
                                    if done {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    }
                                }
                            }
                            .accessibilityLabel(DevotionalAccessibility.collectionLabel(collection, completedToday: done))
                        }
                    }
                }

                Section("متابعة") {
                    if let resume = quranResume {
                        Button {
                            router.open(.quran(resume.position.ref, highlights: false))
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("القرآن الكريم: \(resume.surah.fullArabicName)")
                                    Text("الآية \(resume.position.ayah) من \(resume.surah.ayahCount)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: "book") }
                        }
                    } else {
                        Button {
                            router.tab = .quran
                        } label: { Label("ابدأ قراءة القرآن الكريم", systemImage: "book") }
                    }
                    Button {
                        router.tab = .hisn
                    } label: { Label("حصن المسلم", systemImage: "shield") }
                }

                Section {
                    NavigationLink {
                        FavoritesView()
                    } label: {
                        Label("المفضلة والعلامات", systemImage: "star")
                            .badge(favorites.entries.count)
                    }
                    LabeledContent("أُنجز اليوم", value: progressText)
                        .accessibilityElement(children: .combine)
                }
            }
            .navigationTitle("الرئيسية")
        }
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
        .task { await reload() }
        .onChange(of: router.tab) { Task { await reload() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reload() } }
        }
    }

    private var progressText: String {
        switch completedToday.count {
        case 0: return "لا شيء بعد"
        case 1: return "قسم واحد"
        case 2: return "قسمان"
        case 3...10: return "\(completedToday.count) أقسام"
        default: return "\(completedToday.count) قسماً"
        }
    }

    /// Morning adhkar until mid-afternoon, evening adhkar after; sleep adhkar at night.
    private func suggested(in library: AdhkarLibrary) -> [DevotionalCollection] {
        let hour = Calendar.current.component(.hour, from: Date())
        let ids: [String]
        switch hour {
        case 3..<15: ids = ["morning", "afterPrayer"]
        case 15..<21: ids = ["evening", "afterPrayer"]
        default: ids = ["sleep", "evening"]
        }
        return ids.compactMap { library.collection(.dhikrGroup($0)) }
    }

    private func icon(for ref: ContentRef) -> String {
        if ref == .dhikrGroup("morning") { return "sunrise" }
        if ref == .dhikrGroup("evening") { return "sunset" }
        if ref == .dhikrGroup("sleep") { return "moon.stars" }
        return "hands.sparkles"
    }

    private func reload() async {
        completedToday = AppServices.shared.dailyProgress.completed(on: DayKey(date: Date()))
        if let quran = try? await AppServices.shared.content.quran(),
           let position = UserDefaultsQuranPositionStore().validPosition(in: quran.library),
           let surah = quran.library.surah(position.surah) {
            quranResume = (position, surah)
        } else {
            quranResume = nil
        }
        adhkar = try? await AppServices.shared.content.adhkar().library
    }
}
