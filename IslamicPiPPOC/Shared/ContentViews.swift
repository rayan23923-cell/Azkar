import SwiftUI
import QuranText

/// A load failure with an optional retry. The bundled content should always load; this is
/// the safe path if a file is damaged.
struct ContentErrorView: View {
    let message: String
    let retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("تعذّر التحميل", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button("إعادة المحاولة", action: retry)
            }
        }
    }
}

/// The Quran text font: Amiri Quran, registered at launch, scaled with Dynamic Type. Falls
/// back to the system font only if registration failed (tested not to happen).
enum QuranTypography {
    static func font(size: CGFloat, relativeTo style: Font.TextStyle = .title2) -> Font {
        if QuranFont.register() {
            return .custom(QuranFont.familyName, size: size, relativeTo: style)
        }
        return .system(size: size)
    }
}

/// «متابعة القراءة»: where reading stopped and when.
struct ResumeRow: View {
    let title: String
    let detail: String
    let date: Date

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bookmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("متابعة القراءة")
                    .font(.caption.bold())
                    .foregroundStyle(.tint)
                Text(title)
                Text("\(detail) · \(date.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
