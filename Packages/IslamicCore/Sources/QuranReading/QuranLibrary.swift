import Foundation
import IslamicCore
import ContentKit

/// A verse position: surah 1...114, ayah 1...n.
public struct QuranVerseRef: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let surah: Int
    public let ayah: Int

    public init(surah: Int, ayah: Int) {
        self.surah = surah
        self.ayah = ayah
    }

    init(_ surah: Int, _ ayah: Int) {
        self.init(surah: surah, ayah: ayah)
    }

    public static func < (lhs: QuranVerseRef, rhs: QuranVerseRef) -> Bool {
        (lhs.surah, lhs.ayah) < (rhs.surah, rhs.ayah)
    }

    public var description: String { "\(surah):\(ayah)" }
    public var contentRef: ContentRef { .quranVerse(surah: surah, ayah: ayah) }

    /// From a `quran:s:a` reference.
    public init?(_ ref: ContentRef) {
        guard ref.kind == .quran else { return nil }
        let parts = ref.id.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        self.init(surah: parts[0], ayah: parts[1])
    }
}

/// The whole Quran as loaded from the bundled Tanzil text, with juz and page lookup from the
/// Tanzil metadata. Read-only; the verse text is never changed.
public struct QuranLibrary: Sendable {
    public let surahs: [QuranSurah]
    private let versesBySurah: [[QuranVerse]]

    public static let surahCount = 114
    public static let verseCount = 6236

    /// Returns nil unless the content is complete (114 surahs, verse counts as declared).
    public init?(surahs: [QuranSurah], verses: [[QuranVerse]]) {
        guard surahs.count == Self.surahCount, verses.count == surahs.count else { return nil }
        for (surah, list) in zip(surahs, verses) {
            guard list.count == surah.ayahCount, list.allSatisfy({ $0.surahId == surah.id }) else { return nil }
        }
        self.surahs = surahs
        self.versesBySurah = verses
    }

    public static func load(from repository: QuranRepository = BundledQuranRepository()) async throws -> QuranLibrary {
        let surahs = try await repository.loadSurahs()
        var verses: [[QuranVerse]] = []
        for surah in surahs { verses.append(try await repository.loadVerses(surahId: surah.id)) }
        guard let library = QuranLibrary(surahs: surahs, verses: verses) else {
            throw ContentError.invalidContent("quran: incomplete content")
        }
        return library
    }

    public var totalVerses: Int { versesBySurah.reduce(0) { $0 + $1.count } }

    public func surah(_ id: Int) -> QuranSurah? {
        surahs.indices.contains(id - 1) ? surahs[id - 1] : nil
    }

    public func verses(of surah: Int) -> [QuranVerse] {
        versesBySurah.indices.contains(surah - 1) ? versesBySurah[surah - 1] : []
    }

    public func verse(_ ref: QuranVerseRef) -> QuranVerse? {
        let list = verses(of: ref.surah)
        return list.indices.contains(ref.ayah - 1) ? list[ref.ayah - 1] : nil
    }

    public func contains(_ ref: QuranVerseRef) -> Bool { verse(ref) != nil }

    /// 1...30.
    public func juz(of ref: QuranVerseRef) -> Int {
        Self.index(of: ref, in: QuranMetadata.juzStarts) + 1
    }

    /// 1...604 (Madani mushaf layout).
    public func page(of ref: QuranVerseRef) -> Int {
        Self.index(of: ref, in: QuranMetadata.pageStarts) + 1
    }

    public var juzCount: Int { QuranMetadata.juzStarts.count }
    public var pageCount: Int { QuranMetadata.pageStarts.count }

    public func juzStart(_ juz: Int) -> QuranVerseRef? {
        QuranMetadata.juzStarts.indices.contains(juz - 1) ? QuranMetadata.juzStarts[juz - 1] : nil
    }

    /// The next verse in mushaf order, crossing into the next surah; nil after the last verse.
    public func verse(after ref: QuranVerseRef) -> QuranVerseRef? {
        guard let surah = surah(ref.surah) else { return nil }
        if ref.ayah < surah.ayahCount { return QuranVerseRef(surah: ref.surah, ayah: ref.ayah + 1) }
        return ref.surah < Self.surahCount ? QuranVerseRef(surah: ref.surah + 1, ayah: 1) : nil
    }

    public func verse(before ref: QuranVerseRef) -> QuranVerseRef? {
        if ref.ayah > 1 { return QuranVerseRef(surah: ref.surah, ayah: ref.ayah - 1) }
        guard ref.surah > 1, let previous = surah(ref.surah - 1) else { return nil }
        return QuranVerseRef(surah: previous.id, ayah: previous.ayahCount)
    }

    /// Last index whose start is at or before `ref`.
    private static func index(of ref: QuranVerseRef, in starts: [QuranVerseRef]) -> Int {
        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= ref { low = mid } else { high = mid - 1 }
        }
        return low
    }
}

public extension QuranSurah {
    /// «مكية» / «مدنية».
    var revelationLabel: String { revelationType == .meccan ? "مكية" : "مدنية" }
    /// «سورة البقرة».
    var fullArabicName: String { "سورة \(nameArabic)" }
}
