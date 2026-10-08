import Combine
import Foundation
import IslamicCore

/// One open chapter on screen: the reader state, its same-day position, and the item's
/// recording. The reader owns navigation; the audio player only follows it.
///
/// - Next / previous / restart: stop the recording, move the reader, load the new item's
///   recording without playing it (no autoplay).
/// - A recording that ends stays finished: it does not move the reader or count a repetition.
/// - Counting a repetition does not touch the recording.
@MainActor
public final class HisnReaderController: ObservableObject {
    @Published public private(set) var reader: HisnReader
    /// Changes on every counted recitation; drives the optional haptic.
    @Published public private(set) var recitations = 0
    /// Nil when the app has no audio player (e.g. previews).
    public let audio: HisnAudioPlayer?
    private let store: HisnReadingPositionStore
    private var audioTask: Task<Void, Never>?
    private var audioItemId: String?

    public init(reader: HisnReader, store: HisnReadingPositionStore, audio: HisnAudioPlayer? = nil) {
        self.reader = reader
        self.store = store
        self.audio = audio
        save()
        syncAudio()
    }

    public func recite() {
        reader.recite()
        recitations += 1
        save()
        syncAudio()
    }

    public func next() {
        reader.next()
        save()
        syncAudio()
    }

    public func previous() {
        reader.previous()
        save()
        syncAudio()
    }

    public func restart() {
        reader.restart()
        save()
        syncAudio()
    }

    /// Stops the recording when the screen goes away.
    public func close() {
        audio?.stop()
    }

    /// Waits for the latest recording lookup (tests).
    public func audioSettled() async {
        await audioTask?.value
    }

    /// When the item on screen changed (or the chapter completed), stop and load the new
    /// item's recording, not playing.
    private func syncAudio() {
        guard let audio else { return }
        let itemId = reader.isCompleted ? nil : reader.currentItem.id
        guard itemId != audioItemId else { return }
        audioItemId = itemId
        audio.stop()
        audioTask = Task { await audio.load(itemId: itemId) }
    }

    private func save() {
        HisnResume.record(reader, in: store)
    }
}
