import AVFoundation
import AVKit
import CoreVideo
import HisnAudioPlayback
import PiPCore
import PiPRendering
import UIKit

/// The production PiP controller on the device-proven sample-buffer path (PHASE_3C_PIP_AUDIT.md):
/// an inline `AVSampleBufferDisplayLayer` with a host-clock `CMTimebase` as its control
/// timebase, `ContentSource(sampleBufferDisplayLayer:playbackDelegate:)`, one strongly
/// retained `AVPictureInPictureController`, and a 0.5 s frame heartbeat. Each frame is drawn
/// by `PiPFrameRenderer` (Core Text) into a `CVPixelBuffer` and wrapped by the same
/// `AzkarFrameRenderer.makeSampleBuffer`.
///
/// One per reader screen. `PiPEngine` owns every PiP decision; this class only adapts AVKit:
/// - the time range is finite, so the system shows its skip buttons (previous / next);
/// - the audio session is activated through the app's single owner when PiP starts, never
///   when a screen opens;
/// - automatic start from inline follows `PiPAvailability.allowsAutomaticStart` (off).
@MainActor
final class SampleBufferPiPController: NSObject, PiPController {
    let displayLayer = AVSampleBufferDisplayLayer()
    let isSupported = AVPictureInPictureController.isPictureInPictureSupported()
    private(set) var isPossible = false
    var onEvent: ((PiPControllerEvent) -> Void)?
    var frameSource: (() -> PiPFrame?)?
    weak var commands: PiPCommandHandling?

    private let allowsAutomaticStart: Bool
    private var pipController: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private var timebase: CMTimebase?
    private var heartbeat: Timer?
    /// A start asked for before the system reported PiP possible.
    private var pendingStart = false
    /// Values AVKit may ask for synchronously; updated on main with every frame.
    private let snapshot = PlaybackSnapshot()

    #if HISN_AUDIO_FIXTURE
    /// The device-test build marks every frame; production frames carry no marker.
    private let badge: String? = "نغمة اختبار"
    #else
    private let badge: String? = nil
    #endif

    init(allowsAutomaticStart: Bool = false) {
        self.allowsAutomaticStart = allowsAutomaticStart
        super.init()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
        var tb: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(),
                                        timebaseOut: &tb)
        if let tb {
            CMTimebaseSetTime(tb, time: .zero)
            CMTimebaseSetRate(tb, rate: 0)
            displayLayer.controlTimebase = tb
            timebase = tb
        }
    }

    /// Builds the system controller once, when the inline layer is first shown.
    func prepare() {
        guard isSupported, pipController == nil else { return }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer,
                                                                playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = allowsAutomaticStart
        controller.requiresLinearPlayback = false
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] c, _ in
            let possible = c.isPictureInPicturePossible
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.possibleChanged(possible) }
            }
        }
        pipController = controller
    }

    func start() {
        prepare()
        // PiP needs the playback session; the app's single owner applies the proven policy.
        try? AudioSessionCoordinator.shared.activateForPlayback()
        drawFrame()
        guard let pipController else {
            onEvent?(.failedToStart)
            return
        }
        if pipController.isPictureInPicturePossible {
            pipController.startPictureInPicture()
            return
        }
        // The layer was just shown: give the system a moment to report PiP possible.
        pendingStart = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.pendingStart else { return }
                self.pendingStart = false
                self.onEvent?(.failedToStart)
            }
        }
    }

    func stop() {
        if pendingStart {
            pendingStart = false
            onEvent?(.didStop)
            return
        }
        pipController?.stopPictureInPicture()
    }

    func setHeartbeat(_ running: Bool) {
        if running {
            guard heartbeat == nil else { return }
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.drawFrame() }
            }
            RunLoop.main.add(timer, forMode: .common)
            heartbeat = timer
        } else {
            heartbeat?.invalidate()
            heartbeat = nil
        }
    }

    func refresh() {
        drawFrame()
        pipController?.invalidatePlaybackState()
    }

    private func possibleChanged(_ possible: Bool) {
        isPossible = possible
        onEvent?(.possibleChanged(possible))
        if possible && pendingStart {
            pendingStart = false
            pipController?.startPictureInPicture()
        }
    }

    /// Draws the current frame. The timebase follows the frame: the recording's time with rate
    /// 1 while it plays, otherwise the place in the container with rate 0.
    private func drawFrame() {
        guard let frame = frameSource?() else { return }
        snapshot.update(paused: !frame.isPlaying, duration: frame.duration)
        let time = CMTime(seconds: frame.time, preferredTimescale: 600)
        if let timebase {
            CMTimebaseSetRate(timebase, rate: 0)
            CMTimebaseSetTime(timebase, time: time)
            CMTimebaseSetRate(timebase, rate: frame.rate)
        }
        guard let pixelBuffer = makePixelBuffer(frame),
              let sample = AzkarFrameRenderer.makeSampleBuffer(pixelBuffer: pixelBuffer, presentationTime: time) else {
            return
        }
        let output = displayLayer.sampleBufferRenderer
        // After returning to the foreground the renderer can report "Operation Interrupted"
        // (seen on the device run); flushing lets it continue.
        if output.status == .failed { output.flush() }
        output.enqueue(sample)
    }

    private func makePixelBuffer(_ frame: PiPFrame) -> CVPixelBuffer? {
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
        ]
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, PiPFrameRenderer.width, PiPFrameRenderer.height,
                                  kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer) == kCVReturnSuccess,
              let pb = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: PiPFrameRenderer.width,
                                      height: PiPFrameRenderer.height, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                          | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        PiPFrameRenderer.draw(frame, appearance: appearance, badge: badge, in: context)
        return pb
    }

    /// The app's appearance setting, or the system's.
    private var appearance: PiPFrameRenderer.Appearance {
        switch AppAppearance(rawValue: UserDefaults.standard.string(forKey: AppAppearance.key) ?? "") ?? .system {
        case .light: return .light
        case .dark: return .dark
        case .system:
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            return scene?.traitCollection.userInterfaceStyle == .light ? .light : .dark
        }
    }
}

/// Thread-safe copy of what AVKit asks for synchronously.
private final class PlaybackSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var paused = true
    private var duration: Double = 0

    func update(paused: Bool, duration: Double) {
        lock.lock(); defer { lock.unlock() }
        self.paused = paused
        self.duration = duration
    }

    func read() -> (paused: Bool, duration: Double) {
        lock.lock(); defer { lock.unlock() }
        return (paused, duration)
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension SampleBufferPiPController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        onMain { $0.onEvent?(.willStart) }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        onMain { $0.onEvent?(.didStart) }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: Error) {
        onMain { $0.onEvent?(.failedToStart) }
    }

    nonisolated func pictureInPictureControllerWillStopPictureInPicture(_ controller: AVPictureInPictureController) {
        onMain { $0.onEvent?(.willStop) }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        onMain { $0.onEvent?(.didStop) }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        // The app opens the section shown in the window; its reader is still in its tab.
        onMain { $0.onEvent?(.restoreUserInterface) }
        completionHandler(true)
    }

    nonisolated private func onMain(_ work: @escaping @MainActor (SampleBufferPiPController) -> Void) {
        let run: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            work(self)
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated(run)
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated(run) }
        }
    }
}

// MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

extension SampleBufferPiPController: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        onMain { $0.commands?.setPlaying(playing) }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        // Finite, so the system shows the skip buttons that PiP uses for previous / next.
        let duration = snapshot.read().duration
        return CMTimeRange(start: .zero, duration: CMTime(seconds: max(duration, 0.1), preferredTimescale: 600))
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        snapshot.read().paused
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                skipByInterval skipInterval: CMTime,
                                                completion completionHandler: @escaping () -> Void) {
        let seconds = CMTimeGetSeconds(skipInterval)
        onMain { pip in
            // Previous / next page, then item (PiPNavigation); never a seek, never audio-driven.
            pip.commands?.skip(by: seconds.isFinite ? seconds : 0)
            completionHandler()
        }
    }

    nonisolated func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ controller: AVPictureInPictureController) -> Bool {
        false
    }
}
