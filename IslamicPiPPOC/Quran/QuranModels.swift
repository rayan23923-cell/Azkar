import SwiftUI
import IslamicCore
import ContentKit
import QuranReading
import QuranText

/// Opens a surah at a verse. From the index, a juz, a bookmark, search or the saved position.
struct QuranRoute: Hashable {
    let surah: Int
    let ayah: Int
    /// Set when opened from a search result or a bookmark: the verse is marked briefly.
    var highlights = false
}

/// The bundled Quran and its search index (built once, off the main thread, in `ContentStore`).
@MainActor
final class QuranLibraryModel: ObservableObject {
    enum State {
        case loading
        case loaded(QuranLibrary, QuranSearchEngine)
        case failed
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var resume: QuranReadingPosition?
    let positionStore: QuranPositionStore

    init(positionStore: QuranPositionStore = UserDefaultsQuranPositionStore()) {
        self.positionStore = positionStore
    }

    var library: QuranLibrary? {
        if case .loaded(let library, _) = state { return library }
        return nil
    }

    func load() async {
        state = .loading
        do {
            let quran = try await AppServices.shared.content.quran()
            state = .loaded(quran.library, quran.search)
            refreshResume()
        } catch {
            state = .failed
        }
    }

    func refreshResume() {
        guard let library else { return }
        resume = positionStore.validPosition(in: library)
    }
}
