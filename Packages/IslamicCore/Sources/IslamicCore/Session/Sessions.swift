import Foundation

/// What is being read or listened to, and where the reader is. No audio or PiP here.
public struct QuranSession: Equatable {
    public let surah: QuranSurah
    public var cursor: SessionCursor<QuranVerse>

    /// `startAyah` is 1-based. Returns nil if the verses are empty, belong to
    /// another surah, or `startAyah` is out of range.
    public init?(surah: QuranSurah, verses: [QuranVerse], startAyah: Int = 1) {
        guard verses.allSatisfy({ $0.surahId == surah.id }),
              let cursor = SessionCursor(items: verses, startIndex: startAyah - 1) else { return nil }
        self.surah = surah
        self.cursor = cursor
    }

    public var currentVerse: QuranVerse { cursor.current }
}

public struct DhikrSession: Equatable {
    public let group: DhikrGroup
    public var cursor: SessionCursor<DhikrItem>

    public init?(group: DhikrGroup, items: [DhikrItem], startIndex: Int = 0) {
        guard items.allSatisfy({ $0.group == group.id }),
              let cursor = SessionCursor(items: items, startIndex: startIndex) else { return nil }
        self.group = group
        self.cursor = cursor
    }

    public var currentItem: DhikrItem { cursor.current }
}

public struct DuaSession: Equatable {
    public let category: DuaCategory
    public var cursor: SessionCursor<DuaItem>

    public init?(category: DuaCategory, items: [DuaItem], startIndex: Int = 0) {
        guard items.allSatisfy({ $0.category == category.id }),
              let cursor = SessionCursor(items: items, startIndex: startIndex) else { return nil }
        self.category = category
        self.cursor = cursor
    }

    public var currentItem: DuaItem { cursor.current }
}
