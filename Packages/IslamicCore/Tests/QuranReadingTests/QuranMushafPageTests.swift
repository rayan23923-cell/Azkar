import XCTest
import IslamicCore
@testable import QuranReading

final class QuranMushafPageTests: XCTestCase {
    func testEveryVerseIsOnExactlyOnePageInOrder() async throws {
        let library = try await QuranFixture.library()
        var seen: [QuranVerseRef] = []
        for number in 1...library.pageCount {
            let page = try XCTUnwrap(library.mushafPage(number), "page \(number)")
            XCTAssertEqual(page.number, number)
            XCTAssertEqual(page.firstVerse, library.pageStart(number))
            for section in page.sections {
                XCTAssertFalse(section.verses.isEmpty)
                for verse in section.verses {
                    XCTAssertEqual(verse.surahId, section.surah.id)
                    let ref = QuranVerseRef(surah: verse.surahId, ayah: verse.ayahNumber)
                    XCTAssertEqual(library.page(of: ref), number, "\(ref)")
                    seen.append(ref)
                }
            }
        }
        XCTAssertEqual(seen.count, QuranLibrary.verseCount)
        XCTAssertEqual(seen, seen.sorted())
        XCTAssertNil(library.mushafPage(0))
        XCTAssertNil(library.mushafPage(605))
    }

    func testTheTextIsTheBundledTextUnchanged() async throws {
        let library = try await QuranFixture.library()
        let page = try XCTUnwrap(library.mushafPage(305))
        for verse in page.sections.flatMap(\.verses) {
            XCTAssertEqual(verse, library.verse(QuranVerseRef(surah: verse.surahId, ayah: verse.ayahNumber)))
        }
    }

    func testKnownPages() async throws {
        let library = try await QuranFixture.library()

        let first = try XCTUnwrap(library.mushafPage(1))
        XCTAssertEqual(first.sections.map(\.surah.id), [1])
        XCTAssertEqual(first.verseCount, 7)
        XCTAssertTrue(first.sections[0].startsSurah)
        XCTAssertTrue(first.sections[0].endsSurah)

        // Maryam begins on page 305, verses 1 to 11, in juz 16.
        let maryam = try XCTUnwrap(library.mushafPage(305))
        XCTAssertEqual(maryam.sections.map(\.surah.id), [19])
        XCTAssertEqual(maryam.sections[0].verses.map(\.ayahNumber), Array(1...11))
        XCTAssertTrue(maryam.sections[0].startsSurah)
        XCTAssertEqual(maryam.juz, 16)
        XCTAssertEqual(maryam.surahName, "مريم")
        XCTAssertEqual(QuranMushafNames.juz(maryam.juz), "الجزء السادس عشر")

        let last = try XCTUnwrap(library.mushafPage(604))
        XCTAssertEqual(last.sections.map(\.surah.id), [112, 113, 114])
        XCTAssertTrue(last.sections.allSatisfy { $0.startsSurah && $0.endsSurah })
        XCTAssertEqual(last.surahName, "الناس")
        XCTAssertTrue(last.contains(QuranVerseRef(surah: 114, ayah: 6)))
        XCTAssertFalse(last.contains(QuranVerseRef(surah: 111, ayah: 5)))
    }

    func testNamesAndDigits() {
        XCTAssertEqual(QuranMushafNames.juz(1), "الجزء الأول")
        XCTAssertEqual(QuranMushafNames.juz(21), "الجزء الحادي والعشرون")
        XCTAssertEqual(QuranMushafNames.juz(30), "الجزء الثلاثون")
        XCTAssertEqual(QuranMushafNames.digits(305), "٣٠٥")
        XCTAssertEqual(QuranMushafNames.verseEnd(12), "\u{06DD}١٢")
    }
}
