import Combine
import PiPCore
import SwiftUI
import UIKit

/// One reader screen's PiP: its section's provider and its own platform controller, registered
/// with the app's single `PiPEngine`. Created once per screen.
@MainActor
final class ReaderPiP: ObservableObject {
    let provider: PiPContentProvider
    let controller: SampleBufferPiPController
    private let engine: PiPEngine
    private var subscription: AnyCancellable?

    init(provider: PiPContentProvider, engine: PiPEngine = AppServices.shared.pip) {
        self.provider = provider
        self.engine = engine
        controller = SampleBufferPiPController(allowsAutomaticStart: engine.availability.allowsAutomaticStart)
        engine.register(controller, provider: provider)
        // The engine is the one source of PiP state; this screen re-reads it on every change.
        subscription = engine.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
    }

    /// The PiP button is shown: the build and the setting allow PiP and the device supports it.
    var isOffered: Bool { engine.canOffer(on: controller) }
    var isRunning: Bool { engine.isRunning(provider) }
    var failure: PiPError? { engine.failure(for: provider) }

    func toggle() {
        if isRunning {
            engine.stop()
        } else {
            engine.start(provider, on: controller)
        }
    }

    func setInlineVisible(_ visible: Bool) {
        if visible { controller.prepare() }
        engine.setInlineVisible(visible, for: controller)
    }

    /// The screen was closed (popped): its PiP closes too, and its place is saved by the reader.
    func screenClosed() {
        engine.setInlineVisible(false, for: controller)
        engine.stop(ifShowing: provider)
    }
}

/// The PiP row of a reader: a small live preview (the layer the window grows from) and the
/// «نافذة عائمة» button, which closes the window again while it shows this screen's content.
/// Hidden when PiP is not offered.
struct PiPEntryView: View {
    @ObservedObject var pip: ReaderPiP
    var startTitle = "نافذة عائمة"

    var body: some View {
        if pip.isOffered {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    PiPLayerView(controller: pip.controller)
                        .aspectRatio(CGFloat(AppServices.shared.pipLayout.width)
                                     / CGFloat(AppServices.shared.pipLayout.height), contentMode: .fit)
                        .frame(height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityHidden(true)
                        .onAppear { pip.setInlineVisible(true) }
                        .onDisappear { pip.setInlineVisible(false) }
                    Button {
                        pip.toggle()
                    } label: {
                        if pip.isRunning {
                            Label("إغلاق النافذة العائمة", systemImage: "pip.exit")
                        } else {
                            Label(startTitle, systemImage: "pip.enter")
                        }
                    }
                    .accessibilityLabel(pip.isRunning ? "إغلاق النافذة العائمة" : startTitle)
                    .accessibilityHint(pip.isRunning
                        ? "يغلق النافذة العائمة ويبقى موضع القراءة كما هو"
                        : "يعرض النص الحالي في نافذة عائمة فوق التطبيقات الأخرى. التشغيل والإيقاف يقلّبان الصفحات، والتقديم والرجوع ينتقلان بين العناصر")
                    Spacer(minLength: 0)
                }
                .buttonStyle(.bordered)
                if let failure = pip.failure {
                    Label(Self.message(for: failure), systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    static func message(for failure: PiPError) -> String {
        switch failure {
        case .notSupported: return "العرض العائم غير مدعوم على هذا الجهاز"
        case .disabled: return "العرض العائم متوقف من الإعدادات"
        case .noContent: return "لا يوجد نص لعرضه الآن"
        case .failedToStart: return "تعذّر بدء العرض العائم"
        }
    }
}

/// Hosts the controller's display layer inline. PiP needs the layer on screen to become possible.
struct PiPLayerView: UIViewRepresentable {
    let controller: SampleBufferPiPController

    func makeUIView(context: Context) -> LayerHostView {
        let view = LayerHostView()
        view.hosted = controller.displayLayer
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
