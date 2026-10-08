import Combine
import Foundation

/// A section's adapter to PiP. It wraps the reader the screen already uses, so PiP and the
/// screen share one position, one counter and one saved progress; PiP never sees the domain's
/// own types.
@MainActor
public protocol PiPContentProvider: AnyObject {
    var contentType: PiPContentType { get }
    /// The item to show; nil when there is nothing to show (the chapter or collection is done).
    var current: PiPContent? { get }
    /// The previous / next item, as the reader's own buttons do. Never counts a repetition.
    /// The engine calls them only when `current` is not the first / last item.
    func goToPrevious()
    func goToNext()
    /// The item's recording; nil for a section without audio.
    var playback: PiPPlaybackController? { get }
    /// Fires when the item, its counter or the recording's state may have changed.
    var changes: AnyPublisher<Void, Never> { get }
    /// Saves the reader's position (PiP is closing).
    func persist()
}

/// A loaded recording, as PiP sees it. A recording that ends stays on its item: PiP never moves
/// to the next item because audio finished.
@MainActor
public protocol PiPPlaybackController: AnyObject {
    /// A production recording is loaded for the current item.
    var isAvailable: Bool { get }
    var isPlaying: Bool { get }
    /// Seconds.
    var currentTime: TimeInterval { get }
    var duration: TimeInterval? { get }
    /// Plays, or resumes after a pause.
    func play()
    func pause()
    func seek(to time: TimeInterval)
}

/// Events from the platform PiP controller (the system PiP window and its delegate).
public enum PiPControllerEvent: Equatable, Sendable {
    case possibleChanged(Bool)
    case willStart
    case didStart
    case failedToStart
    case willStop
    case didStop
    /// The user tapped "return to app" in the window.
    case restoreUserInterface
}

/// What the system PiP buttons call.
@MainActor
public protocol PiPCommandHandling: AnyObject {
    /// Play / pause button.
    func setPlaying(_ playing: Bool)
    /// Skip back / forward buttons: the sign gives the direction.
    func skip(by seconds: TimeInterval)
}

/// The platform side: one sample-buffer display layer, its timebase and one system PiP
/// controller. The app implements it on AVKit; tests use a fake. This target never imports AVKit.
@MainActor
public protocol PiPController: AnyObject {
    var isSupported: Bool { get }
    var isPossible: Bool { get }
    var onEvent: ((PiPControllerEvent) -> Void)? { get set }
    /// Supplies each frame the controller draws.
    var frameSource: (() -> PiPFrame?)? { get set }
    /// Where the system buttons go.
    var commands: PiPCommandHandling? { get set }
    func start()
    func stop()
    /// Draws a frame now and tells the system the playback state changed.
    func refresh()
    /// Runs the periodic frame heartbeat (while the inline preview is visible or PiP runs).
    func setHeartbeat(_ running: Bool)
}
