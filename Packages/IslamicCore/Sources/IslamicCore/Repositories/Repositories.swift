import Foundation

public enum ContentError: Error, Equatable, Sendable {
    case resourceMissing(String)
    case unsupportedFormatVersion(Int)
    case invalidContent(String)
    case notFound(String)
}

/// Quran text and surah metadata. Implementations may be bundled (V1) or remote (later).
public protocol QuranRepository: Sendable {
    func loadSurahs() async throws -> [QuranSurah]
    func loadSurah(id: Int) async throws -> QuranSurah
    func loadVerses(surahId: Int) async throws -> [QuranVerse]
    func loadVerse(surahId: Int, ayahNumber: Int) async throws -> QuranVerse
    func loadVerses(_ reference: QuranReference) async throws -> [QuranVerse]
}

public protocol DhikrRepository: Sendable {
    func loadGroups() async throws -> [DhikrGroup]
    func loadItems(group: DhikrGroup.ID) async throws -> [DhikrItem]
    func loadItem(id: String) async throws -> DhikrItem
}

public protocol DuaRepository: Sendable {
    func loadCategories() async throws -> [DuaCategory]
    func loadItems(category: DuaCategory.ID) async throws -> [DuaItem]
    func loadItem(id: String) async throws -> DuaItem
}
