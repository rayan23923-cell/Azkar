import Foundation

public enum RevelationType: String, Codable, Sendable, CaseIterable {
    case meccan
    case medinan
}

public struct QuranSurah: Identifiable, Hashable, Codable, Sendable {
    /// 1...114, in mushaf order.
    public let id: Int
    public let nameArabic: String
    public let nameTransliteration: String
    public let nameEnglish: String
    public let ayahCount: Int
    public let revelationType: RevelationType
    /// Chronological order of revelation, from Tanzil metadata.
    public let revelationOrder: Int
    /// Basmala shown before the first verse. `nil` for Al-Fatiha (where it is
    /// verse 1) and At-Tawba (which has none).
    public let bismillah: String?

    public init(id: Int, nameArabic: String, nameTransliteration: String, nameEnglish: String,
                ayahCount: Int, revelationType: RevelationType, revelationOrder: Int, bismillah: String?) {
        self.id = id
        self.nameArabic = nameArabic
        self.nameTransliteration = nameTransliteration
        self.nameEnglish = nameEnglish
        self.ayahCount = ayahCount
        self.revelationType = revelationType
        self.revelationOrder = revelationOrder
        self.bismillah = bismillah
    }
}

public struct QuranVerse: Identifiable, Hashable, Codable, Sendable {
    public let surahId: Int
    public let ayahNumber: Int
    /// Tanzil Uthmani text, unmodified.
    public let arabicText: String

    public var id: String { "\(surahId):\(ayahNumber)" }

    public init(surahId: Int, ayahNumber: Int, arabicText: String) {
        self.surahId = surahId
        self.ayahNumber = ayahNumber
        self.arabicText = arabicText
    }
}

/// A run of whole verses inside one surah, e.g. Al-Baqarah 285-286.
public struct QuranReference: Hashable, Codable, Sendable {
    public let surah: Int
    public let fromAyah: Int
    public let toAyah: Int

    public init(surah: Int, fromAyah: Int, toAyah: Int) {
        self.surah = surah
        self.fromAyah = fromAyah
        self.toAyah = toAyah
    }

    public init(surah: Int, ayah: Int) {
        self.init(surah: surah, fromAyah: ayah, toAyah: ayah)
    }
}
