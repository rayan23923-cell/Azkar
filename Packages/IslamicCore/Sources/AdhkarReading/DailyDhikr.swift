import Foundation
import IslamicCore
import ContentKit

/// The dhikr of the day for the widget: one bundled dhikr, the same all day and for everyone,
/// chosen in turn from the adhkar short enough to be shown whole (the text is never cut).
///
/// Content gate: only items whose stored status is `REVIEWED` (approved by a named qualified
/// reviewer, see docs/CONTENT_REVIEW_GATE.md) are ever chosen automatically. Items still
/// `CONTENT_REVIEW_REQUIRED` are never picked, and Quranic text is left out (it is shown only
/// in the readers, with the bundled Quran font). No bundled item is `REVIEWED` yet, so today
/// the pool is empty and the widget shows a neutral placeholder. The readers still show every
/// item as before; this gate only governs what is chosen without the user asking.
/// A code gate is not scholarly review or rights clearance.
public enum DailyDhikr {
    /// Longest text, in characters, that a medium widget shows in full.
    public static let maximumLength = 160

    /// Every dhikr eligible, in a fixed order (by reference), so the day picks the same one
    /// on every device whatever order the collections load in.
    public static func pool(in library: AdhkarLibrary, maximumLength: Int = DailyDhikr.maximumLength) -> [DevotionalItem] {
        library.adhkar.flatMap(\.items)
            .filter { isEligible($0, maximumLength: maximumLength) }
            .sorted { $0.ref < $1.ref }
    }

    /// Approved for automatic display: `REVIEWED` only, never Quranic text, and short enough to
    /// show whole.
    public static func isEligible(_ item: DevotionalItem, maximumLength: Int = DailyDhikr.maximumLength) -> Bool {
        item.reviewStatus == .reviewed && item.ref.kind == .adhkar
            && !item.text.isEmpty && item.text.count <= maximumLength
    }

    /// The day's dhikr: the pool taken in turn, one a day. Nil only when nothing is eligible.
    public static func item(on day: DayKey, in library: AdhkarLibrary,
                            maximumLength: Int = DailyDhikr.maximumLength) -> DevotionalItem? {
        let pool = pool(in: library, maximumLength: maximumLength)
        guard !pool.isEmpty else { return nil }
        return pool[dayNumber(day) % pool.count]
    }

    /// Days since 2000-01-01 for the day's date (proleptic Gregorian, no time zone involved).
    static func dayNumber(_ day: DayKey) -> Int {
        // Days from civil: Howard Hinnant's algorithm, exact for every Gregorian date.
        let y = day.month <= 2 ? day.year - 1 : day.year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (day.month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day.day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        let days = era * 146_097 + doe - 719_468 // since 1970-01-01
        return max(0, days - 10_957)
    }
}
