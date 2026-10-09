import SwiftUI
import WidgetKit
import CoreLocation
import ContentKit
import PrayerTimes

struct NextPrayerEntry: TimelineEntry {
    enum Content {
        case prayer(PrayerMoment, place: String, timeZone: TimeZone, twentyFourHour: Bool, notice: PrayerPlaceNotice?)
        /// The App Group cannot be read in this installation.
        case unavailable
        /// No place saved in the app yet.
        case noPlace
        /// A city was chosen in the widget, but no method is known for it.
        case needsMethod(place: String)
        /// «موقعي الحالي» was chosen, but the location is not allowed for widgets.
        case locationNotAllowed
        /// «موقعي الحالي» was chosen, but no location could be read just now.
        case locationUnavailable
        /// The sun does not rise or set there today.
        case noTimes(place: String)
    }

    let date: Date
    let content: Content
}

struct NextPrayerProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NextPrayerEntry {
        NextPrayerEntry(date: Date(), content: .noPlace)
    }

    func snapshot(for configuration: NextPrayerConfiguration, in context: Context) async -> NextPrayerEntry {
        await entries(configuration, from: Date(), limit: 1).first ?? placeholder(in: context)
    }

    /// One entry each time what is shown changes (each prayer and sunrise, and local midnight).
    /// The countdown in between is drawn by the system from the next prayer's date.
    func timeline(for configuration: NextPrayerConfiguration, in context: Context) async -> Timeline<NextPrayerEntry> {
        let now = Date()
        let entries = await entries(configuration, from: now, limit: 16)
        switch entries.last?.content {
        case .prayer where configuration.usesCurrentLocation:
            // The device may move: read the location again within the hour.
            return Timeline(entries: entries, policy: .after(min(entries.last?.date ?? now, now.addingTimeInterval(3600))))
        case .prayer:
            return Timeline(entries: entries, policy: .atEnd)
        case .locationUnavailable:
            return Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60)))
        case .noTimes:
            return Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600)))
        default:
            // The app reloads the widget when a place is chosen; editing the widget reloads it too.
            return Timeline(entries: entries, policy: .never)
        }
    }

    private func entries(_ configuration: NextPrayerConfiguration, from now: Date, limit: Int) async -> [NextPrayerEntry] {
        var location: CLLocation?
        if configuration.usesCurrentLocation {
            switch await WidgetLocation.read() {
            case .location(let reading): location = reading
            case .notAllowed: return [NextPrayerEntry(date: now, content: .locationNotAllowed)]
            case .unavailable: return [NextPrayerEntry(date: now, content: .locationUnavailable)]
            }
        }
        switch NextPrayerWidgetState.resolve(store: WidgetSettings.prayerStore(),
                                             choice: configuration.choice(currentLocation: location),
                                             deviceTimeZone: .current, now: now, limit: limit) {
        case .sharedSettingsUnavailable:
            return [NextPrayerEntry(date: now, content: .unavailable)]
        case .noPlace:
            return [NextPrayerEntry(date: now, content: .noPlace)]
        case .needsMethod(let place):
            return [NextPrayerEntry(date: now, content: .needsMethod(place: place))]
        case .noTimes(let place):
            return [NextPrayerEntry(date: now, content: .noTimes(place: place))]
        case let .moments(moments, place, zone, twentyFourHour, notice):
            return moments.map {
                NextPrayerEntry(date: $0.date, content: .prayer($0, place: place, timeZone: zone,
                                                                twentyFourHour: twentyFourHour, notice: notice))
            }
        }
    }
}

struct NextPrayerWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "NextPrayer", intent: NextPrayerConfiguration.self, provider: NextPrayerProvider()) { entry in
            NextPrayerView(entry: entry)
        }
        .configurationDisplayName("الصلاة القادمة")
        .description("الصلاة القادمة ووقتها والوقت المتبقي، للمكان المحفوظ في التطبيق أو لمدينة تختارها من «تعديل الودجة».")
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
        case let .prayer(moment, place, zone, twentyFourHour, notice):
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
                    Text(placeLine(place, notice)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            case .systemMedium:
                HStack(spacing: 12) {
                    summary(moment: moment, place: placeLine(place, notice), clock: clock)
                    Divider().overlay(.white.opacity(0.3))
                    dayList(moment: moment, zone: zone, twentyFourHour: twentyFourHour)
                }
                .foregroundStyle(.white)
            default:
                summary(moment: moment, place: placeLine(place, notice), clock: clock)
                    .foregroundStyle(.white)
            }
        case .noPlace:
            message("افتح التطبيق واختر مدينتك أو موقعك، أو اختر مدينة من «تعديل الودجة».")
        case .locationNotAllowed:
            message("اسمح بالموقع للودجة: الإعدادات › أذكار › الموقع › «أثناء استخدام التطبيق أو الودجات».")
        case .locationUnavailable:
            message("تعذّر تحديد موقعك الآن، وستُعاد المحاولة بعد قليل.")
        case .needsMethod(let place):
            message("اختر طريقة الحساب من «تعديل الودجة» لتظهر مواقيت \(place).")
        case .unavailable:
            // Not "no place": the app may have one, but this installation does not share it.
            message("لا تصل الودجة إلى إعدادات التطبيق في هذا التثبيت. اضغط عليها مطوّلاً، ثم «تعديل الودجة»، واختر مدينتك.")
        case .noTimes(let place):
            message("لا يمكن حساب المواقيت لـ\(place) اليوم.")
        }
    }

    /// The place, marked when the saved location may be from before travelling.
    private func placeLine(_ place: String, _ notice: PrayerPlaceNotice?) -> String {
        notice == .locationMayBeOld ? "\(place) · قد يكون الموقع قديماً" : place
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
