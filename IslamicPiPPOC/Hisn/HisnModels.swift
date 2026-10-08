import SwiftUI
import IslamicCore
import HisnReading
import HisnAudioPlayback

/// Opens a chapter at a display item. Built from the index, a search result or the saved position.
struct HisnRoute: Hashable {
    let chapterId: String
    let itemIndex: Int
    var completedRepetitions = 0
}

enum HisnSettings {
    static let hapticsKey = "hisn.reader.haptics"
}

/// Loads the bundled book through the repository and keeps the same-day resume position.
@MainActor
final class HisnLibraryModel: ObservableObject {
    enum State {
        case loading
        case loaded(HisnLibrary, HisnSearchIndex, HisnAudioRepository)
        case failed
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var resumePosition: HisnReadingPosition?
    let positionStore: HisnReadingPositionStore
    private let repository: HisnRepository

    init(repository: HisnRepository = BundledHisnRepository(),
         positionStore: HisnReadingPositionStore = UserDefaultsHisnReadingPositionStore()) {
        self.repository = repository
        self.positionStore = positionStore
    }

    func load() async {
        state = .loading
        do {
            let book = try await repository.loadBook()
            let audio = BundledHisnAudioRepository(knownItemIds: Set(book.allItems.map(\.id)))
            state = .loaded(HisnLibrary(book: book), HisnSearchIndex(book: book), audio)
            refreshResume()
        } catch {
            state = .failed
        }
    }

    func refreshResume() {
        guard case .loaded(let library, _, _) = state else { return }
        resumePosition = HisnResume.position(in: positionStore, library: library)
    }

    /// From the index: today's saved place in this chapter, otherwise its first item.
    func route(forChapter chapterId: String) -> HisnRoute {
        if let position = resumePosition, position.chapterId == chapterId {
            return route(for: position)
        }
        return HisnRoute(chapterId: chapterId, itemIndex: 0)
    }

    func route(for position: HisnReadingPosition) -> HisnRoute {
        HisnRoute(chapterId: position.chapterId, itemIndex: position.itemIndex,
                  completedRepetitions: position.completedRepetitions)
    }
}

extension HisnReaderController {
    /// The reader for one chapter with the item's recording, played through the app's single
    /// audio session owner.
    static func make(reader: HisnReader, store: HisnReadingPositionStore,
                     audioRepository: HisnAudioRepository) -> HisnReaderController {
        let audio = HisnAudioPlayer(repository: audioRepository, engine: AVHisnAudioEngine(),
                                    session: HisnAudioSessionCoordinator.shared)
        return HisnReaderController(reader: reader, store: store, audio: audio)
    }
}
