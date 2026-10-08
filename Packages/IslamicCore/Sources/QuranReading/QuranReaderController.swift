import Combine
import Foundation
import IslamicCore
import ContentKit

/// One open surah on screen. The reader reports which verse is at the top of the screen; the
/// controller keeps it, saves it as the reading position at reading transitions (open, jump,
/// change of surah, leaving), and records the surah as read today when its last verse is shown.
@MainActor
public final class QuranReaderController: ObservableObject {
    @Published public private(set) var surah: QuranSurah
    /// The verse at the top of the screen (1-based).
    @Published public private(set) var currentAyah: Int
    /// Changes when the screen should scroll to `currentAyah` (open, jump, change of surah).
    @Published public private(set) var scrollRequest = 0

    public let library: QuranLibrary
    private let store: QuranPositionStore
    private let dailyProgress: DailyProgressStore?
    private let now: () -> Date

    public init?(library: QuranLibrary, start: QuranVerseRef, store: QuranPositionStore,
                 dailyProgress: DailyProgressStore? = nil, now: @escaping () -> Date = Date.init) {
        guard let surah = library.surah(start.surah), library.contains(start) else { return nil }
        self.library = library
        self.surah = surah
        self.currentAyah = start.ayah
        self.store = store
        self.dailyProgress = dailyProgress
        self.now = now
        persist()
    }

    public var verses: [QuranVerse] { library.verses(of: surah.id) }
    public var currentRef: QuranVerseRef { QuranVerseRef(surah: surah.id, ayah: currentAyah) }
    public var juz: Int { library.juz(of: currentRef) }
    public var page: Int { library.page(of: currentRef) }
    /// 0...1 within the surah.
    public var progress: Double { Double(currentAyah) / Double(max(1, surah.ayahCount)) }
    public var previousSurah: QuranSurah? { library.surah(surah.id - 1) }
    public var nextSurah: QuranSurah? { library.surah(surah.id + 1) }

    /// The screen scrolled: this verse is now at the top. Not saved on every scroll.
    public func visible(ayah: Int) {
        guard (1...surah.ayahCount).contains(ayah) else { return }
        if ayah != currentAyah { currentAyah = ayah }
    }

    /// The last verse came into view: the surah counts as read today.
    public func reachedEnd() {
        dailyProgress?.markCompleted(.quranSurah(surah.id), on: DayKey(date: now()))
    }

    /// Jumps to a verse of this surah. False (and no move) when it does not exist.
    @discardableResult
    public func go(to ayah: Int) -> Bool {
        guard (1...surah.ayahCount).contains(ayah) else { return false }
        currentAyah = ayah
        scrollRequest += 1
        persist()
        return true
    }

    /// Opens another surah at a verse (its first by default).
    @discardableResult
    public func open(surah id: Int, ayah: Int = 1) -> Bool {
        guard let next = library.surah(id), (1...next.ayahCount).contains(ayah) else { return false }
        surah = next
        currentAyah = ayah
        scrollRequest += 1
        persist()
        return true
    }

    /// Saves the current verse as the reading position (leaving the screen or the app).
    public func persist() {
        store.save(QuranReadingPosition(currentRef, savedAt: now()))
    }
}
