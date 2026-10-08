import Combine
import Foundation
import IslamicCore

/// The low-level player for one local file. The app uses an AVFoundation implementation
/// (`HisnAudioPlayback`); tests use a fake. Nothing above this protocol sees AVFoundation.
@MainActor
public protocol HisnAudioEngine: AnyObject {
    /// Seconds from the start of the loaded file.
    var currentTime: TimeInterval { get }
    /// Seconds; 0 when nothing is loaded.
    var duration: TimeInterval { get }
    /// Called when the file plays to its end.
    var onFinish: (() -> Void)? { get set }
    /// Called when decoding fails during playback.
    var onFailure: (() -> Void)? { get set }

    func load(url: URL) throws
    /// Starts or continues from the current time. False when the system refused.
    func play() -> Bool
    func pause()
    /// Stops and rewinds to the start.
    func stop()
    func seek(to time: TimeInterval)
    func unload()
}

/// The one owner of the app's audio session (category, activation, system notifications).
@MainActor
public protocol HisnAudioSessionControlling: AnyObject {
    /// Called before playback starts; never at launch.
    func activateForPlayback() throws
    var onEvent: ((HisnAudioSessionEvent) -> Void)? { get set }
}

/// Plays the recording of the item the reader shows. It reports state; it never moves the
/// reader, never counts a repetition, and never starts by itself.
@MainActor
public final class HisnAudioPlayer: ObservableObject {
    public enum Availability: Equatable, Sendable {
        /// Not looked up yet, or a lookup is running.
        case unknown
        case available
        /// The item has no recording: a normal state, no control is shown.
        case unavailable
    }

    @Published public private(set) var state: HisnAudioPlaybackState = .idle
    @Published public private(set) var availability: Availability = .unknown
    /// The item whose recording is loaded or being loaded. Not the reader's position: the
    /// reader owns navigation and tells the player what to load.
    @Published public private(set) var currentAudioItemId: String?
    @Published public private(set) var currentAsset: HisnAudioAsset?
    /// Seconds; nil until a file is loaded.
    @Published public private(set) var duration: TimeInterval?
    /// True after an interruption or a lost output paused playback.
    @Published public private(set) var pausedBySystem = false

    /// Read on demand (the screen samples it); not published, so playing does not flood updates.
    public var currentTime: TimeInterval { state == .idle || state == .loading ? 0 : engine.currentTime }

    private let repository: HisnAudioRepository
    private let engine: HisnAudioEngine
    private let session: HisnAudioSessionControlling
    private var loadToken = 0

    public init(repository: HisnAudioRepository, engine: HisnAudioEngine, session: HisnAudioSessionControlling) {
        self.repository = repository
        self.engine = engine
        self.session = session
        engine.onFinish = { [weak self] in self?.apply(.finish) }
        engine.onFailure = { [weak self] in self?.fail(.couldNotPlay) }
        session.onEvent = { [weak self] event in self?.handle(event) }
    }

    /// Looks up and prepares the item's recording without playing it. Nil clears the player.
    /// A newer call wins over one still running.
    public func load(itemId: String?) async {
        loadToken += 1
        let token = loadToken
        engine.unload()
        currentAsset = nil
        duration = nil
        pausedBySystem = false
        currentAudioItemId = itemId
        guard let itemId else {
            availability = .unknown
            apply(.unload)
            return
        }
        availability = .unknown
        apply(.load)
        var asset: HisnAudioAsset?
        var url: URL?
        do {
            asset = try await repository.audio(for: itemId)
            if let found = asset { url = try await repository.resourceURL(for: found) }
        } catch {
            guard token == loadToken else { return }
            availability = .unavailable
            fail(.unavailable)
            return
        }
        guard token == loadToken else { return }
        guard let asset, let url else {
            availability = .unavailable
            apply(.unload)
            return
        }
        do {
            try engine.load(url: url)
        } catch {
            availability = .unavailable
            fail(.couldNotLoad)
            return
        }
        currentAsset = asset
        duration = engine.duration > 0 ? engine.duration : asset.durationMilliseconds.map { Double($0) / 1000 }
        availability = .available
        apply(.loaded)
    }

    public func play() {
        guard state.applying(.play) != nil else { return }
        start(.play)
    }

    public func pause() {
        guard state.applying(.pause) != nil else { return }
        engine.pause()
        apply(.pause)
    }

    public func resume() {
        guard state.applying(.resume) != nil else { return }
        start(.resume)
    }

    /// Play when stopped or paused, pause when playing.
    public func togglePlayback() {
        switch state {
        case .playing: pause()
        case .paused: resume()
        default: play()
        }
    }

    public func stop() {
        guard state.applying(.stop) != nil else { return }
        engine.stop()
        pausedBySystem = false
        apply(.stop)
    }

    public func seek(to time: TimeInterval) {
        guard state.applying(.seek) != nil else { return }
        let upper = duration ?? engine.duration
        engine.seek(to: min(max(0, time), max(0, upper)))
        apply(.seek)
    }

    public func handle(_ event: HisnAudioSessionEvent) {
        switch event {
        case .interruptionBegan, .outputDeviceUnavailable:
            guard state == .playing else { return }
            engine.pause()
            pausedBySystem = true
            apply(.pause)
        case .interruptionEnded:
            // Conservative: stay paused; the user resumes.
            break
        case .routeChanged:
            break
        case .mediaServicesReset:
            guard currentAsset != nil else { return }
            engine.unload()
            fail(.couldNotPlay)
        }
    }

    private func start(_ event: HisnAudioPlaybackState.Event) {
        if state == .finished { engine.seek(to: 0) }
        do {
            try session.activateForPlayback()
        } catch {
            fail(.couldNotPlay)
            return
        }
        guard engine.play() else {
            fail(.couldNotPlay)
            return
        }
        pausedBySystem = false
        apply(event)
    }

    private func fail(_ failure: HisnAudioFailure) {
        apply(.fail(failure))
    }

    private func apply(_ event: HisnAudioPlaybackState.Event) {
        if let next = state.applying(event) { state = next }
    }
}
