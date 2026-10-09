import SwiftUI
import IslamicCore
import ContentKit
import QuranReading
import AdhkarReading
import GlobalSearch
import HisnReading

/// Saved verses (Quran bookmarks) and saved adhkar and duas, newest first.
struct FavoritesView: View {
    @ObservedObject private var favorites = AppServices.shared.favorites
    @State private var quran: QuranLibrary?
    @State private var adhkar: AdhkarLibrary?
    @State private var hisn: HisnLibrary?

    var body: some View {
        List {
            if favorites.entries.isEmpty {
                ContentUnavailableView("لا يوجد شيء محفوظ", systemImage: "star",
                                       description: Text("احفظ آية بعلامة، أو ذكراً أو دعاءً بالنجمة، من الأذكار أو من حصن المسلم."))
            }
            ForEach(favorites.entries, id: \.ref) { entry in
                if let row = describe(entry.ref) {
                    Button {
                        AppServices.shared.router.open(entry.ref, library: adhkar)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.text)
                                .font(row.isQuran ? QuranTypography.font(size: 20) : .body)
                                .lineLimit(3)
                            Text(row.place)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.place)
                    .accessibilityValue(row.text)
                    .swipeActions {
                        Button(role: .destructive) {
                            favorites.remove(entry.ref)
                        } label: { Label("إزالة", systemImage: "trash") }
                    }
                }
            }
        }
        .navigationTitle("المفضلة")
        .task {
            quran = try? await AppServices.shared.content.quran().library
            adhkar = try? await AppServices.shared.content.adhkar().library
            hisn = (try? await BundledHisnRepository().loadBook()).map(HisnLibrary.init(book:))
        }
    }

    /// Nil for an entry whose content no longer exists (it is hidden, not deleted).
    private func describe(_ ref: ContentRef) -> (text: String, place: String, isQuran: Bool)? {
        switch ref.kind {
        case .quran:
            guard let verseRef = QuranVerseRef(ref), let verse = quran?.verse(verseRef),
                  let surah = quran?.surah(verseRef.surah) else { return nil }
            return (verse.arabicText, "\(surah.fullArabicName)، الآية \(verseRef.ayah)", true)
        case .adhkar, .dua:
            guard let found = adhkar?.locate(ref) else { return nil }
            let item = found.collection.items[found.index]
            return (item.text, found.collection.title, item.reviewStatus == .quranVerbatimTanzil)
        case .hisn:
            guard let found = hisn?.locate(itemId: ref.id) else { return nil }
            return (found.chapter.items[found.itemIndex].arabicText, "حصن المسلم: \(found.chapter.titleArabic)", false)
        }
    }
}
