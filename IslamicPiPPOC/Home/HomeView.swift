import SwiftUI
import IslamicCore
import ContentKit
import QuranReading
import AdhkarReading
import GlobalSearch
import PrayerTimes

/// The first tab: the adhkar for this time of day, where reading stopped, today's progress,
/// search across everything, and Favorites.
struct HomeView: View {
    @ObservedObject private var router = AppServices.shared.router
    @ObservedObject private var favorites = AppServices.shared.favorites
    @ObservedObject private var prayer = PrayerModel.shared
    @ObservedObject private var routine = AppServices.shared.routine
    @State private var resume: ResumeOffer?
    @State private var quranResume: (position: QuranReadingPosition, surah: QuranSurah)?
    @State private var adhkar: AdhkarLibrary?
    @State private var completedToday: Set<ContentRef> = []
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        PrayerTimesView()
                    } label: {
                        prayerRow
                    }
                    NavigationLink {
                        QiblaView()
                    } label: {
                        Label("اتجاه القبلة", systemImage: "location.north.line")
                    }
                }

                if routine.routine.isEnabled, !routine.routine.activeSteps.isEmpty {
                    routineSection
                }

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
                    if let resume {
                        Button {
                            router.open(resume.point)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("أكمل من حيث توقفت")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(resume.title)
                                    Text(resume.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: resume.systemImage) }
                        }
                        .accessibilityLabel("أكمل من حيث توقفت: \(resume.title)، \(resume.detail)")
                    }
                    // The Quran row, unless the Quran is already the place offered above.
                    if resume?.point.section != .quran {
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
            // A widget or shortcut opens the prayer times or the Qibla here.
            .navigationDestination(item: $router.homeDestination) { destination in
                switch destination {
                case .prayerTimes: PrayerTimesView()
                case .qibla: QiblaView()
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
        .task { await reload() }
        .onChange(of: router.tab) { Task { await reload() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reload() } }
        }
    }

    /// The next prayer and the time left, or a prompt to set the place.
    private var prayerRow: some View {
        TimelineView(.everyMinute) { context in
            if let schedule = prayer.schedule, let next = schedule.next(after: context.date) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(next.prayer.arabicName) \(PrayerFormat.clock(next.time, timeZone: schedule.timeZone, twentyFourHour: prayer.twentyFourHour))")
                        Text("\(PrayerFormat.remaining(from: context.date, to: next.time)) · مواقيت الصلاة")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "clock") }
            } else {
                Label("مواقيت الصلاة", systemImage: "clock")
            }
        }
    }

    /// The optional routine: today's chosen steps, each marked when done today. Nothing
    /// counts days or mentions a missed one.
    private var routineSection: some View {
        Section {
            ForEach(routine.routine.activeSteps, id: \.self) { step in
                let done = isDone(step)
                Button {
                    if let collection = step.collection {
                        router.open(.devotional(collection: collection, item: nil))
                    } else {
                        Task { await router.openQuranAtSavedPosition() }
                    }
                } label: {
                    HStack {
                        Label(step.arabicTitle, systemImage: icon(for: step))
                        Spacer()
                        if done { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                    }
                }
                .accessibilityLabel(done ? "\(step.arabicTitle)، أُنجز اليوم" : step.arabicTitle)
            }
        } header: {
            Text("وردي اليوم")
        } footer: {
            Text("اختياري: لا عدّ للأيام ولا تذكير بما فات. تغيّره من الإعدادات.")
        }
    }

    private func isDone(_ step: DailyRoutine.Step) -> Bool {
        if let collection = step.collection { return completedToday.contains(collection) }
        // The Quran counts as read today once a verse was reached today.
        return quranResume.map { Calendar.current.isDateInToday($0.position.savedAt) } ?? false
    }

    private func icon(for step: DailyRoutine.Step) -> String {
        if let collection = step.collection { return icon(for: collection) }
        return "book"
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
        resume = await ResumeFinder.latest()
    }
}
