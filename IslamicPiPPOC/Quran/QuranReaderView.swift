import SwiftUI
import UIKit
import IslamicCore
import ContentKit
import QuranReading
import QuranText
import HisnReading
import HisnShareCard
import PiPProviders

/// One surah, verse after verse, in the Quran font. Tracks the verse at the top of the screen
/// and saves it when the reader leaves or the app goes to the background.
struct QuranReaderView: View {
    @StateObject private var controller: QuranReaderController
    @ObservedObject private var favorites = AppServices.shared.favorites
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isPresented) private var isPresented
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("quran.textSize") private var textSize: Double = 26
    @State private var scrolledAyah: Int?
    @State private var highlightedAyah: Int?
    @State private var sharePayload: HisnSharePayload?
    @State private var notice: String?
    @State private var showsGoTo = false
    /// Made on first appearance, on this screen's controller.
    @State private var pip: ReaderPiP?

    /// `start` must be a verse of `library` (checked by the caller). The controller is made
    /// once per screen; it saves the start verse as the reading position.
    init(library: QuranLibrary, start: QuranVerseRef, store: QuranPositionStore, highlightedAyah: Int?) {
        _controller = StateObject(wrappedValue: QuranReaderController(library: library, start: start, store: store,
                                                                      dailyProgress: AppServices.shared.dailyProgress)!)
        _highlightedAyah = State(initialValue: highlightedAyah)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                ForEach(controller.verses) { verse in
                    verseRow(verse)
                        .id(verse.ayahNumber)
                        .onAppear {
                            if verse.ayahNumber == controller.surah.ayahCount { controller.reachedEnd() }
                        }
                }
                footer
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrolledAyah, anchor: .top)
        .id(controller.surah.id)
        .navigationTitle(controller.surah.fullArabicName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if let pip {
                    PiPEntryView(pip: pip, startTitle: "تشغيل في نافذة عائمة")
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.bar)
                }
                positionBar
            }
        }
        .transientNotice($notice)
        .sheet(item: $sharePayload) { payload in ActivityShareSheet(items: payload.items) }
        .sheet(isPresented: $showsGoTo) {
            QuranGoToView(surah: controller.surah) { ayah in
                if controller.go(to: ayah) { highlightedAyah = ayah }
            }
            .presentationDetents([.medium])
        }
        .onAppear {
            scrolledAyah = controller.currentAyah
            if pip == nil { pip = ReaderPiP(provider: QuranPiPProvider(controller: controller)) }
        }
        .onChange(of: scrolledAyah) { _, ayah in
            if let ayah { controller.visible(ayah: ayah) }
        }
        .onChange(of: controller.scrollRequest) {
            withAnimation(reduceMotion ? nil : .default) { scrolledAyah = controller.currentAyah }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { controller.persist() }
        }
        .onDisappear {
            controller.persist()
            // Closed (not another tab): its PiP closes too.
            if !isPresented { pip?.screenClosed() }
        }
        .task(id: highlightedAyah) {
            guard highlightedAyah != nil else { return }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) { highlightedAyah = nil }
        }
    }

    // MARK: Parts

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 8) {
            Text(controller.surah.fullArabicName)
                .font(.title2.bold())
            Text("\(controller.surah.revelationLabel) · \(QuranAccessibility.verseCount(controller.surah.ayahCount))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let bismillah = controller.surah.bismillah {
                Text(bismillah)
                    .font(QuranTypography.font(size: textSize))
                    .padding(.top, 8)
                    .accessibilityLabel(bismillah)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func verseRow(_ verse: QuranVerse) -> some View {
        let ref = QuranVerseRef(surah: verse.surahId, ayah: verse.ayahNumber)
        let bookmarked = favorites.contains(ref.contentRef)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(arabicIndicDigits(verse.ayahNumber))
                    .font(.footnote.bold())
                    .foregroundStyle(.tint)
                    .frame(minWidth: 30, minHeight: 30)
                    .background(Circle().strokeBorder(.tint.opacity(0.5)))
                if bookmarked {
                    Image(systemName: "bookmark.fill").foregroundStyle(.tint).font(.footnote)
                }
                Spacer()
                Menu {
                    actions(for: verse, bookmarked: bookmarked)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("خيارات الآية \(verse.ayahNumber)")
            }
            Text(verse.arabicText)
                .font(QuranTypography.font(size: textSize))
                .lineSpacing(textSize * 0.45)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(highlightedAyah == verse.ayahNumber ? Color.accentColor.opacity(0.14) : .clear)
        .overlay(alignment: .bottom) { Divider().padding(.horizontal, 20) }
        .contextMenu { actions(for: verse, bookmarked: bookmarked) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(QuranAccessibility.verseLabel(verse.ayahNumber) + (bookmarked ? "، عليها علامة" : ""))
        .accessibilityValue(verse.arabicText)
        .accessibilityActions { actions(for: verse, bookmarked: bookmarked) }
    }

    @ViewBuilder
    private func actions(for verse: QuranVerse, bookmarked: Bool) -> some View {
        let share = QuranShareContent(verse: verse, surah: controller.surah)
        let ref = QuranVerseRef(surah: verse.surahId, ayah: verse.ayahNumber)
        Button {
            UIPasteboard.general.string = share.copyText
            SystemHisnHaptics.shared.play(.copied)
            showNotice("نُسخت الآية", in: $notice)
        } label: { Label(QuranAccessibility.copyVerse, systemImage: "doc.on.doc") }
        Button {
            sharePayload = HisnSharePayload(items: [share.copyText])
        } label: { Label(QuranAccessibility.shareVerse, systemImage: "square.and.arrow.up") }
        Button {
            shareImage(share)
        } label: { Label(QuranAccessibility.shareVerseImage, systemImage: "photo") }
        Button {
            let added = favorites.toggle(ref.contentRef)
            showNotice(added ? "أُضيفت العلامة" : "أُزيلت العلامة", in: $notice)
        } label: {
            Label(bookmarked ? QuranAccessibility.bookmarkRemove : QuranAccessibility.bookmarkAdd,
                  systemImage: bookmarked ? "bookmark.slash" : "bookmark")
        }
    }

    private func shareImage(_ share: QuranShareContent) {
        let content = ShareCardContent(header: "القرآن الكريم", title: share.reference, body: share.text,
                                       bodyFontName: QuranFont.postScriptName, bodyLineHeight: 1.9)
        guard QuranFont.register(),
              let card = HisnShareCardRenderer.render(content, appearance: .init(colorScheme)) else {
            showNotice("تعذّر إنشاء الصورة", in: $notice)
            return
        }
        SystemHisnHaptics.shared.play(.cardReady)
        sharePayload = HisnSharePayload(items: [UIImage(cgImage: card.image)])
    }

    /// Previous surah on the right, next on the left, as Arabic reads.
    @ViewBuilder
    private var footer: some View {
        HStack {
            if let previous = controller.previousSurah {
                Button {
                    controller.open(surah: previous.id)
                } label: { Label("السابقة: \(previous.fullArabicName)", systemImage: "chevron.backward") }
            }
            Spacer()
            if let next = controller.nextSurah {
                Button {
                    controller.open(surah: next.id)
                } label: { Label("التالية: \(next.fullArabicName)", systemImage: "chevron.forward") }
            }
        }
        .buttonStyle(.bordered)
        .font(.footnote)
        .padding(20)
    }

    private var positionBar: some View {
        VStack(spacing: 4) {
            ProgressView(value: controller.progress)
                .accessibilityHidden(true)
            Text("الآية \(controller.currentAyah) من \(controller.surah.ayahCount) · الجزء \(controller.juz) · الصفحة \(controller.page)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(QuranAccessibility.position(controller))
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { showsGoTo = true } label: { Image(systemName: "number") }
                .accessibilityLabel("الانتقال إلى آية")
            Menu {
                Button { textSize = min(44, textSize + 2) } label: { Label("تكبير الخط", systemImage: "plus.magnifyingglass") }
                    .disabled(textSize >= 44)
                Button { textSize = max(18, textSize - 2) } label: { Label("تصغير الخط", systemImage: "minus.magnifyingglass") }
                    .disabled(textSize <= 18)
            } label: { Image(systemName: "textformat.size") }
            .accessibilityLabel("حجم الخط")
        }
    }
}

/// Picks an ayah of the open surah.
private struct QuranGoToView: View {
    let surah: QuranSurah
    let go: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var ayah: Int? {
        let western = text.map { ch -> Character in
            if let value = ch.wholeNumberValue { return Character(String(value)) }
            return ch
        }
        guard let number = Int(String(western)), (1...surah.ayahCount).contains(number) else { return nil }
        return number
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("رقم الآية (1 إلى \(surah.ayahCount))", text: $text)
                    .keyboardType(.numberPad)
                    .accessibilityLabel("رقم الآية")
                if !text.isEmpty && ayah == nil {
                    Text("أدخل رقماً من 1 إلى \(surah.ayahCount).")
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(surah.fullArabicName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("انتقال") {
                        if let ayah { go(ayah); dismiss() }
                    }
                    .disabled(ayah == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
