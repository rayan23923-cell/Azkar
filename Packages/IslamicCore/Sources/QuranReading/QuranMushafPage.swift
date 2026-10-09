import Foundation
import IslamicCore

/// One page of the Madani mushaf (1...604): the verses the printed page carries, by the Tanzil
/// page metadata, grouped by surah. The verse text is the bundled Tanzil text, unchanged; only
/// which verses share a page comes from the layout. Line breaks within the page are not those
/// of the printed mushaf, which would need the King Fahd Complex page fonts.
public struct QuranMushafPage: Equatable, Sendable, Identifiable {
    public struct Section: Equatable, Sendable {
        public let surah: QuranSurah
        public let verses: [QuranVerse]
        /// The surah begins on this page: its title band (and basmala, when it has one) comes first.
        public var startsSurah: Bool { verses.first?.ayahNumber == 1 }
        /// The surah's last verse is on this page.
        public var endsSurah: Bool { verses.last?.ayahNumber == surah.ayahCount }
    }

    public let number: Int
    public let juz: Int
    public let sections: [Section]

    public var id: Int { number }
    public var firstVerse: QuranVerseRef {
        QuranVerseRef(surah: sections[0].surah.id, ayah: sections[0].verses[0].ayahNumber)
    }
    /// The surah named at the top of the page: the one the page ends in, as printed mushafs do.
    public var surahName: String { sections[sections.count - 1].surah.nameArabic }
    public var verseCount: Int { sections.reduce(0) { $0 + $1.verses.count } }

    public func contains(_ ref: QuranVerseRef) -> Bool {
        sections.contains { section in
            section.surah.id == ref.surah && section.verses.contains { $0.ayahNumber == ref.ayah }
        }
    }
}

public extension QuranLibrary {
    /// The first verse of a page; nil outside 1...604.
    func pageStart(_ page: Int) -> QuranVerseRef? {
        QuranMetadata.pageStarts.indices.contains(page - 1) ? QuranMetadata.pageStarts[page - 1] : nil
    }

    /// A page's verses, from its first verse up to the next page's first verse.
    func mushafPage(_ number: Int) -> QuranMushafPage? {
        guard var ref = pageStart(number) else { return nil }
        let end = pageStart(number + 1)
        var sections: [QuranMushafPage.Section] = []
        var current: [QuranVerse] = []
        while ref != end, let item = self.verse(ref) {
            if let last = current.last, last.surahId != item.surahId, let owner = self.surah(last.surahId) {
                sections.append(.init(surah: owner, verses: current))
                current = []
            }
            current.append(item)
            guard let next = self.verse(after: ref) else { break }
            ref = next
        }
        if let last = current.last, let owner = self.surah(last.surahId) {
            sections.append(.init(surah: owner, verses: current))
        }
        guard !sections.isEmpty, let first = sections.first?.verses.first else { return nil }
        return QuranMushafPage(number: number, juz: juz(of: QuranVerseRef(surah: first.surahId, ayah: first.ayahNumber)),
                               sections: sections)
    }
}

/// Names written on mushaf pages.
public enum QuranMushafNames {
    private static let juzOrdinals = [
        "الأول", "الثاني", "الثالث", "الرابع", "الخامس", "السادس", "السابع", "الثامن", "التاسع", "العاشر",
        "الحادي عشر", "الثاني عشر", "الثالث عشر", "الرابع عشر", "الخامس عشر", "السادس عشر", "السابع عشر",
        "الثامن عشر", "التاسع عشر", "العشرون", "الحادي والعشرون", "الثاني والعشرون", "الثالث والعشرون",
        "الرابع والعشرون", "الخامس والعشرون", "السادس والعشرون", "السابع والعشرون", "الثامن والعشرون",
        "التاسع والعشرون", "الثلاثون",
    ]

    /// «الجزء السادس عشر».
    public static func juz(_ juz: Int) -> String {
        juzOrdinals.indices.contains(juz - 1) ? "الجزء \(juzOrdinals[juz - 1])" : "الجزء \(juz)"
    }

    /// Eastern Arabic digits, as printed: 305 → «٣٠٥».
    public static func digits(_ number: Int) -> String {
        String(String(number).map { ch -> Character in
            guard let value = ch.wholeNumberValue, let scalar = UnicodeScalar(0x0660 + value) else { return ch }
            return Character(scalar)
        })
    }

    /// The end-of-verse sign with its number (U+06DD then the digits), which the Quran font
    /// draws as one ornament.
    public static func verseEnd(_ ayah: Int) -> String { "\u{06DD}" + digits(ayah) }
}
