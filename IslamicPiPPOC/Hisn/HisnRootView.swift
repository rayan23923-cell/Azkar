import SwiftUI
import IslamicCore
import HisnReading

/// Hisn Al-Muslim: chapter index, search and reader. Arabic, right to left, system styles
/// (Dynamic Type, dark mode) only. The app's main tab (`AppRootView`).
struct HisnRootView: View {
    @StateObject private var model = HisnLibraryModel()
    @State private var path: [HisnRoute] = []
    @AppStorage(HisnSettings.hapticsKey) private var hapticsEnabled = true

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("حصن المسلم")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Toggle("الاهتزاز عند العدّ", isOn: $hapticsEnabled)
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("الإعدادات")
                    }
                }
                .navigationDestination(for: HisnRoute.self) { route in
                    if case .loaded(let library, _, let audio) = model.state,
                       let chapter = library.chapter(id: route.chapterId),
                       let reader = HisnReader(chapter: chapter, itemIndex: route.itemIndex,
                                               completedRepetitions: route.completedRepetitions) {
                        HisnReaderView(reader: reader, store: model.positionStore, audioRepository: audio,
                                       nextSection: library.section(after: chapter.id)) { next in
                            // «الفصل التالي»: replaces the finished chapter, so back returns to the index.
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
        case .loaded(let library, let index, _):
            HisnIndexView(library: library, index: index, model: model)
        }
    }
}

/// The 133 presentation sections in order, «متابعة القراءة» when a cursor is saved, and search.
private struct HisnIndexView: View {
    let library: HisnLibrary
    let index: HisnSearchIndex
    @ObservedObject var model: HisnLibraryModel
    @State private var query = ""

    var body: some View {
        let results = index.search(query)
        let searching = !HisnSearchKey.make(query).isEmpty
        List {
            if searching {
                HisnSearchResultsSection(results: results)
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
                            HisnSectionRow(entry: entry, isCurrent: entry.id == model.resumePosition?.chapterId)
                        }
                    }
                }
            }
        }
        .overlay {
            if searching && results.isEmpty {
                ContentUnavailableView {
                    Label("لا توجد نتائج", systemImage: "magnifyingglass")
                } description: {
                    Text("جرّب كلمة أخرى أو جزءاً من نص الذكر.")
                }
            }
        }
        .searchable(text: $query, prompt: "ابحث في الأذكار")
        .autocorrectionDisabled()
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
        .accessibilityValue(HisnAccessibility.sectionValue(entry, isCurrent: isCurrent))
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
