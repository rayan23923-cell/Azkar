import SwiftUI
import IslamicCore
import HisnReading

/// The Arabic search field with its own clear button («مسح البحث»).
struct HisnSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("ابحث في الأبواب والأذكار", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel(HisnAccessibility.searchField)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .accessibilityLabel(HisnAccessibility.clearSearch)
            }
        }
    }
}

/// Search results in rank order, with the count. Each row opens its chapter or item.
struct HisnSearchResultsSection: View {
    let results: [HisnSearchResult]
    let route: (HisnSearchResult) -> HisnRoute?

    var body: some View {
        if results.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("لا توجد نتائج", systemImage: "magnifyingglass")
                } description: {
                    Text("جرّب كلمة أخرى أو جزءاً من نص الذكر.")
                }
            }
        } else {
            Section {
                ForEach(results) { result in
                    if let route = route(result) {
                        NavigationLink(value: route) {
                            HisnSearchResultRow(result: result)
                        }
                    }
                }
            } header: {
                Text(HisnAccessibility.resultCount(results.count))
            }
        }
    }
}

private struct HisnSearchResultRow: View {
    let result: HisnSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch result.kind {
            case .chapter:
                Label {
                    Text(highlighted)
                        .font(.headline)
                } icon: {
                    Image(systemName: "book")
                        .foregroundStyle(.tint)
                }
                Text("باب · عدد الأذكار \(result.chapterItemCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .item:
                Text(highlighted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(result.chapterTitle) · الذكر \((result.itemIndex ?? 0) + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HisnAccessibility.searchResultLabel(result))
        .accessibilityValue(HisnAccessibility.searchResultValue(result))
        .accessibilityHint(HisnAccessibility.searchResultHint(result))
    }

    /// The text as stored, with the matched whole words in the accent colour and bold. Whole
    /// words only, so no word is split into differently styled pieces.
    private var highlighted: AttributedString {
        var text = AttributedString(result.matchedText)
        let characters = text.characters
        guard let range = result.highlight, range.lowerBound >= 0, range.upperBound <= characters.count else {
            return text
        }
        let lower = characters.index(characters.startIndex, offsetBy: range.lowerBound)
        let upper = characters.index(characters.startIndex, offsetBy: range.upperBound)
        text[lower..<upper].foregroundColor = .accentColor
        text[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
        return text
    }
}
