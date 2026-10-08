import Combine
import Foundation
import IslamicCore
import ContentKit

/// One open chapter on screen: the reader state (the session), its persistent cursor, and the item's
/// recording. The reader owns navigation; the audio player only follows it.
///
/// - Next / previous / restart: stop the recording, move the reader, load the new item's
///   recording without playing it (no autoplay).
/// - A recording that ends stays finished: it does not move the reader or count a repetition.
/// - Counting a repetition does not touch the recording.
/// - The cursor is saved on each reading transition (open, count, next, previous, restart)
///   and when the app leaves the foreground; never per frame or per audio tick.
@MainActor
public final class HisnReaderController: ObservableObject {
    @Published public private(set) var reader: HisnReader
    /// Changes on every counted recitation; drives the optional haptic.
    @Published public private(set) var recitations = 0
    /// The 1-based number of the item whose last required recitation just moved the reader to
    /// the next item, so the screen can say so; cleared by any other step.
    @Published public private(set) var finishedItemNumber: Int?
    /// Nil when the app has no audio player (e.g. previews).
    public let audio: HisnAudioPlayer?
    private let store: HisnReadingPositionStore
    private let haptics: HisnHaptics?
    private let dailyProgress: DailyProgressStore?
    private let now: () -> Date
    private var audioTask: Task<Void, Never>?
    private var audioItemId: String?

    /// - Parameters:
    ///   - dailyProgress: where finishing the chapter is recorded for today (Phase 3G).
    ///   - now: the clock used for that day (tests pass a fixed one).
    public init(reader: HisnReader, store: HisnReadingPositionStore, audio: HisnAudioPlayer? = nil,
                haptics: HisnHaptics? = nil, dailyProgress: DailyProgressStore? = nil,
                now: @escaping () -> Date = Date.init) {
        self.reader = reader
        self.store = store
        self.audio = audio
        self.haptics = haptics
        self.dailyProgress = dailyProgress
        self.now = now
        save()
        syncAudio()
    }

    public func recite() {
        let number = reader.itemNumber
        let step = reader.recite()
        finishedItemNumber = step == .movedToNext ? number : nil
        // Feedback marks completion only, not every recitation.
        switch step {
        case .movedToNext: haptics?.play(.itemCompleted)
        case .completed:
            haptics?.play(.chapterCompleted)
            recordCompletion()
        case .counted: break
        }
        recitations += 1
        save()
        syncAudio()
    }

    public func next() {
        finishedItemNumber = nil
        let wasCompleted = reader.isCompleted
        reader.next()
        if !wasCompleted && reader.isCompleted {
            haptics?.play(.chapterCompleted)
            recordCompletion()
        }
        save()
        syncAudio()
    }

    public func previous() {
        finishedItemNumber = nil
        reader.previous()
        save()
        syncAudio()
    }

    public func restart() {
        finishedItemNumber = nil
        reader.restart()
        save()
        syncAudio()
    }

    /// Stops the recording and saves the cursor when the screen goes away.
    public func close() {
        save()
        audio?.stop()
    }

    /// Saves the cursor now (the app is leaving the foreground). Audio and PiP state are not
    /// part of it.
    public func persist() {
        save()
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

    /// Finishing the chapter (by counting or by «إنهاء الباب») marks it done for today.
    private func recordCompletion() {
        dailyProgress?.markCompleted(.hisnSection(reader.chapter.id), on: DayKey(date: now()))
    }

    private func save() {
        HisnResume.record(reader, in: store)
    }
}
