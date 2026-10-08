import Combine
import Foundation
import IslamicCore
import ContentKit
import HisnReading

/// One entry of a listening queue: a content reference (the recording's item id in the
/// manifest) and what the screen and PiP show for it.
public struct AudioQueueItem: Hashable, Sendable {
    public let ref: ContentRef
    public let title: String
    /// The stored text, unchanged.
    public let text: String

    public init(ref: ContentRef, title: String, text: String) {
        self.ref = ref
        self.title = title
        self.text = text
    }
}

/// What can be restored after a relaunch: the queue's items, the position and the time.
public struct AudioQueueSnapshot: Codable, Equatable, Sendable {
    public let refs: [ContentRef]
    public let index: Int
    public let time: TimeInterval

    public init(refs: [ContentRef], index: Int, time: TimeInterval) {
        self.refs = refs
        self.index = index
        self.time = max(0, time)
    }
}

/// Plays a list of items one after another (verses of a surah, adhkar of a collection) on top
/// of the one audio player, so the session, interruption and route rules are the Hisn ones.
///
/// - next / previous move at once; the new item is loaded, and plays if the queue was playing.
/// - With `continuous` on, an item that ends starts the next; items without a recording are
///   skipped, and the queue stops at the end.
/// - Interruptions and a lost output pause (the player's rule); nothing resumes by itself.
@MainActor
public final class AudioQueueController: ObservableObject {
    @Published public private(set) var items: [AudioQueueItem] = []
    @Published public private(set) var index = 0
    /// True when the end of the queue was reached by playing.
    @Published public private(set) var reachedEnd = false
    public var continuous = true
    public let player: HisnAudioPlayer
    private var subscriptions: Set<AnyCancellable> = []
    /// Set while the queue moves itself, so a skipped item does not stop the move.
    private var advancing = false

    public init(player: HisnAudioPlayer) {
        self.player = player
        player.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                MainActor.assumeIsolated {
                    if state == .finished { Task { await self.itemFinished() } }
                }
            }
            .store(in: &subscriptions)
    }

    public var current: AudioQueueItem? { items.indices.contains(index) ? items[index] : nil }
    public var hasNext: Bool { index + 1 < items.count }
    public var hasPrevious: Bool { index > 0 }

    /// Replaces the queue and loads `start` (clamped). Does not play.
    public func load(_ items: [AudioQueueItem], start: Int = 0) async {
        self.items = items
        index = items.isEmpty ? 0 : min(max(0, start), items.count - 1)
        reachedEnd = false
        await player.load(itemId: current?.ref.string)
    }

    public func play() { player.togglePlayback() }

    public func next() async {
        guard hasNext else { return }
        await move(to: index + 1)
    }

    public func previous() async {
        // Like most players: back to the start of the item first, then to the previous one.
        if player.currentTime > 3 {
            player.seek(to: 0)
            return
        }
        guard hasPrevious else { return }
        await move(to: index - 1)
    }

    public func jump(to newIndex: Int) async {
        guard items.indices.contains(newIndex) else { return }
        await move(to: newIndex)
    }

    public func stop() {
        player.stop()
    }

    public var snapshot: AudioQueueSnapshot? {
        guard !items.isEmpty else { return nil }
        return AudioQueueSnapshot(refs: items.map(\.ref), index: index, time: player.currentTime)
    }

    /// Restores a saved queue against the current content: items that no longer exist are
    /// dropped by `resolve`; a saved position past the end is clamped. Never plays.
    public func restore(_ snapshot: AudioQueueSnapshot, resolve: (ContentRef) -> AudioQueueItem?) async {
        let currentRef = snapshot.refs.indices.contains(snapshot.index) ? snapshot.refs[snapshot.index] : nil
        let resolved = snapshot.refs.compactMap(resolve)
        let start = currentRef.flatMap { ref in resolved.firstIndex { $0.ref == ref } } ?? 0
        await load(resolved, start: start)
        if player.availability == .available, resolved.indices.contains(start), resolved[start].ref == currentRef {
            player.seek(to: snapshot.time)
        }
    }

    private func move(to newIndex: Int) async {
        let wasPlaying = player.state.isPlaying
        index = newIndex
        reachedEnd = false
        await player.load(itemId: current?.ref.string)
        if wasPlaying || advancing { player.play() }
    }

    private func itemFinished() async {
        guard continuous else { return }
        advancing = true
        defer { advancing = false }
        var candidate = index + 1
        while candidate < items.count {
            await move(to: candidate)
            if player.availability == .available { return }
            candidate += 1
        }
        reachedEnd = true
    }
}
