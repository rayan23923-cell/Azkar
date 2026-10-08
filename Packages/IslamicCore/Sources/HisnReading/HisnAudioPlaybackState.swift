import Foundation

/// Playback state of the Hisn audio player. Changes only through `applying(_:)`.
public enum HisnAudioPlaybackState: Equatable, Sendable {
    /// No recording loaded (none requested, or the item has none).
    case idle
    case loading
    /// Loaded, at the start (or rewound by stop).
    case ready
    case playing
    case paused
    /// Reached the end by itself. Does not advance the reader or count a repetition.
    case finished
    case failed(HisnAudioFailure)

    public enum Event: Equatable, Sendable {
        case load
        case loaded
        case unload
        case play
        case pause
        case resume
        case stop
        case seek
        case finish
        case fail(HisnAudioFailure)
    }

    /// The state after `event`, or nil when the event is not allowed in this state. The player
    /// ignores a nil transition (no crash, no change).
    public func applying(_ event: Event) -> HisnAudioPlaybackState? {
        switch (self, event) {
        case (_, .fail(let failure)): return .failed(failure)
        case (_, .unload): return .idle
        case (_, .load): return .loading
        case (.loading, .loaded): return .ready
        case (.ready, .play), (.paused, .play), (.finished, .play): return .playing
        case (.playing, .pause): return .paused
        case (.paused, .resume): return .playing
        case (.ready, .stop), (.playing, .stop), (.paused, .stop), (.finished, .stop): return .ready
        case (.ready, .seek), (.playing, .seek), (.paused, .seek): return self
        case (.finished, .seek): return .paused
        case (.playing, .finish): return .finished
        default: return nil
        }
    }

    public var isPlaying: Bool { self == .playing }
}

/// Why playback failed. The reader screen turns these into Arabic messages; no file paths or
/// framework error codes reach the user.
public enum HisnAudioFailure: Equatable, Sendable {
    /// The pack or the file could not be read or failed validation.
    case unavailable
    /// The file was found but could not be decoded.
    case couldNotLoad
    /// The system refused to start playback (audio session or decoder).
    case couldNotPlay
}

/// Events from the audio session owner, already reduced to what the player needs.
public enum HisnAudioSessionEvent: Equatable, Sendable {
    case interruptionBegan
    /// `shouldResume` is the system's hint; the player stays paused either way (conservative).
    case interruptionEnded(shouldResume: Bool)
    /// The output the user was listening on went away (headphones unplugged, Bluetooth lost).
    case outputDeviceUnavailable
    /// Any other route change (a device connected, speaker override): no action.
    case routeChanged
    /// The media services restarted; loaded players are invalid.
    case mediaServicesReset
}
