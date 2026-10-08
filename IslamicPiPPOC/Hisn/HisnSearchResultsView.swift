import SwiftUI
import IslamicCore
import HisnReading

/// Offline search results: exact matches first, then partial ones. Each opens its item.
struct HisnSearchResultsSection: View {
    let results: [HisnSearchResult]

    var body: some View {
        if !results.isEmpty {
            Section {
                ForEach(results) { result in
                    NavigationLink(value: HisnRoute(chapterId: result.chapterId, itemIndex: result.itemIndex)) {
                        HisnSearchResultRow(result: result)
                    }
                }
            } header: {
                Text("النتائج: \(results.count)")
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
                Text(result.chapterTitle).font(.headline)
                Text("باب").font(.caption).foregroundStyle(.secondary)
            case .item:
                Text(result.itemText ?? "")
                    .lineLimit(3)
                Text(result.chapterTitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
