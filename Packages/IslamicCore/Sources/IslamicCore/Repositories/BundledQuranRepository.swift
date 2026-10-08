import Foundation

/// Reads `Content/quran.json` (built from the unmodified Tanzil Uthmani text).
public actor BundledQuranRepository: QuranRepository {
    private let source: BundledContentSource
    private var cache: (surahs: [QuranSurah], verses: [[QuranVerse]])?

    public init(source: BundledContentSource = .bundled) {
        self.source = source
    }

    public func loadSurahs() async throws -> [QuranSurah] {
        try content().surahs
    }

    public func loadSurah(id: Int) async throws -> QuranSurah {
        let surahs = try content().surahs
        guard (1...surahs.count).contains(id) else { throw ContentError.notFound("surah \(id)") }
        return surahs[id - 1]
    }

    public func loadVerses(surahId: Int) async throws -> [QuranVerse] {
        let verses = try content().verses
        guard (1...verses.count).contains(surahId) else { throw ContentError.notFound("surah \(surahId)") }
        return verses[surahId - 1]
    }

    public func loadVerse(surahId: Int, ayahNumber: Int) async throws -> QuranVerse {
        let verses = try await loadVerses(surahId: surahId)
        guard (1...verses.count).contains(ayahNumber) else {
            throw ContentError.notFound("verse \(surahId):\(ayahNumber)")
        }
        return verses[ayahNumber - 1]
    }

    public func loadVerses(_ reference: QuranReference) async throws -> [QuranVerse] {
        let verses = try await loadVerses(surahId: reference.surah)
        guard reference.fromAyah >= 1, reference.fromAyah <= reference.toAyah, reference.toAyah <= verses.count else {
            throw ContentError.notFound("verses \(reference.surah):\(reference.fromAyah)-\(reference.toAyah)")
        }
        return Array(verses[(reference.fromAyah - 1)..<reference.toAyah])
    }

    private func content() throws -> (surahs: [QuranSurah], verses: [[QuranVerse]]) {
        if let cache { return cache }
        let file = try source.decode(QuranFile.self, resource: "quran")
        try requireContent(!file.surahs.isEmpty, "quran: no surahs")
        var surahs: [QuranSurah] = []
        var verses: [[QuranVerse]] = []
        for (offset, entry) in file.surahs.enumerated() {
            try requireContent(entry.id == offset + 1, "quran: surah \(entry.id) out of order")
            try requireContent(entry.ayahCount == entry.verses.count && !entry.verses.isEmpty,
                               "quran: surah \(entry.id) verse count")
            surahs.append(QuranSurah(id: entry.id, nameArabic: entry.nameArabic,
                                     nameTransliteration: entry.nameTransliteration, nameEnglish: entry.nameEnglish,
                                     ayahCount: entry.ayahCount, revelationType: entry.revelationType,
                                     revelationOrder: entry.revelationOrder, bismillah: entry.bismillah))
            verses.append(entry.verses.enumerated().map {
                QuranVerse(surahId: entry.id, ayahNumber: $0.offset + 1, arabicText: $0.element)
            })
        }
        let loaded = (surahs, verses)
        cache = loaded
        return loaded
    }
}

private struct QuranFile: Decodable {
    struct Surah: Decodable {
        let id: Int
        let nameArabic: String
        let nameTransliteration: String
        let nameEnglish: String
        let revelationType: RevelationType
        let revelationOrder: Int
        let ayahCount: Int
        let bismillah: String?
        let verses: [String]
    }
    let surahs: [Surah]
}
