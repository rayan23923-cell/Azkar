import SwiftUI
import IslamicCore
import ContentKit
import QuranReading
import QuranText

/// The Quran: surah index, juz index, bookmarks, search and the reader. Arabic, right to left.
struct QuranRootView: View {
    @StateObject private var model = QuranLibraryModel()
    @ObservedObject private var favorites = AppServices.shared.favorites
    @ObservedObject private var router = AppServices.shared.router
    @State private var path: [QuranRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("القرآن الكريم")
                .navigationDestination(for: QuranRoute.self) { route in
                    if let library = model.library,
                       library.contains(QuranVerseRef(surah: route.surah, ayah: route.ayah)) {
                        QuranReadingScreen(library: library, start: QuranVerseRef(surah: route.surah, ayah: route.ayah),
                                           store: model.positionStore, highlightedAyah: route.highlights ? route.ayah : nil)
                            .id(route)
                    } else if model.library == nil {
                        ProgressView()
                    } else {
                        ContentErrorView(message: "تعذّر فتح هذه السورة.", retry: nil)
                    }
                }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
        .task {
            if case .loading = model.state { await model.load() }
        }
        .onChange(of: path) { model.refreshResume() }
        .onAppear { model.refreshResume() }
        .onChange(of: router.quranTarget, initial: true) {
            guard let target = router.quranTarget else { return }
            path = [QuranRoute(surah: target.surah, ayah: target.ayah, highlights: router.quranHighlights)]
            router.quranTarget = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("جارٍ تحميل القرآن الكريم…")
        case .failed:
            ContentErrorView(message: "تعذّر تحميل القرآن الكريم من التطبيق.") {
                Task { await model.load() }
            }
        case .loaded(let library, let engine):
            QuranIndexView(library: library, engine: engine, model: model, favorites: favorites)
        }
    }
}

private struct QuranIndexView: View {
    enum Section: String, CaseIterable {
        case surahs, juz, bookmarks

        var title: String {
            switch self {
            case .surahs: return "السور"
            case .juz: return "الأجزاء"
            case .bookmarks: return "العلامات"
            }
        }
    }

    let library: QuranLibrary
    let engine: QuranSearchEngine
    @ObservedObject var model: QuranLibraryModel
    @ObservedObject var favorites: FavoritesModel
    @State private var section: Section = .surahs
    @State private var query = ""
    @State private var filter: QuranSearchFilter = .all
    @State private var results: [QuranSearchResult] = []

    var body: some View {
        let searching = !ArabicSearchNormalizer.normalize(query).isEmpty
        List {
            SwiftUI.Section {
                SearchField(text: $query, prompt: "ابحث في السور والآيات", accessibilityLabel: "بحث في القرآن الكريم")
                if searching {
                    Picker("نوع النتائج", selection: $filter) {
                        Text("الكل").tag(QuranSearchFilter.all)
                        Text("السور").tag(QuranSearchFilter.surahs)
                        Text("الآيات").tag(QuranSearchFilter.verses)
                    }
                    .pickerStyle(.segmented)
                } else {
                    Picker("القسم", selection: $section) {
                        ForEach(Section.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            if searching {
                searchResults
            } else {
                if let resume = model.resume, let surah = library.surah(resume.surah) {
                    SwiftUI.Section {
                        NavigationLink(value: QuranRoute(surah: resume.surah, ayah: resume.ayah)) {
                            ResumeRow(title: surah.fullArabicName, detail: "الآية \(resume.ayah) من \(surah.ayahCount)",
                                      date: resume.savedAt)
                        }
                        .accessibilityHint("يفتح الآية التي توقفت عندها")
                    }
                }
                switch section {
                case .surahs: surahList
                case .juz: juzList
                case .bookmarks: bookmarkList
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: query, initial: true) { runSearch() }
        .onChange(of: filter) { runSearch() }
    }

    private func runSearch() {
        results = engine.search(query, filter: filter)
    }

    private var surahList: some View {
        SwiftUI.Section {
            ForEach(library.surahs) { surah in
                NavigationLink(value: QuranRoute(surah: surah.id, ayah: 1)) {
                    HStack(spacing: 12) {
                        Text("\(surah.id)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 28, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(surah.fullArabicName)
                            Text("\(surah.revelationLabel) · \(QuranAccessibility.verseCount(surah.ayahCount))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if AppServices.shared.isCompletedToday(.quranSurah(surah.id)) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(QuranAccessibility.surahLabel(surah))
                }
            }
        }
    }

    private var juzList: some View {
        SwiftUI.Section {
            ForEach(1...library.juzCount, id: \.self) { juz in
                if let start = library.juzStart(juz), let surah = library.surah(start.surah) {
                    NavigationLink(value: QuranRoute(surah: start.surah, ayah: start.ayah)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("الجزء \(juz)")
                            Text("\(surah.fullArabicName)، الآية \(start.ayah)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(QuranAccessibility.juzLabel(juz, start: start, library: library))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bookmarkList: some View {
        let bookmarks = favorites.entries.compactMap { entry in QuranVerseRef(entry.ref) }.filter { library.contains($0) }
        if bookmarks.isEmpty {
            SwiftUI.Section {
                ContentUnavailableView("لا توجد علامات", systemImage: "bookmark",
                                       description: Text("اضغط مطولاً على آية واختر «إضافة علامة»."))
            }
        } else {
            SwiftUI.Section {
                ForEach(bookmarks, id: \.self) { ref in
                    if let surah = library.surah(ref.surah), let verse = library.verse(ref) {
                        NavigationLink(value: QuranRoute(surah: ref.surah, ayah: ref.ayah, highlights: true)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verse.arabicText)
                                    .font(QuranTypography.font(size: 20))
                                    .lineLimit(2)
                                Text("\(surah.fullArabicName)، الآية \(ref.ayah)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("علامة، \(surah.fullArabicName)، الآية \(ref.ayah)")
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                favorites.remove(ref.contentRef)
                            } label: {
                                Label(QuranAccessibility.bookmarkRemove, systemImage: "bookmark.slash")
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if results.isEmpty {
            SwiftUI.Section {
                ContentUnavailableView("لا توجد نتائج", systemImage: "magnifyingglass",
                                       description: Text("جرّب كلمة أخرى أو جزءاً من الآية."))
            }
        } else {
            SwiftUI.Section {
                ForEach(results) { result in
                    NavigationLink(value: QuranRoute(surah: result.surah, ayah: result.ayah ?? 1,
                                                     highlights: result.kind == .verse)) {
                        VStack(alignment: .leading, spacing: 4) {
                            if result.kind == .surah {
                                Label { Text(highlightedText("سورة " + result.matchedText, range: result.highlight.map {
                                    ($0.lowerBound + 5)..<($0.upperBound + 5) })) } icon: {
                                    Image(systemName: "book.closed").foregroundStyle(.tint)
                                }
                            } else {
                                Text(highlightedText(result.matchedText, range: result.highlight))
                                    .font(QuranTypography.font(size: 20))
                                Text("سورة \(result.surahName)، الآية \(result.ayah ?? 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(QuranAccessibility.searchResultLabel(result))
                        .accessibilityValue(result.kind == .verse ? result.matchedText : "")
                    }
                }
            } header: {
                Text(arabicResultCount(results.count))
            }
        }
    }
}
