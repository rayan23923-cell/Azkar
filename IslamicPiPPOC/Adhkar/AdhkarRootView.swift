import SwiftUI
import IslamicCore
import ContentKit
import AdhkarReading

/// Adhkar and duas: the collections, search, and the counter reader. Arabic, right to left.
struct AdhkarRootView: View {
    enum Scope: String, CaseIterable {
        case all, adhkar, dua

        var title: String {
            switch self {
            case .all: return "الكل"
            case .adhkar: return "الأذكار"
            case .dua: return "الأدعية"
            }
        }

        var kind: DevotionalCollection.Kind? {
            switch self {
            case .all: return nil
            case .adhkar: return .adhkar
            case .dua: return .dua
            }
        }
    }

    private enum LoadState {
        case loading
        case loaded(AdhkarLibrary, DevotionalSearchIndex)
        case failed
    }

    @ObservedObject private var router = AppServices.shared.router
    @ObservedObject private var favorites = AppServices.shared.favorites
    @State private var state: LoadState = .loading
    @State private var path: [DevotionalRoute] = []
    @State private var query = ""
    @State private var scope: Scope = .all
    @State private var results: [DevotionalSearchResult] = []
    /// Refreshed when coming back from a reader, for the completed marks and resume rows.
    @State private var refresh = 0

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("الأذكار والأدعية")
                .navigationDestination(for: DevotionalRoute.self) { route in
                    if case .loaded(let library, _) = state, let collection = library.collection(route.collection) {
                        DevotionalReaderView(collection: collection, start: route.item,
                                             highlights: route.highlights)
                            .id(route)
                    } else {
                        ContentErrorView(message: "تعذّر فتح هذا القسم.", retry: nil)
                    }
                }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
        .task { await loadIfNeeded() }
        .onChange(of: path) { refresh += 1 }
        .onChange(of: router.devotionalTarget, initial: true) { openPendingTarget() }
    }

    private var isLoaded: Bool {
        if case .loaded = state { return true }
        return false
    }

    private func loadIfNeeded() async {
        guard !isLoaded else { return }
        state = .loading
        do {
            let adhkar = try await AppServices.shared.content.adhkar()
            state = .loaded(adhkar.library, adhkar.search)
            openPendingTarget()
        } catch {
            state = .failed
        }
    }

    private func openPendingTarget() {
        guard let target = router.devotionalTarget, isLoaded else { return }
        router.devotionalTarget = nil
        path = [target]
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView("جارٍ التحميل…")
        case .failed:
            ContentErrorView(message: "تعذّر تحميل الأذكار والأدعية من التطبيق.") {
                Task { await loadIfNeeded() }
            }
        case .loaded(let library, let index):
            list(library: library, index: index)
        }
    }

    private func list(library: AdhkarLibrary, index: DevotionalSearchIndex) -> some View {
        let searching = !ArabicSearchNormalizer.normalize(query).isEmpty
        return List {
            Section {
                SearchField(text: $query, prompt: "ابحث في الأذكار والأدعية", accessibilityLabel: "بحث في الأذكار والأدعية")
                Picker("القسم", selection: $scope) {
                    ForEach(Scope.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if searching {
                searchResults
            } else {
                favoritesSection(library: library)
                if scope != .dua {
                    collectionSection("الأذكار", library.adhkar)
                }
                if scope != .adhkar {
                    collectionSection("الأدعية", library.duas)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: query, initial: true) { results = index.search(query, kind: scope.kind) }
        .onChange(of: scope) { results = index.search(query, kind: scope.kind) }
    }

    private struct SavedItem {
        let ref: ContentRef
        let collection: DevotionalCollection
        let item: DevotionalItem
    }

    /// «المفضلة»: the saved adhkar and duas in this scope, newest first; each opens at its item.
    @ViewBuilder
    private func favoritesSection(library: AdhkarLibrary) -> some View {
        let saved = favorites.entries.compactMap { entry -> SavedItem? in
            guard entry.ref.kind == .adhkar || entry.ref.kind == .dua, let found = library.locate(entry.ref),
                  scope.kind == nil || found.collection.kind == scope.kind else { return nil }
            return SavedItem(ref: entry.ref, collection: found.collection, item: found.collection.items[found.index])
        }
        if !saved.isEmpty {
            Section("المفضلة") {
                ForEach(saved, id: \.ref) { entry in
                    NavigationLink(value: DevotionalRoute(collection: entry.collection.ref, item: entry.ref,
                                                          highlights: true)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.item.text)
                                .lineLimit(2)
                            Text(entry.collection.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            favorites.remove(entry.ref)
                        } label: { Label("إزالة", systemImage: "star.slash") }
                    }
                }
            }
        }
    }

    private func collectionSection(_ title: String, _ collections: [DevotionalCollection]) -> some View {
        Section(title) {
            ForEach(collections) { collection in
                let completed = AppServices.shared.isCompletedToday(collection.ref)
                let saved = AppServices.shared.devotionalPositions.position(in: collection.ref)
                NavigationLink(value: DevotionalRoute(collection: collection.ref)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(collection.title)
                            if let saved, let index = collection.items.firstIndex(where: { $0.ref == saved.item }) {
                                Text("متابعة من \(DevotionalAccessibility.itemPosition(index, of: collection.items.count))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("\(collection.items.count) \(collection.kind == .adhkar ? "أذكار" : "أدعية")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if completed {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(DevotionalAccessibility.collectionLabel(collection, completedToday: completed))
                }
            }
        }
        .id(refresh)
    }

    @ViewBuilder
    private var searchResults: some View {
        if results.isEmpty {
            Section {
                ContentUnavailableView("لا توجد نتائج", systemImage: "magnifyingglass",
                                       description: Text("جرّب كلمة أخرى."))
            }
        } else {
            Section {
                ForEach(results) { result in
                    NavigationLink(value: DevotionalRoute(collection: result.collection, item: result.item,
                                                          highlights: result.item != nil)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(highlightedText(result.matchedText, range: result.highlight))
                                .lineLimit(result.kind == .collection ? 1 : 4)
                            if result.kind == .item {
                                Text(result.collectionTitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(DevotionalAccessibility.searchResultLabel(result))
                        .accessibilityValue(result.kind == .item ? result.matchedText : "")
                    }
                }
            } header: {
                Text(arabicResultCount(results.count))
            }
        }
    }
}
