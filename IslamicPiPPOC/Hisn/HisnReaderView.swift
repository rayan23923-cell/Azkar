import SwiftUI
import IslamicCore
import HisnReading

/// One chapter: the item text, its source on demand, the repetition counter and
/// previous / next. Ends in a completion state; never opens another chapter by itself.
struct HisnReaderView: View {
    @StateObject private var screen: HisnReaderScreenModel
    private let nextSection: HisnSectionEntry?
    private let openSection: (HisnSectionEntry) -> Void

    /// - Parameters:
    ///   - nextSection: the section after this one, offered as «الفصل التالي» on completion.
    ///   - openSection: opens it (the reader never changes chapter by itself).
    init(reader: HisnReader, store: HisnReadingPositionStore, audioRepository: HisnAudioRepository,
         nextSection: HisnSectionEntry? = nil, openSection: @escaping (HisnSectionEntry) -> Void = { _ in }) {
        _screen = StateObject(wrappedValue: HisnReaderScreenModel(reader: reader, store: store,
                                                                  audioRepository: audioRepository))
        self.nextSection = nextSection
        self.openSection = openSection
    }

    var body: some View {
        HisnReaderContent(model: screen.controller, screen: screen, nextSection: nextSection,
                          openSection: openSection)
    }
}

private struct HisnReaderContent: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var model: HisnReaderController
    let screen: HisnReaderScreenModel
    let nextSection: HisnSectionEntry?
    let openSection: (HisnSectionEntry) -> Void
    @AppStorage(HisnSettings.hapticsKey) private var hapticsEnabled = true

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
        .sensoryFeedback(.impact(weight: .light), trigger: model.recitations) { _, _ in hapticsEnabled }
        .sensoryFeedback(.success, trigger: model.reader.isCompleted) { _, completed in hapticsEnabled && completed }
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
                    Text("اضغط بعد كل قراءة")
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
