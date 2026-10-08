import SwiftUI
import UIKit

/// An Arabic search field with its own clear button, so both read in Arabic whatever the
/// system language.
struct SearchField: View {
    @Binding var text: String
    let prompt: String
    let accessibilityLabel: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel(accessibilityLabel)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel("مسح البحث")
            }
        }
    }
}

/// The matched whole words of a search preview in the accent colour and bold. Whole words
/// only, so Arabic letters stay joined.
func highlightedText(_ text: String, range: Range<Int>?) -> AttributedString {
    var attributed = AttributedString(text)
    let characters = attributed.characters
    guard let range, range.lowerBound >= 0, range.upperBound <= characters.count, !range.isEmpty else { return attributed }
    let lower = characters.index(characters.startIndex, offsetBy: range.lowerBound)
    let upper = characters.index(characters.startIndex, offsetBy: range.upperBound)
    attributed[lower..<upper].foregroundColor = .accentColor
    attributed[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
    return attributed
}

/// Arabic-Indic digits for ayah markers («٢٥٥»).
func arabicIndicDigits(_ number: Int) -> String {
    let digits: [Character] = ["٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"]
    return String(String(number).compactMap { $0.wholeNumberValue.map { digits[$0] } })
}

/// Arabic number agreement for result counts.
func arabicResultCount(_ count: Int) -> String {
    switch count {
    case 0: return "لا توجد نتائج"
    case 1: return "نتيجة واحدة"
    case 2: return "نتيجتان"
    case 3...10: return "\(count) نتائج"
    default: return "\(count) نتيجة"
    }
}

/// A short notice at the top of a screen that goes away by itself; also spoken.
struct TransientNotice: ViewModifier {
    @Binding var text: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let text {
                Text(text)
                    .font(.callout.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    func transientNotice(_ text: Binding<String?>) -> some View { modifier(TransientNotice(text: text)) }
}

@MainActor
func showNotice(_ message: String, in binding: Binding<String?>) {
    withAnimation { binding.wrappedValue = message }
    UIAccessibility.post(notification: .announcement, argument: message)
    Task {
        try? await Task.sleep(nanoseconds: 1_600_000_000)
        withAnimation { if binding.wrappedValue == message { binding.wrappedValue = nil } }
    }
}
