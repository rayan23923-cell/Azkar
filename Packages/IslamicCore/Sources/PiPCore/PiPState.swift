import Foundation

/// Why PiP is not showing.
public enum PiPError: Equatable, Sendable {
    /// The device does not support PiP.
    case notSupported
    /// PiP is turned off (the setting, or a build without the PiP background mode).
    case disabled
    /// The section has nothing to show (for example a Hisn chapter already completed).
    case noContent
    /// The system refused to start PiP.
    case failedToStart
}

/// The one PiP state of the app. Only `PiPEngine` holds it; every screen reads it from there.
///
/// - `active`: the window is shown and its content is playing (a recording, or the pages of a
///   long text turning by themselves).
/// - `paused`: the window is shown and nothing moves by itself.
public enum PiPState: Equatable, Sendable {
    case inactive
    case starting
    case active
    case paused
    case stopping
    case error(PiPError)

    public enum Event: Equatable, Sendable {
        /// The user asked for PiP and the engine handed it to the system.
        case startRequested
        case willStart
        case didStart(playing: Bool)
        case failedToStart
        case playingChanged(Bool)
        case willStop
        case didStop
        /// The engine refused a start before asking the system.
        case rejected(PiPError)
    }

    /// The window is on screen.
    public var isShowing: Bool { self == .active || self == .paused }

    /// A PiP session exists (starting, shown or stopping).
    public var isRunning: Bool {
        switch self {
        case .starting, .active, .paused, .stopping: return true
        case .inactive, .error: return false
        }
    }

    public var error: PiPError? {
        if case .error(let error) = self { return error }
        return nil
    }

    /// The next state; events that do not apply leave the state unchanged.
    public func applying(_ event: Event) -> PiPState {
        switch event {
        case .startRequested:
            return isRunning ? self : .starting
        case .willStart:
            return isShowing || self == .stopping ? self : .starting
        case .didStart(let playing):
            return playing ? .active : .paused
        case .failedToStart:
            return .error(.failedToStart)
        case .playingChanged(let playing):
            guard isShowing else { return self }
            return playing ? .active : .paused
        case .willStop:
            return isRunning ? .stopping : self
        case .didStop:
            return .inactive
        case .rejected(let error):
            return isRunning ? self : .error(error)
        }
    }
}
