import SwiftUI
import IslamicCore
import HisnReading

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
        case loaded(HisnLibrary, HisnSearchIndex)
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
            state = .loaded(HisnLibrary(book: book), HisnSearchIndex(book: book))
            refreshResume()
        } catch {
            state = .failed
        }
    }

    func refreshResume() {
        guard case .loaded(let library, _) = state else { return }
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

/// One open chapter. Every change goes through `HisnReader` and is saved for same-day resume.
@MainActor
final class HisnReaderModel: ObservableObject {
    @Published private(set) var reader: HisnReader
    /// Changes on every counted recitation; drives the optional haptic.
    @Published private(set) var recitations = 0
    private let store: HisnReadingPositionStore

    init(reader: HisnReader, store: HisnReadingPositionStore) {
        self.reader = reader
        self.store = store
        save()
    }

    func recite() {
        reader.recite()
        recitations += 1
        save()
    }

    func next() {
        reader.next()
        save()
    }

    func previous() {
        reader.previous()
        save()
    }

    func restart() {
        reader.restart()
        save()
    }

    private func save() {
        HisnResume.record(reader, in: store)
    }
}
