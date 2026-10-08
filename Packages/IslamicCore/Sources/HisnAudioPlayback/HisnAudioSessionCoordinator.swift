import AVFoundation
import Foundation
import HisnReading

/// The single owner of the audio session for Hisn playback. Views, view models and the player
/// never touch `AVAudioSession`; they go through this object.
///
/// - Activates only when playback starts (never at launch).
/// - Uses `.playback` (plays with the silent switch on and in the background; the app already
///   declares the `audio` background mode). If the session is already in `.playback` (for
///   example set by the PiP test engine), its mode is left as it is.
/// - Never deactivates the session in Phase 3B, so it cannot cut off other in-app audio.
/// - Turns interruption, route-change and media-reset notifications into `HisnAudioSessionEvent`.
@MainActor
public final class HisnAudioSessionCoordinator: HisnAudioSessionControlling {
    public static let shared = HisnAudioSessionCoordinator()

    public var onEvent: ((HisnAudioSessionEvent) -> Void)?
    private var observers: [NSObjectProtocol] = []

    private init() {
        #if os(iOS)
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session,
                                            queue: .main) { note in
            let event = Self.interruptionEvent(note.userInfo)
            MainActor.assumeIsolated { if let event { HisnAudioSessionCoordinator.shared.onEvent?(event) } }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session,
                                            queue: .main) { note in
            let event = Self.routeEvent(note.userInfo)
            MainActor.assumeIsolated { HisnAudioSessionCoordinator.shared.onEvent?(event) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session,
                                            queue: .main) { _ in
            MainActor.assumeIsolated { HisnAudioSessionCoordinator.shared.onEvent?(.mediaServicesReset) }
        })
        #endif
    }

    public func activateForPlayback() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
        }
        try session.setActive(true)
        #endif
    }

    #if os(iOS)
    nonisolated static func interruptionEvent(_ info: [AnyHashable: Any]?) -> HisnAudioSessionEvent? {
        guard let raw = info?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return nil }
        switch type {
        case .began:
            return .interruptionBegan
        case .ended:
            let options = (info?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init)
            return .interruptionEnded(shouldResume: options?.contains(.shouldResume) ?? false)
        @unknown default:
            return nil
        }
    }

    nonisolated static func routeEvent(_ info: [AnyHashable: Any]?) -> HisnAudioSessionEvent {
        guard let raw = info?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return .routeChanged }
        return reason == .oldDeviceUnavailable ? .outputDeviceUnavailable : .routeChanged
    }
    #endif
}
