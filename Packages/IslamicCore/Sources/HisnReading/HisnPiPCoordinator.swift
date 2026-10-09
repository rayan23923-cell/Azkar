import Combine
import Foundation
import IslamicCore

/// What the Hisn PiP window shows: one frame's worth of state, read from the reader and the
/// audio player. Nothing here is owned by PiP.
public struct HisnPiPContent: Equatable, Sendable {
    public let chapterTitle: String
    /// The current dhikr's bundled text, unchanged.
    public let itemText: String
    public let playback: HisnAudioPlaybackState
    /// Seconds, from the audio player (the authoritative position).
    public let currentTime: TimeInterval
    public let duration: TimeInterval?

    public init(chapterTitle: String, itemText: String, playback: HisnAudioPlaybackState,
                currentTime: TimeInterval, duration: TimeInterval?) {
        self.chapterTitle = chapterTitle
        self.itemText = itemText
        self.playback = playback
        self.currentTime = currentTime
        self.duration = duration
    }

    /// 0...1, or nil without a known duration.
    public var progress: Double? {
        guard let duration, duration > 0 else { return nil }
        return min(max(currentTime / duration, 0), 1)
    }
}

/// Events from the platform PiP surface (the system PiP controller and its delegate).
public enum HisnPiPSurfaceEvent: Equatable, Sendable {
    case possibleChanged(Bool)
    case willStart
    case didStart
    case failedToStart
    case willStop
    case didStop
}

/// The platform side of Hisn PiP: one sample-buffer display layer, its host-clock timebase and
/// one system PiP controller. The app implements it (`SampleBufferPiPSurface`); tests use a fake.
/// This target stays free of the platform PiP frameworks.
@MainActor
public protocol HisnPiPSurface: AnyObject {
    var isSupported: Bool { get }
    var isPossible: Bool { get }
    var onEvent: ((HisnPiPSurfaceEvent) -> Void)? { get set }
    /// Supplies the content for each frame the surface draws.
    var contentProvider: (() -> HisnPiPContent?)? { get set }
    func start()
    func stop()
    /// Draws a frame now and tells the system the playback state changed.
    func refresh()
    /// Runs the periodic frame heartbeat (only while the inline preview is visible or PiP is active).
    func setHeartbeat(_ running: Bool)
}

/// What the system PiP playback controls call: play/pause and skip. The platform surface talks
/// to this protocol, so Hisn and any other content can drive the same proven surface.
@MainActor
public protocol PiPPlaybackControlling: AnyObject {
    func setPlaying(_ playing: Bool)
    func skip(by seconds: TimeInterval)
}

/// Superseded in the app by the unified PiP engine (PiPCore) with `HisnPiPProvider`; kept with its
/// tests as the Phase 3C reference until it is removed.
///
/// Owns the Hisn PiP lifecycle. It reads the reader (current item) and the audio player
/// (state, time, duration); it never owns either. PiP system controls are mapped here:
/// play/pause → the player, skip ±interval → a seek within the current recording (never the
/// next dhikr). A recording ending in PiP does not count a repetition.
@MainActor
public final class HisnPiPCoordinator: ObservableObject, PiPPlaybackControlling {
    public enum Status: Equatable, Sendable {
        case inactive
        case starting
        case active
        case stopping
    }

    public enum Failure: Equatable, Sendable {
        /// The device does not support PiP.
        case notSupported
        /// The item has no recording, or the surface is not ready yet.
        case notPossible
        /// The system refused to start PiP. Audio is unaffected.
        case failedToStart
    }

    @Published public private(set) var status: Status = .inactive
    @Published public private(set) var failure: Failure?
    @Published public private(set) var isPossible = false

    public let surface: HisnPiPSurface
    private let controller: HisnReaderController
    private var subscriptions: Set<AnyCancellable> = []
    private var inlineVisible = false

    public init(controller: HisnReaderController, surface: HisnPiPSurface) {
        self.controller = controller
        self.surface = surface
        surface.contentProvider = { [weak self] in self?.content }
        surface.onEvent = { [weak self] event in self?.handle(event) }
        isPossible = surface.isPossible
        controller.$reader
            .map { _ in () }
            .merge(with: controller.audio.map { audio in
                audio.$state.map { _ in () }
                    .merge(with: audio.$availability.map { _ in () }, audio.$duration.map { _ in () })
                    .eraseToAnyPublisher()
            } ?? Empty<Void, Never>().eraseToAnyPublisher())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.stateChanged() }
            }
            .store(in: &subscriptions)
    }

    private var audio: HisnAudioPlayer? { controller.audio }

    /// Hisn PiP exists only for an item whose recording is loaded. Without production audio
    /// this is always false, and no PiP control is shown.
    public var isAvailable: Bool {
        surface.isSupported && audio?.availability == .available && !controller.reader.isCompleted
    }

    /// The content of the next frame; nil when there is nothing to show.
    public var content: HisnPiPContent? {
        guard let audio, audio.availability == .available, !controller.reader.isCompleted else { return nil }
        return HisnPiPContent(chapterTitle: controller.reader.chapter.titleArabic,
                              itemText: controller.reader.currentItem.arabicText,
                              playback: audio.state, currentTime: audio.currentTime, duration: audio.duration)
    }

    // MARK: Manual start / stop

    /// Starts PiP on the user's request. Never called automatically.
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

    /// The reader shows (or hides) the inline preview the PiP window grows from.
    public func setInlineVisible(_ visible: Bool) {
        inlineVisible = visible
        updateHeartbeat()
        if visible { surface.refresh() }
    }

    /// The reader screen is going away: leave PiP and stop drawing.
    public func close() {
        stop()
        inlineVisible = false
        surface.setHeartbeat(false)
    }

    // MARK: PiP playback delegate semantics

    /// System play / pause button.
    public func setPlaying(_ playing: Bool) {
        guard let audio else { return }
        if playing {
            if audio.state == .paused { audio.resume() } else { audio.play() }
        } else {
            audio.pause()
        }
        surface.refresh()
    }

    public var isPlaybackPaused: Bool { !(audio?.state.isPlaying ?? false) }

    /// The seekable range shown by the system, nil when there is no recording.
    public var playbackDuration: TimeInterval? {
        guard isAvailable, let duration = audio?.duration, duration > 0 else { return nil }
        return duration
    }

    /// System skip back / forward: a seek inside the current recording, clamped to it.
    public func skip(by seconds: TimeInterval) {
        guard let audio, audio.availability == .available else { return }
        audio.seek(to: audio.currentTime + seconds)
        surface.refresh()
    }

    // MARK: Events

    private func handle(_ event: HisnPiPSurfaceEvent) {
        switch event {
        case .possibleChanged(let possible):
            isPossible = possible
        case .willStart:
            status = .starting
        case .didStart:
            status = .active
            failure = nil
        case .failedToStart:
            status = .inactive
            failure = .failedToStart
        case .willStop:
            status = .stopping
        case .didStop:
            status = .inactive
        }
        updateHeartbeat()
    }

    private func stateChanged() {
        if !isAvailable && (status == .active || status == .starting) {
            // No recording any more (another item, chapter complete): PiP does not pretend.
            surface.stop()
        }
        surface.refresh()
    }

    private func updateHeartbeat() {
        surface.setHeartbeat(inlineVisible || status == .active || status == .starting)
    }
}

/// Splits a long text into pages for the PiP frame without changing it: every page is a
/// contiguous slice of the original, breaking only after whitespace, and the pages joined
/// give back the text exactly.
public enum HisnPiPPaginator {
    /// - Parameter fits: whether a slice fits one frame at the chosen font.
    public static func pages(_ text: String, fits: (Substring) -> Bool) -> [Range<String.Index>] {
        guard !text.isEmpty else { return [] }
        // Break opportunities: just after each whitespace run.
        var breaks: [String.Index] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            if text[index].isWhitespace && (next == text.endIndex || !text[next].isWhitespace) {
                breaks.append(next)
            }
            index = next
        }
        if breaks.last != text.endIndex { breaks.append(text.endIndex) }

        var pages: [Range<String.Index>] = []
        var start = text.startIndex
        var cursor = 0
        while start < text.endIndex {
            var end: String.Index? = nil
            while cursor < breaks.count {
                let candidate = breaks[cursor]
                if candidate <= start { cursor += 1; continue }
                if fits(text[start..<candidate]) {
                    end = candidate
                    cursor += 1
                } else {
                    break
                }
            }
            // A single word longer than a frame still gets its own page (shrinking is the
            // renderer's job); text is never dropped.
            let pageEnd = end ?? breaks.first { $0 > start } ?? text.endIndex
            pages.append(start..<pageEnd)
            start = pageEnd
        }
        return pages
    }
}
