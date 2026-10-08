import SwiftUI
import UIKit
import HisnReading
import HisnShareCard

/// System haptics for Hisn events. Off when the user turned «الاهتزاز عند العدّ» off; silently
/// does nothing on hardware without haptics.
@MainActor
final class SystemHisnHaptics: HisnHaptics {
    static let shared = SystemHisnHaptics()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var isEnabled: Bool {
        defaults.object(forKey: HisnSettings.hapticsKey) as? Bool ?? true
    }

    func play(_ event: HisnHapticEvent) {
        guard isEnabled else { return }
        switch event {
        case .itemCompleted, .chapterCompleted, .copied:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .cardReady:
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

/// The general pasteboard.
@MainActor
final class SystemPasteboard: HisnTextPasteboard {
    var string: String? {
        get { UIPasteboard.general.string }
        set { UIPasteboard.general.string = newValue }
    }
}

/// What the system share sheet receives: the dhikr text or the generated card image.
struct HisnSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// The iOS share sheet; the system decides the targets.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension HisnShareCardRenderer.Appearance {
    init(_ scheme: ColorScheme) {
        self = scheme == .dark ? .dark : .light
    }
}
