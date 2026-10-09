import SwiftUI
import WidgetKit
import ContentKit
import AdhkarReading

struct DailyDhikrEntry: TimelineEntry {
    struct Dhikr {
        let ref: ContentRef
        let text: String
        let source: String
        let collection: String
        let repeatCount: Int
    }

    let date: Date
    let dhikr: Dhikr?
}

struct DailyDhikrProvider: TimelineProvider {
    func placeholder(in context: Context) -> DailyDhikrEntry {
        DailyDhikrEntry(date: Date(), dhikr: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (DailyDhikrEntry) -> Void) {
        Task { completion(await entry(on: Date())) }
    }

    /// Today's dhikr until the next local midnight, then the next one.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DailyDhikrEntry>) -> Void) {
        Task {
            let now = Date()
            let entry = await entry(on: now)
            let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
            completion(Timeline(entries: [entry], policy: .after(midnight)))
        }
    }

    private func entry(on date: Date) async -> DailyDhikrEntry {
        guard let library = try? await AdhkarLibrary.load(),
              let item = DailyDhikr.item(on: DayKey(date: date), in: library) else {
            return DailyDhikrEntry(date: date, dhikr: nil)
        }
        let title = library.collection(item.collection)?.title ?? ""
        return DailyDhikrEntry(date: date, dhikr: .init(ref: item.ref, text: item.text, source: item.source,
                                                         collection: title, repeatCount: item.repeatCount))
    }
}

struct DailyDhikrWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DailyDhikr", provider: DailyDhikrProvider()) { entry in
            DailyDhikrView(entry: entry)
        }
        .configurationDisplayName("ذكر اليوم")
        .description("ذكر من أذكار التطبيق كل يوم. يفتحه في مكانه دون أن يُعدّ.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct DailyDhikrView: View {
    let entry: DailyDhikrEntry

    var body: some View {
        Group {
            if let dhikr = entry.dhikr {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("ذكر اليوم").font(.caption.bold())
                        Spacer()
                        Text(dhikr.collection).font(.caption2).opacity(0.8)
                    }
                    // The bundled text, whole: only short adhkar are chosen, so it is never cut.
                    Text(dhikr.text)
                        .font(.body)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    HStack {
                        Text(dhikr.source).font(.caption2).opacity(0.8).lineLimit(1)
                        Spacer()
                        if dhikr.repeatCount > 1 {
                            Text("التكرار: \(dhikr.repeatCount)").font(.caption2.monospacedDigit()).opacity(0.8)
                        }
                    }
                }
                .widgetURL(AppLink.content(dhikr.ref).url)
            } else {
                Text("افتح التطبيق لقراءة الأذكار.")
                    .font(.footnote)
                    .widgetURL(AppLink.home.url)
            }
        }
        .foregroundStyle(.white)
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar"))
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.07, green: 0.27, blue: 0.20), Color(red: 0.03, green: 0.16, blue: 0.12)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}
