import SwiftUI
import ContentKit
import GlobalSearch
import QuranText

/// Search across the Quran, Hisn Al-Muslim, the adhkar and the duas.
struct GlobalSearchView: View {
    @State private var engine: GlobalSearchEngine?
    @State private var query = ""
    @State private var source: GlobalSearchResult.Source?
    @State private var response = GlobalSearchResponse.empty

    var body: some View {
        List {
            Section {
                SearchField(text: $query, prompt: "ابحث في كل المحتوى", accessibilityLabel: "بحث في كل المحتوى")
                Picker("المصدر", selection: $source) {
                    Text("الكل").tag(GlobalSearchResult.Source?.none)
                    ForEach(GlobalSearchResult.Source.allCases, id: \.self) { source in
                        Text(source.title).tag(Optional(source))
                    }
                }
            }
            if engine == nil {
                Section { ProgressView("جارٍ تجهيز البحث…") }
            } else if !response.query.isEmpty {
                results
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("البحث")
        .task {
            if engine == nil { engine = await AppServices.shared.content.globalSearch() }
            run()
        }
        .onChange(of: query) { run() }
        .onChange(of: source) { run() }
    }

    private func run() {
        response = engine?.search(query, source: source) ?? .empty
    }

    @ViewBuilder
    private var results: some View {
        if response.results.isEmpty {
            Section {
                ContentUnavailableView("لا توجد نتائج", systemImage: "magnifyingglass",
                                       description: Text("جرّب كلمة أخرى أو جزءاً منها."))
            }
        } else {
            if let corrected = response.correctedQuery {
                Section {
                    Text("لا نتائج لما كُتب. النتائج لـ «\(corrected)».")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(response.results) { result in
                    Button {
                        AppServices.shared.router.open(result.destination)
                    } label: {
                        ResultRow(result: result)
                    }
                    .foregroundStyle(.primary)
                }
            } header: {
                Text(summary)
            }
        }
    }

    private var summary: String {
        let total = response.totalCount
        let shown = response.results.count
        return shown < total ? "\(arabicResultCount(total))، يُعرض أفضل \(shown)" : arabicResultCount(total)
    }
}

private struct ResultRow: View {
    let result: GlobalSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.source.title)
                .font(.caption2.bold())
                .foregroundStyle(.tint)
            if result.isTitle {
                Text(highlightedText(result.matchedText, range: result.highlight))
                    .font(.headline)
            } else {
                Text(highlightedText(result.matchedText, range: result.highlight))
                    .font(result.source == .quran ? QuranTypography.font(size: 20) : .body)
                    .lineLimit(4)
                Text(result.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(result.source.title)، \(result.isTitle ? result.matchedText : result.title)")
        .accessibilityValue(result.isTitle ? "" : result.matchedText)
        .accessibilityHint("يفتح النتيجة في موضعها")
    }
}
