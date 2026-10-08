import SwiftUI
import HisnReading

/// The reader's PiP row: a small live preview of the PiP frame (the layer the PiP window grows
/// from) and the «عرض عائم» button. Shown only while the current dhikr has a recording, so it
/// never appears with the empty production audio pack.
struct HisnPiPControls: View {
    @ObservedObject var pip: HisnPiPCoordinator
    /// Observed so the row follows the recording's availability.
    @ObservedObject var player: HisnAudioPlayer
    let surface: SampleBufferPiPSurface

    var body: some View {
        if pip.isAvailable {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    HisnPiPLayerView(surface: surface)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityHidden(true)
                        .onAppear {
                            surface.prepareController()
                            pip.setInlineVisible(true)
                        }
                        .onDisappear { pip.setInlineVisible(false) }
                    Spacer(minLength: 0)
                    if pip.status == .inactive {
                        Button {
                            pip.start()
                        } label: {
                            Label("عرض عائم", systemImage: "pip.enter")
                        }
                        .disabled(!pip.isPossible)
                        .accessibilityHint("يعرض الذكر في نافذة عائمة فوق التطبيقات الأخرى")
                    } else {
                        Button {
                            pip.stop()
                        } label: {
                            Label("إغلاق العرض العائم", systemImage: "pip.exit")
                        }
                    }
                }
                .buttonStyle(.bordered)
                if let failure = pip.failure {
                    Label(message(for: failure), systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func message(for failure: HisnPiPCoordinator.Failure) -> String {
        switch failure {
        case .notSupported: return "العرض العائم غير مدعوم على هذا الجهاز"
        case .notPossible: return "العرض العائم غير متاح الآن"
        case .failedToStart: return "تعذر بدء العرض العائم، والتسجيل مستمر"
        }
    }
}

/// Hosts the surface's display layer inline. PiP needs the layer on screen to become possible.
struct HisnPiPLayerView: UIViewRepresentable {
    let surface: SampleBufferPiPSurface

    func makeUIView(context: Context) -> LayerHostView {
        let view = LayerHostView()
        view.hosted = surface.displayLayer
        return view
    }

    func updateUIView(_ view: LayerHostView, context: Context) {}

    final class LayerHostView: UIView {
        var hosted: CALayer? {
            didSet {
                oldValue?.removeFromSuperlayer()
                if let hosted { layer.addSublayer(hosted) }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            hosted?.frame = bounds
        }
    }
}
