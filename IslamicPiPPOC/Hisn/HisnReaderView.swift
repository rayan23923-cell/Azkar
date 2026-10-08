import SwiftUI
import IslamicCore
import HisnReading

/// One chapter: the item text, its source on demand, the repetition counter and
/// previous / next. Ends in a completion state; never opens another chapter by itself.
struct HisnReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: HisnReaderModel
    @AppStorage(HisnSettings.hapticsKey) private var hapticsEnabled = true

    init(reader: HisnReader, store: HisnReadingPositionStore) {
        _model = StateObject(wrappedValue: HisnReaderModel(reader: reader, store: store))
    }

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
    }

    // MARK: Reading

    private var reading: some View {
        let reader = model.reader
        let item = reader.presentation
        return VStack(spacing: 0) {
            ProgressView(value: reader.progress)
                .accessibilityLabel("التقدم في الباب")
                .accessibilityValue("الذكر \(reader.itemNumber) من \(reader.itemCount)")
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
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
            counter
            HStack {
                Button {
                    model.previous()
                } label: {
                    Label("السابق", systemImage: "chevron.backward")
                }
                .disabled(reader.isFirstItem)
                Spacer()
                Text("\(reader.itemNumber) / \(reader.itemCount)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("الذكر \(reader.itemNumber) من \(reader.itemCount)")
                Spacer()
                Button {
                    model.next()
                } label: {
                    Label("التالي", systemImage: "chevron.forward")
                        .labelStyle(TrailingIconLabelStyle())
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.bar)
    }

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
        .accessibilityLabel(counterLabel(reader))
        .accessibilityValue(counterValue(reader))
        .accessibilityHint(counterHint(reader))
        .accessibilityAddTraits(.isButton)
    }

    private func counterLabel(_ reader: HisnReader) -> String {
        if case .counted = reader.repetition { return "العدّ" }
        return "تمّت القراءة"
    }

    private func counterValue(_ reader: HisnReader) -> String {
        if case .counted(let completed, let total) = reader.repetition { return "\(completed) من \(total)" }
        return ""
    }

    private func counterHint(_ reader: HisnReader) -> String {
        if case .counted = reader.repetition { return "اضغط مرة بعد كل قراءة" }
        return reader.isLastItem ? "ينهي الباب" : "ينتقل إلى الذكر التالي"
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
