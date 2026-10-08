import SwiftUI
import IslamicCore
import HisnReading
import HisnShareCard

/// One chapter: the item text, its source on demand, the repetition counter and
/// previous / next. Ends in a completion state; never opens another chapter by itself.
struct HisnReaderView: View {
    @StateObject private var screen: HisnReaderScreenModel
    private let nextSection: HisnSectionEntry?
    private let openSection: (HisnSectionEntry) -> Void
    private let highlightedItemId: String?

    /// - Parameters:
    ///   - highlightedItemId: the item opened from a search result, marked briefly on arrival.
    ///   - nextSection: the section after this one, offered as «الفصل التالي» on completion.
    ///   - openSection: opens it (the reader never changes chapter by itself).
    init(reader: HisnReader, store: HisnReadingPositionStore, audioRepository: HisnAudioRepository,
         highlightedItemId: String? = nil, nextSection: HisnSectionEntry? = nil,
         openSection: @escaping (HisnSectionEntry) -> Void = { _ in }) {
        _screen = StateObject(wrappedValue: HisnReaderScreenModel(reader: reader, store: store,
                                                                  audioRepository: audioRepository))
        self.nextSection = nextSection
        self.openSection = openSection
        self.highlightedItemId = highlightedItemId
    }

    var body: some View {
        HisnReaderContent(model: screen.controller, screen: screen, nextSection: nextSection,
                          openSection: openSection, highlightedItemId: highlightedItemId)
    }
}

private struct HisnReaderContent: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sharePayload: HisnSharePayload?
    @State private var notice: String?
    @ObservedObject var model: HisnReaderController
    let screen: HisnReaderScreenModel
    let nextSection: HisnSectionEntry?
    let openSection: (HisnSectionEntry) -> Void
    /// Cleared shortly after arrival; only ever marks the item it was opened on.
    @State var highlightedItemId: String?

    var body: some View {
        Group {
            if model.reader.isCompleted {
                completion
            } else {
                reading
            }
        }
        .navigationTitle(model.reader.chapter.titleArabic)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !model.reader.isCompleted {
                ToolbarItem(placement: .primaryAction) { actionsMenu }
            }
        }
        .sheet(item: $sharePayload) { payload in
            ActivityShareSheet(items: payload.items)
                .presentationDetents([.medium, .large])
        }
        .overlay(alignment: .top) {
            if let notice {
                Text(notice)
                    .font(.callout.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityHidden(true)
            }
        }
        .onDisappear { screen.close() }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the foreground: the cursor is already saved on each step; save once more
            // so the stored time is the last moment of reading.
            if phase == .background { model.persist() }
        }
        .onChange(of: model.finishedItemNumber) { _, number in
            if let number {
                UIAccessibility.post(notification: .announcement, argument: "أتممت الذكر \(number)")
            }
        }
    }

    // MARK: Item actions

    private var actionsMenu: some View {
        Menu {
            Button {
                copy()
            } label: {
                Label("نسخ", systemImage: "doc.on.doc")
            }
            .accessibilityLabel(HisnAccessibility.copyAction)
            Button {
                shareText()
            } label: {
                Label("مشاركة", systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel(HisnAccessibility.shareAction)
            Button {
                shareImage()
            } label: {
                Label("مشاركة كصورة", systemImage: "photo")
            }
            .accessibilityLabel(HisnAccessibility.shareImageAction)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(HisnAccessibility.actionsMenu)
    }

    private func copy() {
        if screen.actions.copy(model.reader.shareContent) {
            show(HisnAccessibility.copied)
        }
    }

    private func shareText() {
        guard let text = screen.actions.textPayload(model.reader.shareContent) else { return }
        sharePayload = HisnSharePayload(items: [text])
    }

    private func shareImage() {
        let card = HisnShareCardRenderer.render(model.reader.shareContent, appearance: .init(colorScheme))
        screen.actions.cardGenerated(card != nil)
        guard let card else {
            show(HisnAccessibility.cardFailed)
            return
        }
        sharePayload = HisnSharePayload(items: [UIImage(cgImage: card.image)])
    }

    /// A short notice at the top, also spoken; it goes away by itself.
    private func show(_ text: String) {
        withAnimation { notice = text }
        UIAccessibility.post(notification: .announcement, argument: text)
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation { if notice == text { notice = nil } }
        }
    }

    // MARK: Reading

    private var reading: some View {
        let reader = model.reader
        let item = reader.presentation
        return VStack(spacing: 0) {
            ProgressView(value: reader.progress)
                .accessibilityLabel("التقدم في الباب")
                .accessibilityValue(HisnAccessibility.itemPosition(reader))
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let finished = model.finishedItemNumber {
                        // The previous item's count is done and the reader moved on (the
                        // session's rule); say so instead of switching silently.
                        Label("أتممت الذكر \(finished)، وهذا الذكر التالي", systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.tint)
                    }
                    Text(item.text)
                        .font(.title2)
                        .lineSpacing(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .background {
                            // Opened from a search result: a soft mark that fades by itself.
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.accentColor.opacity(highlightedItemId == reader.currentItem.id ? 0.14 : 0))
                                .padding(-8)
                        }
                        .task(id: highlightedItemId) { await fadeHighlight() }
                    if !item.sources.isEmpty {
                        DisclosureGroup("المصدر") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(item.sources, id: \.self) { source in
                                    Text(source)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.top, 6)
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .id(reader.currentItem.id)
            controls
        }
    }

    private func fadeHighlight() async {
        guard highlightedItemId != nil else { return }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) { highlightedItemId = nil }
    }

    private var controls: some View {
        let reader = model.reader
        return VStack(spacing: 12) {
            #if HISN_AUDIO_FIXTURE
            Text(HisnAudioFixture.notice)
                .font(.caption.bold())
                .foregroundStyle(.orange)
            #endif
            if let audio = model.audio {
                HisnAudioControls(player: audio)
                HisnPiPControls(pip: screen.pip, player: audio, surface: screen.surface)
            }
            counter
            HStack {
                Button {
                    model.previous()
                } label: {
                    if compactLabels {
                        Image(systemName: "chevron.backward")
                    } else {
                        Label("السابق", systemImage: "chevron.backward")
                    }
                }
                .disabled(reader.isFirstItem)
                .accessibilityLabel("الذكر السابق")
                Spacer()
                Text("\(reader.itemNumber) / \(reader.itemCount)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(HisnAccessibility.itemPosition(reader))
                Spacer()
                Button {
                    model.next()
                } label: {
                    if compactLabels {
                        Image(systemName: "chevron.forward")
                    } else {
                        Label("التالي", systemImage: "chevron.forward")
                            .labelStyle(TrailingIconLabelStyle())
                    }
                }
                .accessibilityLabel(reader.isLastItem ? "إنهاء الباب" : "الذكر التالي")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.bar)
    }

    /// At accessibility text sizes previous / next show icons only (with their spoken labels)
    /// so the count button keeps its room.
    private var compactLabels: Bool { dynamicTypeSize.isAccessibilitySize }

    private var counter: some View {
        let reader = model.reader
        return Button {
            model.recite()
        } label: {
            VStack(spacing: 4) {
                switch reader.repetition {
                case .counted(let completed, let total):
                    Text("\(completed) / \(total)")
                        .font(.largeTitle.monospacedDigit().bold())
                    ProgressView(value: Double(completed), total: Double(total))
                        .tint(.white.opacity(0.9))
                        .frame(maxWidth: 160)
                    Text(completed + 1 == total ? "القراءة الأخيرة" : "اضغط بعد كل قراءة")
                        .font(.footnote)
                case .once, .unstated:
                    Text("تمّ")
                        .font(.title.bold())
                    Text(reader.isLastItem ? "إنهاء الباب" : "الانتقال إلى الذكر التالي")
                        .font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 88)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HisnAccessibility.counterLabel(reader))
        .accessibilityValue(HisnAccessibility.counterValue(reader))
        .accessibilityHint(HisnAccessibility.counterHint(reader))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Completion

    private var completion: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("أتممت هذا الباب")
                .font(.title2.bold())
            Text(model.reader.chapter.titleArabic)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 12) {
                Button {
                    model.restart()
                } label: {
                    Text("إعادة").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("يبدأ هذا الباب من أوله")
                if let nextSection {
                    Button {
                        openSection(nextSection)
                    } label: {
                        VStack(spacing: 2) {
                            Text("الفصل التالي")
                            Text(nextSection.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("الفصل التالي")
                    .accessibilityValue(HisnAccessibility.sectionLabel(nextSection))
                }
                Button {
                    dismiss()
                } label: {
                    Text("الفهرس").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button("الرجوع إلى آخر ذكر") {
                    model.previous()
                }
                .font(.footnote)
            }
            .controlSize(.large)
            .padding(.horizontal, 32)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Puts the icon after the title («التالي ‹» in right-to-left).
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}
