import Combine
import Foundation
import HisnReading
import IslamicCore
import PiPCore

/// Hisn Al-Muslim in PiP: the chapter, the item's text, and its repetition («التكرار 2 من 3»).
/// Previous / next are the reader's own (they stop the recording and load the next item's,
/// without playing it). PiP never counts a repetition, and opening PiP changes nothing; the
/// counter moves only from the reader's count button. Next stops at the last item: PiP never
/// completes the chapter.
@MainActor
public final class HisnPiPProvider: PiPContentProvider {
    public let controller: HisnReaderController
    private let audio: HisnPiPPlayback?

    public init(controller: HisnReaderController) {
        self.controller = controller
        audio = controller.audio.map(HisnPiPPlayback.init)
    }

    public var contentType: PiPContentType { .hisn }

    public var current: PiPContent? {
        let reader = controller.reader
        guard !reader.isCompleted else { return nil }
        return PiPContent(contentType: .hisn, contentID: reader.currentItem.id, containerID: reader.chapter.id,
                          title: reader.chapter.titleArabic, subtitle: "الذكر \(reader.itemNumber)",
                          text: reader.currentItem.arabicText, index: reader.itemIndex, total: reader.itemCount,
                          detail: Self.detail(reader.repetition))
    }

    /// «التكرار n من m» while the item is said more than once: n is the recitation in progress.
    static func detail(_ repetition: HisnReader.Repetition) -> String? {
        guard case .counted(let completed, let total) = repetition else { return nil }
        return "التكرار \(min(completed + 1, total)) من \(total)"
    }

    public func goToPrevious() {
        guard !controller.reader.isFirstItem else { return }
        controller.previous()
    }

    public func goToNext() {
        guard !controller.reader.isLastItem, !controller.reader.isCompleted else { return }
        controller.next()
    }

    public var playback: PiPPlaybackController? { audio }

    public var changes: AnyPublisher<Void, Never> {
        let reader = controller.objectWillChange.map { _ in () }.eraseToAnyPublisher()
        guard let player = controller.audio else { return reader }
        return reader.merge(with: player.objectWillChange.map { _ in () }).eraseToAnyPublisher()
    }

    public func persist() {
        controller.persist()
    }
}

/// The Hisn audio player as PiP playback. Only a loaded production recording counts.
@MainActor
final class HisnPiPPlayback: PiPPlaybackController {
    let player: HisnAudioPlayer

    init(_ player: HisnAudioPlayer) {
        self.player = player
    }

    var isAvailable: Bool { player.availability == .available }
    var isPlaying: Bool { player.state.isPlaying }
    var currentTime: TimeInterval { player.currentTime }
    var duration: TimeInterval? { player.duration }

    func play() {
        if player.state == .paused { player.resume() } else { player.play() }
    }

    func pause() { player.pause() }
    func seek(to time: TimeInterval) { player.seek(to: time) }
}
