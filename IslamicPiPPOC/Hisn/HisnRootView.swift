import SwiftUI
import IslamicCore
import HisnReading

/// Hisn Al-Muslim: chapter index, search and reader. Arabic, right to left, system styles
/// (Dynamic Type, dark mode) only. Presented over the app; the PiP screen stays underneath.
struct HisnRootView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = HisnLibraryModel()
    @State private var path: [HisnRoute] = []
    @AppStorage(HisnSettings.hapticsKey) private var hapticsEnabled = true

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("حصن المسلم")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("إغلاق") { dismiss() }
                    }
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
                        HisnReaderView(reader: reader, store: model.positionStore, audioRepository: audio)
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

/// The 133 presentation sections in order, the same-day resume entry, and search.
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
                            VStack(alignment: .leading, spacing: 4) {
                                Text("متابعة القراءة").font(.headline)
                                Text(chapter.titleArabic).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityHint("يفتح الذكر الذي توقفت عنده اليوم")
                    }
                }
                Section("الأبواب") {
                    ForEach(library.sections) { entry in
                        NavigationLink(value: model.route(forChapter: entry.id)) {
                            HisnSectionRow(entry: entry)
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

private struct HisnSectionRow: View {
    let entry: HisnSectionEntry

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
            Text(entry.title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(entry.itemCount)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.title)
        .accessibilityValue("عدد الأذكار \(entry.itemCount)")
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
