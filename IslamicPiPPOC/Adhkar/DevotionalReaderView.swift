import SwiftUI
import UIKit
import IslamicCore
import ContentKit
import AdhkarReading
import HisnReading
import HisnShareCard
import QuranText
import PiPProviders

/// One dhikr or dua at a time with its counter. A tap on the counter says one repetition;
/// after the last, the next item opens. Saved when leaving or going to the background.
struct DevotionalReaderView: View {
    @StateObject private var reader: DevotionalReaderController
    @ObservedObject private var favorites = AppServices.shared.favorites
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isPresented) private var isPresented
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("adhkar.textSize") private var textSize: Double = 24
    /// Follows the system text size (Dynamic Type) on top of the reader's own size.
    @ScaledMetric(relativeTo: .body) private var dynamicScale: CGFloat = 1
    @State private var highlighted: Bool
    @State private var sharePayload: HisnSharePayload?
    @State private var notice: String?
    /// Made on first appearance, on this screen's reader.
    @State private var pip: ReaderPiP?

    init(collection: DevotionalCollection, start: ContentRef?, highlights: Bool) {
        // Collections are never empty (checked when the content loads).
        _reader = StateObject(wrappedValue: DevotionalReaderController(
            collection: collection, start: start, store: AppServices.shared.devotionalPositions,
            dailyProgress: AppServices.shared.dailyProgress)!)
        _highlighted = State(initialValue: highlights)
    }

    var body: some View {
        Group {
            if reader.isComplete {
                completion
            } else {
                itemView
            }
        }
        .navigationTitle(reader.collection.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .transientNotice($notice)
        .sheet(item: $sharePayload) { payload in ActivityShareSheet(items: payload.items) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { reader.persist() }
        }
        .onAppear {
            if pip == nil { pip = ReaderPiP(provider: DevotionalPiPProvider.make(controller: reader)) }
        }
        .onDisappear {
            reader.persist()
            // Closed (not another tab): its PiP closes too.
            if !isPresented { pip?.screenClosed() }
        }
        .task(id: highlighted) {
            guard highlighted else { return }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) { highlighted = false }
        }
    }

    private var isQuranText: Bool { reader.current.reviewStatus == .quranVerbatimTanzil }

    private var itemView: some View {
        let item = reader.current
        return VStack(spacing: 0) {
            ProgressView(value: reader.cursor.progress)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .accessibilityHidden(true)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(DevotionalAccessibility.itemPosition(reader.index, of: reader.count))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(item.text)
                        .font(isQuranText ? QuranTypography.font(size: textSize + 2) : .system(size: CGFloat(textSize) * dynamicScale))
                        .lineSpacing(textSize * 0.4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(highlighted ? Color.accentColor.opacity(0.14) : .clear,
                                    in: RoundedRectangle(cornerRadius: 12))
                        .textSelection(.enabled)
                        .accessibilityLabel(item.text)
                    Text(item.source)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("المصدر: \(item.source)")
                    if item.repeatCount > 1 {
                        Text("يُقال \(DevotionalAccessibility.repetitions(item.repeatCount))")
                            .font(.footnote.bold())
                            .foregroundStyle(.tint)
                    }
                }
                .padding(20)
            }
            counterBar
        }
    }

    private var counterBar: some View {
        VStack(spacing: 12) {
            if let pip {
                PiPEntryView(pip: pip)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button {
                let step = reader.recite()
                switch step {
                case .finished: SystemHisnHaptics.shared.play(.chapterCompleted)
                case .movedToNext: SystemHisnHaptics.shared.play(.itemCompleted)
                case .repeated: SystemHisnHaptics.shared.tick()
                }
            } label: {
                VStack(spacing: 4) {
                    Text("\(reader.remaining)")
                        .font(.largeTitle.monospacedDigit().bold())
                    Text(reader.remaining == 0 ? "اكتمل ✓" : reader.current.repeatCount > 1 ? "متبقٍّ" : "تمّ")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, minHeight: 88)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("عدّاد")
            .accessibilityValue(DevotionalAccessibility.remaining(reader.remaining))
            .accessibilityHint(DevotionalAccessibility.counterHint)
            HStack {
                Button {
                    reader.previous()
                } label: { Label("السابق", systemImage: "chevron.backward") }
                .disabled(reader.cursor.isFirst)
                Spacer()
                Button {
                    reader.next()
                } label: { Label("التالي", systemImage: "chevron.forward") }
                .disabled(reader.cursor.isLast)
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .background(.bar)
    }

    private var completion: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("أتممت \(reader.collection.title)")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("سُجّل إتمامها لهذا اليوم.")
                .foregroundStyle(.secondary)
            Button("البدء من جديد") { reader.restart() }
                .buttonStyle(.bordered)
        }
        .padding(32)
        .accessibilityElement(children: .contain)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !reader.isComplete {
                let item = reader.current
                let saved = favorites.contains(item.ref)
                Button {
                    let added = favorites.toggle(item.ref)
                    showNotice(added ? "أُضيف إلى المفضلة" : "أُزيل من المفضلة", in: $notice)
                } label: { Image(systemName: saved ? "star.fill" : "star") }
                .accessibilityLabel(saved ? "إزالة من المفضلة" : "إضافة إلى المفضلة")
                Menu {
                    Button {
                        UIPasteboard.general.string = shareText(item)
                        SystemHisnHaptics.shared.play(.copied)
                        showNotice("نُسخ النص", in: $notice)
                    } label: { Label("نسخ", systemImage: "doc.on.doc") }
                    Button {
                        sharePayload = HisnSharePayload(items: [shareText(item)])
                    } label: { Label("مشاركة النص", systemImage: "square.and.arrow.up") }
                    Button {
                        shareImage(item)
                    } label: { Label("مشاركة كصورة", systemImage: "photo") }
                    Divider()
                    Button { textSize = min(40, textSize + 2) } label: { Label("تكبير الخط", systemImage: "plus.magnifyingglass") }
                    Button { textSize = max(16, textSize - 2) } label: { Label("تصغير الخط", systemImage: "minus.magnifyingglass") }
                    Button { reader.restart() } label: { Label("البدء من جديد", systemImage: "arrow.counterclockwise") }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("خيارات")
            }
        }
    }

    /// The stored text, then its source on its own line.
    private func shareText(_ item: DevotionalItem) -> String { "\(item.text)\n\(item.source)" }

    private func shareImage(_ item: DevotionalItem) {
        let quran = item.reviewStatus == .quranVerbatimTanzil && QuranFont.register()
        let content = ShareCardContent(header: reader.collection.kind == .adhkar ? "الأذكار" : "الأدعية",
                                       title: reader.collection.title, body: item.text,
                                       bodyFontName: quran ? QuranFont.postScriptName : nil,
                                       bodyLineHeight: quran ? 1.9 : 1.45)
        guard let card = HisnShareCardRenderer.render(content, appearance: .init(colorScheme)) else {
            showNotice("تعذّر إنشاء الصورة", in: $notice)
            return
        }
        SystemHisnHaptics.shared.play(.cardReady)
        sharePayload = HisnSharePayload(items: [UIImage(cgImage: card.image)])
    }
}
