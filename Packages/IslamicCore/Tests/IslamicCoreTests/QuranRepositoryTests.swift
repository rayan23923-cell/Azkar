import XCTest
@testable import IslamicCore

final class QuranRepositoryTests: XCTestCase {
    let repository = BundledQuranRepository()

    func testHas114SurahsInOrder() async throws {
        let surahs = try await repository.loadSurahs()
        XCTAssertEqual(surahs.count, 114)
        XCTAssertEqual(surahs.map(\.id), Array(1...114))
    }

    func testHas6236Verses() async throws {
        var total = 0
        for surah in try await repository.loadSurahs() {
            let verses = try await repository.loadVerses(surahId: surah.id)
            XCTAssertEqual(verses.count, surah.ayahCount, "surah \(surah.id)")
            total += verses.count
        }
        XCTAssertEqual(total, 6236)
    }

    func testAlFatihaHasSevenVerses() async throws {
        let fatiha = try await repository.loadSurah(id: 1)
        XCTAssertEqual(fatiha.nameArabic, "الفاتحة")
        XCTAssertEqual(fatiha.ayahCount, 7)
        let verses = try await repository.loadVerses(surahId: 1)
        XCTAssertEqual(verses.count, 7)
        XCTAssertEqual(verses.first?.arabicText, "بِسْمِ ٱللَّهِ ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ")
    }

    func testFirstAndLastSurah() async throws {
        let surahs = try await repository.loadSurahs()
        XCTAssertEqual(surahs.first?.nameArabic, "الفاتحة")
        XCTAssertEqual(surahs.first?.nameTransliteration, "Al-Faatiha")
        XCTAssertEqual(surahs.last?.nameArabic, "الناس")
        XCTAssertEqual(surahs.last?.ayahCount, 6)
        XCTAssertEqual(surahs[1].ayahCount, 286)
        XCTAssertEqual(surahs[1].revelationType, .medinan)
        XCTAssertEqual(surahs[0].revelationType, .meccan)
    }

    func testVersesAreNumberedInOrder() async throws {
        for surahId in 1...114 {
            let verses = try await repository.loadVerses(surahId: surahId)
            XCTAssertEqual(verses.map(\.ayahNumber), Array(1...verses.count), "surah \(surahId)")
            XCTAssertTrue(verses.allSatisfy { $0.surahId == surahId })
        }
    }

    func testArabicIntegrityOfEveryVerseAndName() async throws {
        for surah in try await repository.loadSurahs() {
            assertArabicIntegrity(surah.nameArabic, "name \(surah.id)")
            for verse in try await repository.loadVerses(surahId: surah.id) {
                assertArabicIntegrity(verse.arabicText, verse.id)
            }
        }
    }

    func testBismillahIsSeparateFromVerseText() async throws {
        let surahs = try await repository.loadSurahs()
        XCTAssertNil(surahs[0].bismillah, "Al-Fatiha: basmala is verse 1")
        XCTAssertNil(surahs[8].bismillah, "At-Tawba has no basmala")
        XCTAssertEqual(surahs.filter { $0.bismillah != nil }.count, 112)
        let baqarah1 = try await repository.loadVerse(surahId: 2, ayahNumber: 1)
        XCTAssertEqual(baqarah1.arabicText, "الٓمٓ")
    }

    func testLoadByReference() async throws {
        let verses = try await repository.loadVerses(QuranReference(surah: 2, fromAyah: 285, toAyah: 286))
        XCTAssertEqual(verses.map(\.id), ["2:285", "2:286"])
        let kursi = try await repository.loadVerses(QuranReference(surah: 2, ayah: 255))
        XCTAssertEqual(kursi.count, 1)
    }

    func testInvalidIdsThrowNotFound() async {
        await assertNotFound { _ = try await self.repository.loadSurah(id: 0) }
        await assertNotFound { _ = try await self.repository.loadSurah(id: 115) }
        await assertNotFound { _ = try await self.repository.loadVerses(surahId: 115) }
        await assertNotFound { _ = try await self.repository.loadVerse(surahId: 1, ayahNumber: 8) }
        await assertNotFound { _ = try await self.repository.loadVerse(surahId: 1, ayahNumber: 0) }
        await assertNotFound { _ = try await self.repository.loadVerses(QuranReference(surah: 1, fromAyah: 5, toAyah: 9)) }
        await assertNotFound { _ = try await self.repository.loadVerses(QuranReference(surah: 1, fromAyah: 3, toAyah: 2)) }
    }
}

func assertNotFound(_ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
    do {
        try await body()
        XCTFail("expected notFound", file: file, line: line)
    } catch let error as ContentError {
        guard case .notFound = error else { return XCTFail("got \(error)", file: file, line: line) }
    } catch {
        XCTFail("got \(error)", file: file, line: line)
    }
}
