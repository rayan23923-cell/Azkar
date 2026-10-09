import Combine
import Foundation
import PiPCore
import PrayerTimes

/// The day's prayer times in PiP, so they stay in view over other apps.
///
/// - The counter line (large, clear of the system controls) is the next prayer and the time
///   left: «العصر 3:12 م · بعد 1:05». It is recomputed on every frame the window draws, so the
///   countdown follows the clock.
/// - The text is the day's six times, two a line.
/// - Skip back / forward: the previous / next day, from today to six days ahead. Play / pause
///   turns pages as in every section (the list fits one page).
/// - Nothing is counted, saved or sent: the times are computed on the device from the saved
///   place.
@MainActor
public final class PrayerPiPProvider: PiPContentProvider {
    public static let days = 7

    public private(set) var schedule: PrayerSchedule
    public private(set) var placeName: String
    private var twentyFourHour: Bool
    private let now: () -> Date
    private let subject = PassthroughSubject<Void, Never>()
    /// Days after today (0: today).
    public private(set) var dayOffset = 0

    public init(schedule: PrayerSchedule, placeName: String, twentyFourHour: Bool = false,
                now: @escaping () -> Date = Date.init) {
        self.schedule = schedule
        self.placeName = placeName
        self.twentyFourHour = twentyFourHour
        self.now = now
    }

    /// The place or settings changed: the window (if open) shows the new times at once.
    public func update(schedule: PrayerSchedule, placeName: String, twentyFourHour: Bool) {
        guard schedule != self.schedule || placeName != self.placeName || twentyFourHour != self.twentyFourHour
        else { return }
        self.schedule = schedule
        self.placeName = placeName
        self.twentyFourHour = twentyFourHour
        subject.send()
    }

    public var contentType: PiPContentType { .prayer }

    public var current: PiPContent? {
        let date = now()
        guard let day = schedule.day(containing: date, offset: dayOffset) else { return nil }
        let zone = schedule.timeZone
        let shown = Calendar(identifier: .gregorian).date(byAdding: .day, value: dayOffset, to: date) ?? date
        let next = schedule.next(after: date)
        // Two times a line (Fajr · sunrise, Dhuhr · Asr, Maghrib · Isha): the list fits a
        // landscape window on one page at a readable size.
        let entries = day.all.map {
            "\($0.prayer.arabicName) \(PrayerFormat.clock($0.time, timeZone: zone, twentyFourHour: twentyFourHour))"
        }
        let lines = stride(from: 0, to: entries.count, by: 2).map { entries[$0..<min($0 + 2, entries.count)].joined(separator: "   ·   ") }
        let detail = next.map {
            "\($0.prayer.arabicName) \(PrayerFormat.clock($0.time, timeZone: zone, twentyFourHour: twentyFourHour))"
                + "  ·  \(PrayerFormat.remaining(from: date, to: $0.time))"
        }
        let dayName = dayOffset == 0 ? "اليوم" : dayOffset == 1 ? "غداً" : PrayerFormat.gregorian(shown, timeZone: zone)
        return PiPContent(contentType: .prayer, contentID: "prayer:\(dayOffset)", containerID: "prayer:\(placeName)",
                          title: placeName,
                          subtitle: "\(dayName) · \(PrayerFormat.hijri(shown, timeZone: zone))",
                          text: lines.joined(separator: "\n"), index: dayOffset, total: Self.days, detail: detail)
    }

    public func goToPrevious() {
        guard dayOffset > 0 else { return }
        dayOffset -= 1
        subject.send()
    }

    public func goToNext() {
        guard dayOffset < Self.days - 1 else { return }
        dayOffset += 1
        subject.send()
    }

    public var playback: PiPPlaybackController? { nil }
    public var changes: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }
    public func persist() {}
}
