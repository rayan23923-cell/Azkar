import Foundation
import IslamicCore
import ContentKit
import QuranReading
import HisnReading
import AdhkarReading
import GlobalSearch
import PiPCore
import PiPRendering

/// Opens an adhkar or dua collection, optionally at one item.
struct DevotionalRoute: Hashable {
    let collection: ContentRef
    var item: ContentRef?
    /// Set when opened from search or Favorites: the item is marked briefly.
    var highlights = false
}

/// Where a tap outside a section (Home, global search, Favorites, a reminder) wants to go.
/// The tab that owns the destination reads its target and clears it.
@MainActor
final class AppRouter: ObservableObject {
    enum Tab: String {
        case home
        case quran
        case hisn
        case adhkar
        case settings
        case pipTest
    }

    @Published var tab: Tab = .home
    @Published var quranTarget: QuranVerseRef?
    @Published var quranHighlights = false
    @Published var hisnTarget: HisnSearchResult?
    @Published var devotionalTarget: DevotionalRoute?

    func open(_ destination: GlobalSearchResult.Destination) {
        switch destination {
        case .quran(let ref, let highlights):
            quranHighlights = highlights
            quranTarget = ref
            tab = .quran
        case .hisn(let result):
            hisnTarget = result
            tab = .hisn
        case .devotional(let collection, let item):
            devotionalTarget = DevotionalRoute(collection: collection, item: item, highlights: item != nil)
            tab = .adhkar
        }
    }

    /// A stored reference: a Quran verse or surah, a dhikr or dua (item or collection).
    func open(_ ref: ContentRef, library: AdhkarLibrary?) {
        switch ref.kind {
        case .quran:
            if let verse = QuranVerseRef(ref) {
                open(.quran(verse, highlights: true))
            } else if let surah = Int(ref.id) {
                open(.quran(QuranVerseRef(surah: surah, ayah: 1), highlights: false))
            }
        case .adhkar, .dua:
            if let found = library?.locate(ref) {
                open(.devotional(collection: found.collection.ref, item: ref))
            } else {
                open(.devotional(collection: ref, item: nil))
            }
        case .hisn:
            tab = .hisn
        }
    }
}

/// The bundled content, loaded and indexed once and shared by every screen. Everything is
/// read from the app bundle; nothing goes to the network.
@MainActor
final class ContentStore {
    typealias Quran = (library: QuranLibrary, search: QuranSearchEngine)
    typealias Adhkar = (library: AdhkarLibrary, search: DevotionalSearchIndex)

    private var quranTask: Task<Quran, Error>?
    private var adhkarTask: Task<Adhkar, Error>?
    private var globalTask: Task<GlobalSearchEngine, Never>?

    func quran() async throws -> Quran {
        if quranTask == nil {
            quranTask = Task.detached(priority: .userInitiated) {
                let library = try await QuranLibrary.load()
                return (library, QuranSearchEngine(index: QuranSearchIndex(library: library)))
            }
        }
        do {
            return try await quranTask!.value
        } catch {
            quranTask = nil
            throw error
        }
    }

    func adhkar() async throws -> Adhkar {
        if adhkarTask == nil {
            adhkarTask = Task.detached(priority: .userInitiated) {
                let library = try await AdhkarLibrary.load()
                return (library, DevotionalSearchIndex(library: library))
            }
        }
        do {
            return try await adhkarTask!.value
        } catch {
            adhkarTask = nil
            throw error
        }
    }

    /// A section that fails to load is left out of global search rather than failing it.
    func globalSearch() async -> GlobalSearchEngine {
        if let globalTask { return await globalTask.value }
        let quran = try? await quran()
        let adhkar = try? await adhkar()
        let task = Task.detached(priority: .userInitiated) { () -> GlobalSearchEngine in
            let book = try? await BundledHisnRepository().loadBook()
            return GlobalSearchEngine(quran: quran.map { ($0.library, $0.search) },
                                      hisn: book.map { ($0, HisnSearchEngine(index: HisnSearchIndex(book: $0))) },
                                      adhkar: adhkar.map { ($0.library, $0.search) })
        }
        globalTask = task
        return await task.value
    }
}

/// The app's long-lived services, created once. Views read them from here; nothing in it
/// talks to the network.
@MainActor
final class AppServices: ObservableObject {
    static let shared = AppServices()

    let reminders: ReminderController
    let dailyProgress: DailyProgressStore
    let favorites: FavoritesModel
    let devotionalPositions: DevotionalPositionStore
    let router = AppRouter()
    let content = ContentStore()
    /// The one PiP engine of the app (Quran, Hisn, adhkar and duas).
    let pip: PiPEngine
    /// The PiP frame's size and layout, from the orientation setting read at launch (pages and
    /// frames must agree, so a change applies the next time the app opens).
    let pipLayout: PiPLayout

    private init() {
        reminders = ReminderController(store: UserDefaultsReminderStore(), scheduler: SystemReminderScheduler())
        dailyProgress = UserDefaultsDailyProgressStore()
        favorites = FavoritesModel(store: UserDefaultsFavoritesStore())
        devotionalPositions = UserDefaultsDevotionalPositionStore()
        // PiP is offered only when this build declares the PiP background mode (see
        // docs/UNIFIED_PIP.md) and the user's
        // «العرض العائم» setting is on. It always starts from a button, never automatically.
        let availability = PiPAvailability(
            backgroundModeDeclared: PiPAvailability.backgroundModeDeclared(in: Bundle.main.infoDictionary),
            userEnabled: UserDefaults.standard.object(forKey: PiPAvailability.settingKey) as? Bool ?? true)
        pipLayout = PiPLayout.saved()
        pip = PiPEngine(paginator: CoreTextPiPPaginator(layout: pipLayout), sessionStore: UserDefaultsPiPSessionStore(),
                        availability: availability)
        pip.onRestoreUserInterface = { [router] type in
            // "Return to app" in the window opens the section it shows.
            switch type {
            case .quran: router.tab = .quran
            case .hisn: router.tab = .hisn
            case .dhikr, .dua: router.tab = .adhkar
            }
        }
    }

    func isCompletedToday(_ ref: ContentRef) -> Bool {
        dailyProgress.completed(on: DayKey(date: Date())).contains(ref)
    }
}
