import Foundation

// Plain state types for V1. They carry no behaviour yet; the session engine
// (Phase 4) owns transitions. Content, audio, PiP and UI state stay separate.

public enum SessionState: String, Sendable, CaseIterable {
    case idle, preparing, ready, playing, paused, stopping, stopped, error
}

public enum PlaybackState: String, Sendable, CaseIterable {
    case stopped, playing, paused, buffering, completed, error
}

public enum PiPState: String, Sendable, CaseIterable {
    case unavailable, idle, starting, active, stopping, stopped, error
}

public enum AudioState: String, Sendable, CaseIterable {
    case unavailable, idle, playing, paused, stopped, interrupted, error
}
