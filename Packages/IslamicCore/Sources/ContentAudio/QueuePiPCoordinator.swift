import Combine
import Foundation
import HisnReading

/// PiP for a listening queue, on the same surface protocol as Hisn PiP. The queue is the
/// content provider (title and text of the playing item), the player is the playback
/// controller, and the surface is the renderer. System skip buttons seek inside the current
/// recording, as in Hisn. PiP is available only while a recording is loaded.
@MainActor
public final class QueuePiPCoordinator: ObservableObject, PiPPlaybackControlling {
    @Published public private(set) var status: HisnPiPCoordinator.Status = .inactive
    @Published public private(set) var failure: HisnPiPCoordinator.Failure?
    @Published public private(set) var isPossible = false

    public let surface: HisnPiPSurface
    private let queue: AudioQueueController
    private var subscriptions: Set<AnyCancellable> = []
    private var inlineVisible = false

    public init(queue: AudioQueueController, surface: HisnPiPSurface) {
        self.queue = queue
        self.surface = surface
        surface.contentProvider = { [weak self] in self?.content }
        surface.onEvent = { [weak self] event in self?.handle(event) }
        isPossible = surface.isPossible
        queue.$index.map { _ in () }
            .merge(with: queue.player.$state.map { _ in () }, queue.player.$availability.map { _ in () },
                   queue.player.$duration.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in MainActor.assumeIsolated { self?.stateChanged() } }
            .store(in: &subscriptions)
    }

    public var isAvailable: Bool {
        surface.isSupported && queue.player.availability == .available && queue.current != nil
    }

    public var content: HisnPiPContent? {
        guard queue.player.availability == .available, let item = queue.current else { return nil }
        return HisnPiPContent(chapterTitle: item.title, itemText: item.text, playback: queue.player.state,
                              currentTime: queue.player.currentTime, duration: queue.player.duration)
    }

    public func start() {
        failure = nil
        guard surface.isSupported else { failure = .notSupported; return }
        guard isAvailable, surface.isPossible, status == .inactive else { failure = .notPossible; return }
        surface.start()
    }

    public func stop() {
        guard status == .active || status == .starting else { return }
        surface.stop()
    }

    public func setInlineVisible(_ visible: Bool) {
        inlineVisible = visible
        updateHeartbeat()
        if visible { surface.refresh() }
    }

    public func close() {
        stop()
        inlineVisible = false
        surface.setHeartbeat(false)
    }

    public func setPlaying(_ playing: Bool) {
        let player = queue.player
        if playing {
            if player.state == .paused { player.resume() } else { player.play() }
        } else {
            player.pause()
        }
        surface.refresh()
    }

    public func skip(by seconds: TimeInterval) {
        guard queue.player.availability == .available else { return }
        queue.player.seek(to: queue.player.currentTime + seconds)
        surface.refresh()
    }

    private func handle(_ event: HisnPiPSurfaceEvent) {
        switch event {
        case .possibleChanged(let possible): isPossible = possible
        case .willStart: status = .starting
        case .didStart:
            status = .active
            failure = nil
        case .failedToStart:
            status = .inactive
            failure = .failedToStart
        case .willStop: status = .stopping
        case .didStop: status = .inactive
        }
        updateHeartbeat()
    }

    private func stateChanged() {
        // Between items the queue reloads; PiP stays while the next item has a recording.
        if !isAvailable && queue.player.state != .loading && (status == .active || status == .starting) {
            surface.stop()
        }
        surface.refresh()
    }

    private func updateHeartbeat() {
        surface.setHeartbeat(inlineVisible || status == .active || status == .starting)
    }
}
