import SwiftUI
import IslamicCore
import HisnReading

/// Hisn Al-Muslim: chapter index, search and reader. Arabic, right to left, system styles
/// (Dynamic Type, dark mode) only. A tab of `AppRootView`.
struct HisnRootView: View {
    @StateObject private var model = HisnLibraryModel()
    @State private var path: [HisnRoute] = []
    @ObservedObject private var router = AppServices.shared.router

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("حصن المسلم")
                .navigationDestination(for: HisnRoute.self) { route in
                    if case .loaded(let library, _, let audio) = model.state,
                       let chapter = library.chapter(id: route.chapterId),
                       let reader = HisnReader(chapter: chapter, itemIndex: route.itemIndex,
                                               completedRepetitions: route.completedRepetitions) {
                        HisnReaderView(reader: reader, store: model.positionStore, dailyProgress: model.dailyProgress,
                                       audioRepository: audio,
                                       highlightedItemId: route.highlightedItemId,
                                       nextSection: library.section(after: chapter.id)) { next in
                            // «الباب التالي»: replaces the finished chapter, so back returns to the index.
                            path[path.count - 1] = HisnRoute(chapterId: next.id, itemIndex: 0)
                        }
                        .id(route)
                    } else {
                        HisnErrorView(message: "تعذّر فتح هذا الباب.", retry: nil)
                    }
                }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
        .task {
            if case .loading = model.state { await model.load() }
        }
        .onChange(of: path) {
            model.refreshResume()
        }
        .onAppear { model.refreshResume() }
        // A result from global search: opened once the book is loaded.
        .onChange(of: router.hisnTarget, initial: true) { openPendingTarget() }
        .onChange(of: model.isLoaded) { openPendingTarget() }
    }

    private func openPendingTarget() {
        guard let target = router.hisnTarget, model.isLoaded else { return }
        router.hisnTarget = nil
        if let route = model.route(for: target) { path = [route] }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("جارٍ تحميل الأذكار…")
        case .failed:
            HisnErrorView(message: "تعذّر تحميل حصن المسلم من التطبيق.") {
                Task { await model.load() }
            }
        case .loaded(let library, let search, _):
            HisnIndexView(library: library, search: search, model: model)
        }
    }
}

/// The 133 presentation sections in order, «متابعة القراءة» when a cursor is saved, and search.
/// The query lives only while this screen exists; it is not saved.
private struct HisnIndexView: View {
    let library: HisnLibrary
    let search: HisnSearchEngine
    @ObservedObject var model: HisnLibraryModel
    @State private var query = ""
    @State private var filter: HisnSearchFilter = .all
    @State private var results: [HisnSearchResult] = []

    var body: some View {
        let searching = HisnSearchEngine.isSearchable(query)
        List {
            Section {
                HisnSearchField(text: $query)
                if searching {
                    Picker(HisnAccessibility.searchFilter, selection: $filter) {
                        ForEach(HisnSearchFilter.allCases, id: \.self) { filter in
                            Text(HisnAccessibility.filterTitle(filter)).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            if searching {
                HisnSearchResultsSection(results: results) { model.route(for: $0) }
            } else {
                if let position = model.resumePosition, let chapter = library.chapter(id: position.chapterId) {
                    Section {
                        NavigationLink(value: model.route(for: position)) {
                            HisnResumeRow(position: position, chapter: chapter)
                        }
                        .accessibilityHint("يفتح الذكر الذي توقفت عنده")
                    }
                }
                Section("الأبواب") {
                    ForEach(library.sections) { entry in
                        NavigationLink(value: model.route(forChapter: entry.id)) {
                            HisnSectionRow(entry: entry, isCurrent: entry.id == model.resumePosition?.chapterId,
                                           completedToday: model.isCompletedToday(entry.id))
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        // Searches run only when the query or the filter changes, against the index built once.
        .onChange(of: query, initial: true) { runSearch() }
        .onChange(of: filter) { runSearch() }
    }

    private func runSearch() {
        results = search.search(query, filter: filter)
    }
}

/// «متابعة القراءة»: the saved chapter, item and when it was last read.
private struct HisnResumeRow: View {
    let position: HisnReadingPosition
    let chapter: HisnChapter

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("متابعة القراءة", systemImage: "bookmark.fill")
                .font(.headline)
            Text(chapter.titleArabic)
                .font(.subheadline)
            HStack(spacing: 6) {
                Text("الذكر \(min(position.itemIndex, chapter.itemCount - 1) + 1) من \(chapter.itemCount)")
                Text("·").accessibilityHidden(true)
                Text(position.savedAt, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HisnSectionRow: View {
    let entry: HisnSectionEntry
    /// The saved reading cursor is in this section.
    let isCurrent: Bool
    /// Read to the end today.
    var completedToday = false

    var body: some View {
        HStack(spacing: 12) {
            if let number = entry.bookChapterNumber {
                Text("\(number)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 28, alignment: .leading)
            }
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(.tint)
            }
            Text(entry.title)
                .frame(maxWidth: .infinity, alignment: .leading)
            if completedToday {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            if isCurrent {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(.tint)
            }
            Text("\(entry.itemCount)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HisnAccessibility.sectionLabel(entry))
        .accessibilityValue(HisnAccessibility.sectionValue(entry, isCurrent: isCurrent, completedToday: completedToday))
    }

    private var symbol: String? {
        switch entry.timeOfDay {
        case .morning: return "sun.max"
        case .evening: return "moon"
        case nil: return nil
        }
    }
}

struct HisnErrorView: View {
    let message: String
    let retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("حدث خطأ", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button("إعادة المحاولة", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
