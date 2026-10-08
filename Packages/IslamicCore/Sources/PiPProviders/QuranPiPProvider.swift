import Combine
import Foundation
import IslamicCore
import PiPCore
import QuranReading

/// Quran in PiP: the surah name, the verse number and the verse in the Quran font. Previous /
/// next move one verse inside the open surah (never into another surah) through the reader,
/// which scrolls to it and saves it as the reading position. No Quran recitation ships, so
/// there is no playback.
///
/// The verse shown is PiP's own cursor, taken from the reader's verse when PiP starts. It
/// follows the reader's explicit moves (go to verse, another surah) but not plain scrolling, so
/// a scroll that cannot put the last verses at the top does not pull PiP back.
@MainActor
public final class QuranPiPProvider: PiPContentProvider {
    public let controller: QuranReaderController
    private var surahId: Int
    private var ayah: Int
    private var lastScrollRequest: Int

    public init(controller: QuranReaderController) {
        self.controller = controller
        surahId = controller.surah.id
        ayah = controller.currentAyah
        lastScrollRequest = controller.scrollRequest
    }

    public var contentType: PiPContentType { .quran }

    public var current: PiPContent? {
        syncWithReader()
        guard let surah = controller.library.surah(surahId),
              let verse = controller.library.verse(QuranVerseRef(surah: surahId, ayah: ayah)) else { return nil }
        let ref = QuranVerseRef(surah: surahId, ayah: ayah)
        return PiPContent(contentType: .quran, contentID: ref.contentRef.string, containerID: "quran:\(surahId)",
                          title: "سورة \(surah.nameArabic)", subtitle: "الآية \(ayah)", text: verse.arabicText,
                          textStyle: .quran, index: ayah - 1, total: surah.ayahCount)
    }

    public func goToPrevious() { move(to: ayah - 1) }
    public func goToNext() { move(to: ayah + 1) }

    public var playback: PiPPlaybackController? { nil }

    public var changes: AnyPublisher<Void, Never> {
        controller.objectWillChange.map { _ in () }.eraseToAnyPublisher()
    }

    public func persist() {
        controller.persist()
    }

    /// Takes the reader's verse when the reader moved on purpose (a jump or another surah).
    private func syncWithReader() {
        guard controller.scrollRequest != lastScrollRequest || controller.surah.id != surahId else { return }
        lastScrollRequest = controller.scrollRequest
        surahId = controller.surah.id
        ayah = controller.currentAyah
    }

    private func move(to newAyah: Int) {
        syncWithReader()
        guard controller.surah.id == surahId, controller.go(to: newAyah) else { return }
        ayah = newAyah
        lastScrollRequest = controller.scrollRequest
    }
}
