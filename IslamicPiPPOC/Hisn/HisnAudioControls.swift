import SwiftUI
import HisnReading

/// Compact recording controls under the dhikr: play / pause, stop, progress and times.
/// Shown only when the item has a recording (or its recording failed); nothing otherwise.
struct HisnAudioControls: View {
    @ObservedObject var player: HisnAudioPlayer
    /// The slider position while the user drags it; nil otherwise.
    @State private var scrubbing: Double?

    var body: some View {
        if case .failed(let failure) = player.state {
            Label(message(for: failure), systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if player.availability == .available {
            if player.state.isPlaying {
                // Samples the current time four times a second, only while playing.
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    controls
                }
            } else {
                controls
            }
        }
    }

    private var controls: some View {
        let duration = max(player.duration ?? 0, 0.1)
        let position = min(scrubbing ?? player.currentTime, duration)
        return HStack(spacing: 12) {
            Button {
                player.togglePlayback()
            } label: {
                Image(systemName: player.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel(playLabel)

            if player.state == .playing || player.state == .paused {
                Button {
                    player.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("إيقاف الذكر")
            }

            VStack(spacing: 2) {
                Slider(value: Binding(get: { position }, set: { scrubbing = $0 }), in: 0...duration,
                       onEditingChanged: { editing in
                           if !editing, let target = scrubbing {
                               player.seek(to: target)
                               scrubbing = nil
                           }
                       })
                .accessibilityLabel("التقدم في التسجيل")
                .accessibilityValue("\(timeText(position)) من \(timeText(duration))")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: player.seek(to: player.currentTime + 5)
                    case .decrement: player.seek(to: player.currentTime - 5)
                    @unknown default: break
                    }
                }
                HStack {
                    Text(timeText(position))
                        .accessibilityLabel("الوقت المنقضي \(timeText(position))")
                    Spacer()
                    if player.duration != nil {
                        Text(timeText(duration))
                            .accessibilityLabel("مدة التسجيل \(timeText(duration))")
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    private var playLabel: String {
        switch player.state {
        case .playing: return "إيقاف مؤقت"
        case .paused: return "استئناف الذكر"
        default: return "تشغيل الذكر"
        }
    }

    private func message(for failure: HisnAudioFailure) -> String {
        switch failure {
        case .unavailable: return "التسجيل غير متوفر"
        case .couldNotLoad: return "تعذر تشغيل التسجيل"
        case .couldNotPlay: return "حدث خطأ أثناء تشغيل التسجيل"
        }
    }

    private func timeText(_ seconds: Double) -> String {
        Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: .minuteSecond))
    }
}
