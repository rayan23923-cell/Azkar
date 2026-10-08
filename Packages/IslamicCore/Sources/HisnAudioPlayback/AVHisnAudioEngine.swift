import AVFoundation
import Foundation
import HisnReading

/// `HisnAudioEngine` on `AVAudioPlayer`: the simplest player for short local files (load,
/// play, pause, seek, duration, current time, end-of-file). No streaming, no network.
@MainActor
public final class AVHisnAudioEngine: NSObject, HisnAudioEngine {
    public var onFinish: (() -> Void)?
    public var onFailure: (() -> Void)?
    private var player: AVAudioPlayer?

    public override init() {
        super.init()
    }

    public var currentTime: TimeInterval { player?.currentTime ?? 0 }
    public var duration: TimeInterval { player?.duration ?? 0 }

    public func load(url: URL) throws {
        unload()
        guard url.isFileURL else { throw URLError(.unsupportedURL) }
        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.prepareToPlay()
        self.player = player
    }

    public func play() -> Bool {
        player?.play() ?? false
    }

    public func pause() {
        player?.pause()
    }

    public func stop() {
        player?.stop()
        player?.currentTime = 0
    }

    public func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(0, time), player.duration)
    }

    public func unload() {
        player?.stop()
        player?.delegate = nil
        player = nil
    }
}

extension AVHisnAudioEngine: AVAudioPlayerDelegate {
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in
            guard let current = self.player, ObjectIdentifier(current) == id else { return }
            if flag { self.onFinish?() } else { self.onFailure?() }
        }
    }

    nonisolated public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in
            guard let current = self.player, ObjectIdentifier(current) == id else { return }
            self.onFailure?()
        }
    }
}
