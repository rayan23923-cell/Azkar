import SwiftUI
import WidgetKit
import ContentKit
import PrayerTimes

struct NextPrayerEntry: TimelineEntry {
    enum Content {
        case prayer(PrayerMoment, place: String, timeZone: TimeZone, twentyFourHour: Bool)
        /// No place saved in the app yet (or no App Group in this build).
        case noPlace
        /// The sun does not rise or set there today.
        case noTimes(place: String)
    }

    let date: Date
    let content: Content
}

struct NextPrayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextPrayerEntry {
        NextPrayerEntry(date: Date(), content: .noPlace)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextPrayerEntry) -> Void) {
        completion(entries(from: Date(), limit: 1).first ?? placeholder(in: context))
    }

    /// One entry each time what is shown changes (each prayer and sunrise, and local midnight).
    /// The countdown in between is drawn by the system from the next prayer's date.
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextPrayerEntry>) -> Void) {
        let now = Date()
        let entries = entries(from: now, limit: 16)
        switch entries.last?.content {
        case .prayer:
            completion(Timeline(entries: entries, policy: .atEnd))
        case .noTimes:
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600))))
        default:
            // The app reloads the widget when a place is chosen.
            completion(Timeline(entries: entries, policy: .never))
        }
    }

    private func entries(from now: Date, limit: Int) -> [NextPrayerEntry] {
        guard let store = WidgetSettings.prayerStore(), let place = store.place, let schedule = store.schedule else {
            return [NextPrayerEntry(date: now, content: .noPlace)]
        }
        let moments = schedule.moments(from: now, limit: limit)
        guard !moments.isEmpty else { return [NextPrayerEntry(date: now, content: .noTimes(place: place.name))] }
        return moments.map {
            NextPrayerEntry(date: $0.date, content: .prayer($0, place: place.name, timeZone: schedule.timeZone,
                                                            twentyFourHour: store.twentyFourHour))
        }
    }
}

struct NextPrayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextPrayer", provider: NextPrayerProvider()) { entry in
            NextPrayerView(entry: entry)
        }
        .configurationDisplayName("الصلاة القادمة")
        .description("الصلاة القادمة ووقتها والوقت المتبقي للمكان المحفوظ في التطبيق.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

struct NextPrayerView: View {
    let entry: NextPrayerEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar"))
            .widgetURL(AppLink.prayerTimes.url)
            .containerBackground(for: .widget) {
                if family == .systemSmall || family == .systemMedium {
                    LinearGradient(colors: [Color(red: 0.07, green: 0.27, blue: 0.20), Color(red: 0.03, green: 0.16, blue: 0.12)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.content {
        case let .prayer(moment, place, zone, twentyFourHour):
            let clock = PrayerFormat.clock(moment.nextTime, timeZone: zone, twentyFourHour: twentyFourHour)
            switch family {
            case .accessoryInline:
                Label("\(moment.next.arabicName) \(clock)", systemImage: "clock")
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Text(moment.next.arabicName).font(.caption2.bold())
                    Text(clock).font(.caption2.monospacedDigit()).minimumScaleFactor(0.6)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("الصلاة القادمة \(moment.next.arabicName) الساعة \(clock)")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(moment.next.arabicName) \(clock)").font(.headline)
                    Text(timerInterval: moment.date...moment.nextTime, countsDown: true)
                        .font(.body.monospacedDigit())
                    Text(place).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            case .systemMedium:
                HStack(spacing: 12) {
                    summary(moment: moment, place: place, clock: clock)
                    Divider().overlay(.white.opacity(0.3))
                    dayList(moment: moment, zone: zone, twentyFourHour: twentyFourHour)
                }
                .foregroundStyle(.white)
            default:
                summary(moment: moment, place: place, clock: clock)
                    .foregroundStyle(.white)
            }
        case .noPlace:
            message("افتح التطبيق واختر مدينتك أو موقعك لتظهر المواقيت هنا.")
        case .noTimes(let place):
            message("لا يمكن حساب المواقيت لـ\(place) اليوم.")
        }
    }

    private func summary(moment: PrayerMoment, place: String, clock: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("الصلاة القادمة").font(.caption).opacity(0.8)
            Text(moment.next.arabicName).font(.title.bold()).minimumScaleFactor(0.7)
            Text(clock).font(.headline.monospacedDigit())
            Text(timerInterval: moment.date...moment.nextTime, countsDown: true)
                .font(.subheadline.monospacedDigit())
                .opacity(0.9)
            Spacer(minLength: 0)
            Text(place).font(.caption2).opacity(0.75).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func dayList(moment: PrayerMoment, zone: TimeZone, twentyFourHour: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Prayer.allCases, id: \.self) { prayer in
                HStack {
                    Text(prayer.arabicName)
                    Spacer()
                    Text(PrayerFormat.clock(moment.day.time(of: prayer), timeZone: zone, twentyFourHour: twentyFourHour))
                        .monospacedDigit()
                }
                .font(.caption.weight(prayer == moment.next ? .bold : .regular))
                .opacity(prayer.isPrayer ? 1 : 0.7)
            }
            Spacer(minLength: 0)
            Link(destination: AppLink.qibla.url) {
                Label("القبلة", systemImage: "location.north.line")
                    .font(.caption.bold())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(family == .accessoryInline || family == .accessoryCircular ? .caption2 : .footnote)
            .foregroundStyle(family == .systemSmall || family == .systemMedium ? Color.white : Color.primary)
            .minimumScaleFactor(0.7)
    }
}
