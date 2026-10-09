import Combine
import Foundation
import HisnReading
import IslamicCore
import PiPCore

/// Hisn Al-Muslim in PiP: the chapter, the item's text, and its repetition («التكرار 37 من 100»).
///
/// - Counting: skip forward records one recitation through the reader's own `recite()`, which
///   saves the count at once. Any stated count is counted, with no upper limit.
/// - Reaching the count: the reader moves to the next item (its established behaviour), but the
///   window first keeps the finished item, marked «اكتمل ✓», so nothing moves without being
///   seen. The next skip forward shows the next item. After the chapter's last item the window
///   keeps «اكتمل الباب»; it never opens another chapter.
/// - Previous / next are the reader's own (they stop the recording and load the item's,
///   without playing it). Next never counts and stops at the last item; opening PiP changes
///   nothing.
@MainActor
public final class HisnPiPProvider: PiPContentProvider {
    public let controller: HisnReaderController
    private let audio: HisnPiPPlayback?
    /// The item whose count PiP just completed, shown until the next skip; valid only while the
    /// reader is still where that recitation left it (a change on the screen dismisses it).
    private var finished: (content: PiPContent, readerKey: String)?

    public init(controller: HisnReaderController) {
        self.controller = controller
        audio = controller.audio.map(HisnPiPPlayback.init)
    }

    public var contentType: PiPContentType { .hisn }

    public var current: PiPContent? {
        if let finished, finished.readerKey == readerKey { return finished.content }
        let reader = controller.reader
        guard !reader.isCompleted else { return nil }
        let repetition = Self.repetition(reader.repetition)
        return PiPContent(contentType: .hisn, contentID: reader.currentItem.id, containerID: reader.chapter.id,
                          title: reader.chapter.titleArabic, subtitle: "الذكر \(reader.itemNumber)",
                          text: reader.currentItem.arabicText, index: reader.itemIndex, total: reader.itemCount,
                          detail: repetition.map(Self.detail), repetition: repetition)
    }

    /// The count PiP advances, from the reader's own counter: a stated count of any size (one
    /// included); nil when the book states none.
    static func repetition(_ repetition: HisnReader.Repetition) -> PiPRepetition? {
        switch repetition {
        case .counted(let completed, let total): return PiPRepetition(completed: completed, total: total)
        case .once: return PiPRepetition(completed: 0, total: 1)
        case .unstated: return nil
        }
    }

    /// «التكرار n من m»: n is the recitation in progress; «اكتمل ✓ m من m» once done.
    static func detail(_ repetition: PiPRepetition) -> String {
        if repetition.isComplete { return "اكتمل ✓ \(repetition.total) من \(repetition.total)" }
        return "التكرار \(repetition.current) من \(repetition.total)"
    }

    /// One recitation of the item shown.
    public func recordRepetition() {
        guard let shown = current, let repetition = shown.repetition, !repetition.isComplete else { return }
        controller.recite()
        // Still on the item: the counter moved. Moved on (or the chapter ended): keep the item.
        guard controller.reader.isCompleted || controller.reader.itemIndex != shown.index else { return }
        let done = PiPRepetition(completed: repetition.total, total: repetition.total)
        let chapterDone = controller.reader.isCompleted
        // After the chapter nothing is next, so skip forward has nothing left to do.
        finished = (PiPContent(contentType: .hisn, contentID: shown.contentID, containerID: shown.containerID,
                               title: shown.title, subtitle: shown.subtitle, text: shown.text,
                               textStyle: shown.textStyle, index: shown.index, total: shown.total,
                               detail: Self.detail(done) + (chapterDone ? "  ·  اكتمل الباب" : ""),
                               repetition: chapterDone ? nil : done),
                    readerKey)
    }

    public func goToPrevious() {
        if dismissFinished() {
            // The reader is already past the finished item: back to it (or, after the chapter,
            // to its last item).
            controller.previous()
            return
        }
        guard !controller.reader.isFirstItem else { return }
        controller.previous()
    }

    public func goToNext() {
        if finished?.readerKey == readerKey {
            // After the chapter there is nothing next: «اكتمل الباب» stays until the window closes.
            guard !controller.reader.isCompleted else { return }
            dismissFinished()
            return
        }
        guard !controller.reader.isLastItem, !controller.reader.isCompleted else { return }
        controller.next()
    }

    /// Drops the «اكتمل ✓» item; true when it was shown.
    @discardableResult
    private func dismissFinished() -> Bool {
        defer { finished = nil }
        return finished?.readerKey == readerKey
    }

    /// Where the reader stands: its item and count, or the end of the chapter.
    private var readerKey: String {
        let reader = controller.reader
        if reader.isCompleted { return "completed" }
        return "\(reader.itemIndex)#\(reader.currentItem.id)#\(reader.completedRepetitions)"
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
