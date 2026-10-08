import Foundation
import IslamicCore
import ContentKit

/// What copy and share use for a verse: the stored Tanzil text, unchanged, and its reference
/// on its own line.
public struct QuranShareContent: Equatable, Sendable {
    public let text: String
    public let reference: String

    public init(verse: QuranVerse, surah: QuranSurah) {
        text = verse.arabicText
        reference = "\(surah.fullArabicName)، الآية \(verse.ayahNumber)"
    }

    /// The text, then the reference.
    public var copyText: String { "\(text)\n\(reference)" }
}

/// Arabic VoiceOver text for the Quran screens.
public enum QuranAccessibility {
    /// Arabic number agreement for «آية».
    public static func verseCount(_ count: Int) -> String {
        switch count {
        case 1: return "آية واحدة"
        case 2: return "آيتان"
        case 3...10: return "\(count) آيات"
        default: return "\(count) آية"
        }
    }

    /// "سورة البقرة، رقم 2، مدنية، 286 آية".
    public static func surahLabel(_ surah: QuranSurah) -> String {
        "\(surah.fullArabicName)، رقم \(surah.id)، \(surah.revelationLabel)، \(verseCount(surah.ayahCount))"
    }

    public static func verseLabel(_ ayah: Int) -> String { "الآية \(ayah)" }

    @MainActor
    public static func position(_ controller: QuranReaderController) -> String {
        "الآية \(controller.currentAyah) من \(controller.surah.ayahCount)، الجزء \(controller.juz)، الصفحة \(controller.page)"
    }

    public static func juzLabel(_ juz: Int, start: QuranVerseRef, library: QuranLibrary) -> String {
        let name = library.surah(start.surah)?.fullArabicName ?? ""
        return "الجزء \(juz)، يبدأ من \(name)، الآية \(start.ayah)"
    }

    public static func searchResultLabel(_ result: QuranSearchResult) -> String {
        switch result.kind {
        case .surah: return "سورة \(result.surahName)"
        case .verse: return "آية، سورة \(result.surahName)، الآية \(result.ayah ?? 1)"
        }
    }

    public static let bookmarkAdd = "إضافة علامة"
    public static let bookmarkRemove = "إزالة العلامة"
    public static let copyVerse = "نسخ الآية"
    public static let shareVerse = "مشاركة الآية"
    public static let shareVerseImage = "مشاركة الآية كصورة"
}
