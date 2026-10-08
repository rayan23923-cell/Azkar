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

    public static func sectionValue(_ entry: HisnSectionEntry, isCurrent: Bool, completedToday: Bool = false) -> String {
        var parts: [String] = []
        if isCurrent { parts.append("موضع القراءة الحالي") }
        if completedToday { parts.append(completedTodayLabel) }
        parts.append("عدد الأذكار \(entry.itemCount)")
        return parts.joined(separator: "، ")
    }

    /// A section read to the end today.
    public static let completedTodayLabel = "أُتمّ اليوم"

    // MARK: Search

    public static let searchField = "بحث في حصن المسلم"
    public static let clearSearch = "مسح البحث"
    public static let searchFilter = "نوع النتائج"

    public static func filterTitle(_ filter: HisnSearchFilter) -> String {
        switch filter {
        case .all: return "الكل"
        case .chapters: return "الفصول"
        case .texts: return "النصوص"
        }
    }

    /// The result count with Arabic number agreement.
    public static func resultCount(_ count: Int) -> String {
        switch count {
        case 0: return "لا توجد نتائج"
        case 1: return "نتيجة واحدة"
        case 2: return "نتيجتان"
        case 3...10: return "\(count) نتائج"
        default: return "\(count) نتيجة"
        }
    }

    /// The result type, then where it is: "فصل، أذكار الصباح" or
    /// "ذكر، الذكر 2 من 31، أذكار الصباح".
    public static func searchResultLabel(_ result: HisnSearchResult) -> String {
        switch result.kind {
        case .chapter:
            return "فصل، \(result.chapterTitle)"
        case .item:
            let number = (result.itemIndex ?? 0) + 1
            return "ذكر، الذكر \(number) من \(result.chapterItemCount)، \(result.chapterTitle)"
        }
    }

    /// The text preview for an item; the item count for a chapter.
    public static func searchResultValue(_ result: HisnSearchResult) -> String {
        switch result.kind {
        case .chapter: return "عدد الأذكار \(result.chapterItemCount)"
        case .item: return result.matchedText
        }
    }

    public static func searchResultHint(_ result: HisnSearchResult) -> String {
        result.kind == .chapter ? "يفتح الفصل" : "يفتح الذكر في موضعه"
    }
}
