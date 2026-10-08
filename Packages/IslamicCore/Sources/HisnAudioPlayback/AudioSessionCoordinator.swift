import AVFoundation
import Foundation
import HisnReading

/// The single owner of the app's audio session. The Hisn audio player and the PiP test engine
/// both go through it; views, view models, players and PiP code never call
/// `AVAudioSession.setCategory` / `setActive` themselves.
///
/// Policy (one, for the whole app):
/// - category `.playback`, mode `.moviePlayback`, no options: the configuration proven on a
///   device with the sample-buffer PiP path (plays with the silent switch on, in the
///   background, and lets AVKit start PiP);
/// - the category is set only when it differs, so repeated calls do not reconfigure the session;
/// - activated when playback or PiP preparation starts, never at launch;
/// - never deactivated (deactivating could cut off PiP or the other in-app audio).
///
/// It also turns interruption, route-change and media-reset notifications into
/// `HisnAudioSessionEvent`s for the Hisn player.
@MainActor
public final class AudioSessionCoordinator: HisnAudioSessionControlling {
    public static let shared = AudioSessionCoordinator()

    public var onEvent: ((HisnAudioSessionEvent) -> Void)?
    /// How many times the category was actually set (for the test screen's log).
    public private(set) var configurations = 0
    private var observers: [NSObjectProtocol] = []

    private init() {
        #if os(iOS)
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session,
                                            queue: .main) { note in
            let event = Self.interruptionEvent(note.userInfo)
            MainActor.assumeIsolated { if let event { AudioSessionCoordinator.shared.onEvent?(event) } }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session,
                                            queue: .main) { note in
            let event = Self.routeEvent(note.userInfo)
            MainActor.assumeIsolated { AudioSessionCoordinator.shared.onEvent?(event) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session,
                                            queue: .main) { _ in
            MainActor.assumeIsolated { AudioSessionCoordinator.shared.onEvent?(.mediaServicesReset) }
        })
        #endif
    }

    public func activateForPlayback() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback || session.mode != .moviePlayback || !session.categoryOptions.isEmpty {
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            configurations += 1
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
