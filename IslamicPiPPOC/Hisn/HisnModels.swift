import SwiftUI
import IslamicCore
import HisnReading
import HisnAudioPlayback
import ContentKit
import PiPProviders

/// Opens a chapter at a display item. Built from the index, a search result or the saved position.
struct HisnRoute: Hashable {
    let chapterId: String
    let itemIndex: Int
    var completedRepetitions = 0
    /// Set when opened from an item search result: the reader marks this item briefly.
    var highlightedItemId: String?
}

enum HisnSettings {
    static let hapticsKey = "hisn.reader.haptics"
}

/// Loads the bundled book through the repository and offers the saved reading cursor.
@MainActor
final class HisnLibraryModel: ObservableObject {
    enum State {
        case loading
        case loaded(HisnLibrary, HisnSearchEngine, HisnAudioRepository)
        case failed
    }

    @Published private(set) var state: State = .loading
    var isLoaded: Bool {
        if case .loaded = state { return true }
        return false
    }
    @Published private(set) var resumePosition: HisnReadingPosition?
    /// Sections read to the end today.
    @Published private(set) var completedToday: Set<ContentRef> = []
    let positionStore: HisnReadingPositionStore
    let dailyProgress: DailyProgressStore
    private let repository: HisnRepository

    init(repository: HisnRepository = BundledHisnRepository(),
         positionStore: HisnReadingPositionStore = UserDefaultsHisnReadingPositionStore(),
         dailyProgress: DailyProgressStore = UserDefaultsDailyProgressStore()) {
        self.repository = repository
        self.positionStore = positionStore
        self.dailyProgress = dailyProgress
    }

    func load() async {
        state = .loading
        do {
            let book = try await repository.loadBook()
            let itemIds = Set(book.allItems.map(\.id))
            #if HISN_AUDIO_FIXTURE
            let audio = HisnAudioFixture.repository(knownItemIds: itemIds)
                ?? BundledHisnAudioRepository(knownItemIds: itemIds)
            #else
            let audio = BundledHisnAudioRepository(knownItemIds: itemIds)
            #endif
            // The search index is built once here and shared by every query.
            state = .loaded(HisnLibrary(book: book), HisnSearchEngine(index: HisnSearchIndex(book: book)), audio)
            refreshResume()
        } catch {
            state = .failed
        }
    }

    func refreshResume() {
        guard case .loaded(let library, _, _) = state else { return }
        resumePosition = HisnResume.position(in: positionStore, library: library)
        completedToday = dailyProgress.completed(on: DayKey(date: Date()))
    }

    func isCompletedToday(_ sectionId: String) -> Bool {
        completedToday.contains(.hisnSection(sectionId))
    }

    /// From the index: the saved place when it is in this chapter, otherwise its first item.
    func route(forChapter chapterId: String) -> HisnRoute {
        if let position = resumePosition, position.chapterId == chapterId {
            return route(for: position)
        }
        return HisnRoute(chapterId: chapterId, itemIndex: 0)
    }

    /// A search result's place, or nil when it no longer points at a real chapter or item.
    func route(for result: HisnSearchResult) -> HisnRoute? {
        guard case .loaded(let library, _, _) = state,
              let destination = HisnSearchDestination.resolve(result, in: library, cursor: resumePosition) else {
            return nil
        }
        return HisnRoute(chapterId: destination.chapterId, itemIndex: destination.itemIndex,
                         completedRepetitions: destination.completedRepetitions,
                         highlightedItemId: destination.highlightedItemId)
    }

    /// A saved item (Favorites), marked briefly when it opens; nil when it no longer exists.
    func route(forItem itemId: String) -> HisnRoute? {
        guard case .loaded(let library, _, _) = state, let found = library.locate(itemId: itemId) else { return nil }
        return HisnRoute(chapterId: found.chapter.id, itemIndex: found.itemIndex, highlightedItemId: itemId)
    }

    func route(for position: HisnReadingPosition) -> HisnRoute {
        HisnRoute(chapterId: position.chapterId, itemIndex: position.itemIndex,
                  completedRepetitions: position.completedRepetitions)
    }
}

extension HisnReaderController {
    /// The reader for one chapter with the item's recording, played through the app's single
    /// audio session owner.
    static func make(reader: HisnReader, store: HisnReadingPositionStore, dailyProgress: DailyProgressStore,
                     audioRepository: HisnAudioRepository) -> HisnReaderController {
        let audio = HisnAudioPlayer(repository: audioRepository, engine: AVHisnAudioEngine(),
                                    session: AudioSessionCoordinator.shared)
        return HisnReaderController(reader: reader, store: store, audio: audio, haptics: SystemHisnHaptics.shared,
                                    dailyProgress: dailyProgress, counts: AppServices.shared.itemCounts)
    }
}

/// Everything one open chapter needs, created once per reader screen: the reader and its
/// recording (`HisnReaderController`), and its PiP (`HisnPiPProvider` on the app's PiP engine).
/// PiP reads the controller; the controller does not know about PiP.
@MainActor
final class HisnReaderScreenModel: ObservableObject {
    let controller: HisnReaderController
    let pip: ReaderPiP
    let actions: HisnItemActions

    init(reader: HisnReader, store: HisnReadingPositionStore, dailyProgress: DailyProgressStore,
         audioRepository: HisnAudioRepository) {
        controller = .make(reader: reader, store: store, dailyProgress: dailyProgress, audioRepository: audioRepository)
        pip = ReaderPiP(provider: HisnPiPProvider(controller: controller))
        actions = HisnItemActions(pasteboard: SystemPasteboard(), haptics: SystemHisnHaptics.shared)
    }

    /// The screen went away. Closed (popped): leave PiP, stop the recording and save the place.
    /// Another tab while PiP shows this chapter: PiP keeps running on this reader.
    func disappeared(closed: Bool) {
        if closed || !pip.isRunning {
            pip.screenClosed()
            controller.close()
        } else {
            controller.persist()
        }
    }
}
