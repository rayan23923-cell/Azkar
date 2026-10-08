import AVFoundation
import AVKit
import HisnReading
import UIKit

/// The Hisn PiP surface on the device-proven sample-buffer path (see PHASE_3C_PIP_AUDIT.md):
/// an inline `AVSampleBufferDisplayLayer` with a host-clock `CMTimebase` as its control
/// timebase, `ContentSource(sampleBufferDisplayLayer:playbackDelegate:)`, one strongly
/// retained `AVPictureInPictureController`, and a 0.5 s frame heartbeat. Frames are drawn by
/// `HisnPiPFrameRenderer` and wrapped by the same `AzkarFrameRenderer.makeSampleBuffer`.
///
/// PiP semantics live in `HisnPiPCoordinator`; this class only adapts AVKit to it.
/// Automatic start from inline is off: Hisn PiP starts when the user asks.
@MainActor
final class SampleBufferPiPSurface: NSObject, HisnPiPSurface {
    let displayLayer = AVSampleBufferDisplayLayer()
    let isSupported = AVPictureInPictureController.isPictureInPictureSupported()
    private(set) var isPossible = false
    var onEvent: ((HisnPiPSurfaceEvent) -> Void)?
    var contentProvider: (() -> HisnPiPContent?)?
    /// Set by the coordinator's owner so the delegate can reach the PiP semantics.
    weak var coordinator: (any PiPPlaybackControlling)?

    private var pipController: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private var timebase: CMTimebase?
    private var heartbeat: Timer?
    private let renderer = HisnPiPFrameRenderer()
    /// Values AVKit may ask for synchronously; updated on main with every frame.
    private let snapshot = PlaybackSnapshot()

    override init() {
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

    /// Builds the controller once, when the inline layer is first shown.
    func prepareController() {
        guard isSupported, pipController == nil else { return }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer,
                                                                playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        controller.requiresLinearPlayback = false
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] c, _ in
            let possible = c.isPictureInPicturePossible
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isPossible = possible
                    self.onEvent?(.possibleChanged(possible))
                }
            }
        }
        pipController = controller
    }

    func start() {
        pipController?.startPictureInPicture()
    }

    func stop() {
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

    /// Draws the current content. The timebase follows the audio player: its time is the
    /// recording's current time and its rate is 1 only while playing, so the system's PiP
    /// progress matches the audio.
    private func drawFrame() {
        guard let content = contentProvider?() else { return }
        let playing = content.playback == .playing
        snapshot.update(paused: !playing, duration: content.duration)
        let time = CMTime(seconds: content.currentTime, preferredTimescale: 600)
        if let timebase {
            CMTimebaseSetRate(timebase, rate: 0)
            CMTimebaseSetTime(timebase, time: time)
            CMTimebaseSetRate(timebase, rate: playing ? 1 : 0)
        }
        guard let pixelBuffer = renderer.makePixelBuffer(content: content),
              let sample = AzkarFrameRenderer.makeSampleBuffer(pixelBuffer: pixelBuffer, presentationTime: time) else {
            return
        }
        let output = displayLayer.sampleBufferRenderer
        if output.status == .failed { output.flush() }
        output.enqueue(sample)
    }
}

/// Thread-safe copy of what AVKit asks for synchronously.
private final class PlaybackSnapshot: @unchecked Sendable {
    private let lock = NSLock()
    private var paused = true
    private var duration: TimeInterval?

    func update(paused: Bool, duration: TimeInterval?) {
        lock.lock(); defer { lock.unlock() }
        self.paused = paused
        self.duration = duration
    }

    func read() -> (paused: Bool, duration: TimeInterval?) {
        lock.lock(); defer { lock.unlock() }
        return (paused, duration)
    }
}

// MARK: - AVPictureInPictureControllerDelegate

extension SampleBufferPiPSurface: AVPictureInPictureControllerDelegate {
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
        // The reader is still on screen underneath; nothing to rebuild.
        completionHandler(true)
    }

    nonisolated private func onMain(_ work: @escaping @MainActor (SampleBufferPiPSurface) -> Void) {
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

extension SampleBufferPiPSurface: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        onMain { $0.coordinator?.setPlaying(playing) }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        let duration = snapshot.read().duration ?? 0
        // A finite range from the recording: the system shows skip buttons and progress.
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
        onMain { surface in
            // A seek inside the current recording, never the next dhikr.
            surface.coordinator?.skip(by: seconds.isFinite ? seconds : 0)
            completionHandler()
        }
    }

    nonisolated func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ controller: AVPictureInPictureController) -> Bool {
        false
    }
}
