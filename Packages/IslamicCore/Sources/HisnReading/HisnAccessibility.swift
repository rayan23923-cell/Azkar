import Foundation
import IslamicCore

/// Arabic VoiceOver text for the reader and the index, built from reader state so it can be
/// tested without a view.
public enum HisnAccessibility {
    // MARK: Repetition control

    public static func counterLabel(_ reader: HisnReader) -> String {
        if case .counted = reader.repetition { return "العدّ" }
        return "تمّت القراءة"
    }

    public static func counterValue(_ reader: HisnReader) -> String {
        if case .counted(let completed, let total) = reader.repetition { return "التكرار \(completed) من \(total)" }
        // No stated count: nothing is announced, never a made-up total.
        return ""
    }

    public static func counterHint(_ reader: HisnReader) -> String {
        if case .counted(let completed, let total) = reader.repetition {
            return total - completed == 1
                ? (reader.isLastItem ? "القراءة الأخيرة، تنهي الباب" : "القراءة الأخيرة، تنتقل إلى الذكر التالي")
                : "اضغط مرة بعد كل قراءة"
        }
        return reader.isLastItem ? "ينهي الباب" : "ينتقل إلى الذكر التالي"
    }

    /// "الذكر n من m".
    public static func itemPosition(_ reader: HisnReader) -> String {
        "الذكر \(reader.itemNumber) من \(reader.itemCount)"
    }

    // MARK: Item actions

    public static let actionsMenu = "إجراءات الذكر"
    public static let copyAction = "نسخ الذكر"
    public static let shareAction = "مشاركة الذكر"
    public static let shareImageAction = "مشاركة الذكر كصورة"
    public static let copied = "تم النسخ"
    public static let cardFailed = "تعذّر إنشاء الصورة"

    // MARK: Index

    /// "الباب 27، أذكار الصباح، قسم الصباح": the canonical number, the title, and the half of
    /// chapter 27 when it is one.
    public static func sectionLabel(_ entry: HisnSectionEntry) -> String {
        var parts: [String] = []
        if let number = entry.bookChapterNumber { parts.append("الباب \(number)") }
        parts.append(entry.title)
        switch entry.timeOfDay {
        case .morning: parts.append("قسم الصباح")
        case .evening: parts.append("قسم المساء")
        case nil: break
        }
        return parts.joined(separator: "، ")
    }

    public static func sectionValue(_ entry: HisnSectionEntry, isCurrent: Bool) -> String {
        let count = "عدد الأذكار \(entry.itemCount)"
        return isCurrent ? "موضع القراءة الحالي، \(count)" : count
    }
}
