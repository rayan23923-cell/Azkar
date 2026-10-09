import XCTest
import CoreText
import IslamicCore
@testable import QuranReading
@testable import QuranText

/// The printed-page layout (Madina 1421H, 15 lines) cut from the bundled text.
final class QuranMushafLinesTests: XCTestCase {
    private func words(_ line: QuranMushafLine) -> [QuranMushafLine.Item] {
        if case .text(let items) = line.kind { return items }
        return []
    }

    func testLayoutLoads() throws {
        let layout = try XCTUnwrap(QuranMushafLayout.madina1421)
        XCTAssertEqual(layout.pages.count, 604)
    }

    /// Joined back, every verse's words are its bundled text, character for character; each verse
    /// ends with one end sign; the pages carry the same verses as the page metadata.
    func testLinesRebuildTheTextUnchangedAndMatchThePages() async throws {
        let library = try await QuranFixture.library()
        var wordsByVerse: [QuranVerseRef: [String]] = [:]
        var ends: [QuranVerseRef] = []
        for number in 1...604 {
            let lines = try XCTUnwrap(library.mushafLines(number), "page \(number)")
            XCTAssertEqual(lines.count, number <= 2 ? 8 : 15, "page \(number)")
            var onPage: [QuranVerseRef] = []
            for line in lines {
                for item in words(line) {
                    if onPage.last != item.verse { onPage.append(item.verse) }
                    switch item.kind {
                    case .word(let word): wordsByVerse[item.verse, default: []].append(word)
                    case .verseEnd: ends.append(item.verse)
                    }
                }
            }
            let page = try XCTUnwrap(library.mushafPage(number))
            let expected = page.sections.flatMap { $0.verses.map { QuranVerseRef(surah: $0.surahId, ayah: $0.ayahNumber) } }
            XCTAssertEqual(onPage, expected, "page \(number)")
        }
        XCTAssertEqual(ends.count, QuranLibrary.verseCount)
        XCTAssertEqual(ends, ends.sorted())
        for surah in library.surahs {
            for verse in library.verses(of: surah.id) {
                let ref = QuranVerseRef(surah: verse.surahId, ayah: verse.ayahNumber)
                XCTAssertEqual(wordsByVerse[ref]?.joined(separator: " "), verse.arabicText, "\(ref)")
            }
        }
    }

    /// Titles and basmalas: 114 titles, a basmala after each except At-Tawbah's and Al-Fatiha's
    /// (where it is the first verse).
    func testTitlesAndBasmalas() async throws {
        let library = try await QuranFixture.library()
        var titles: [Int] = []
        var basmalas = 0
        for number in 1...604 {
            for line in try XCTUnwrap(library.mushafLines(number)) {
                switch line.kind {
                case .surahTitle(let surah): titles.append(surah.id)
                case .basmala(let text):
                    basmalas += 1
                    XCTAssertEqual(text, library.surah(2)?.bismillah)
                case .text: break
                }
            }
        }
        XCTAssertEqual(titles, Array(1...114))
        XCTAssertEqual(basmalas, 112)
    }

    /// Page 305 as printed: Maryam's title, the basmala, then 13 lines ending with verse 11.
    func testMaryamPage() async throws {
        let library = try await QuranFixture.library()
        let lines = try XCTUnwrap(library.mushafLines(305))
        XCTAssertEqual(lines[0].kind, .surahTitle(try XCTUnwrap(library.surah(19))))
        if case .basmala = lines[1].kind {} else { XCTFail("basmala") }
        let first = words(lines[2])
        XCTAssertEqual(first.first?.verse, QuranVerseRef(surah: 19, ayah: 1))
        XCTAssertEqual(first.filter { $0.kind == .verseEnd }.map(\.verse.ayah), [1, 2])
        XCTAssertEqual(first.last?.kind, .word("إِذْ"))
        let last = words(lines[14])
        XCTAssertEqual(last.last, QuranMushafLine.Item(kind: .verseEnd, verse: QuranVerseRef(surah: 19, ayah: 11)))
    }

    /// A page that opens with the basmala of a surah titled at the foot of the page before.
    func testBasmalaCarriedOverAPageBreak() async throws {
        let library = try await QuranFixture.library()
        let before = try XCTUnwrap(library.mushafLines(76))
        XCTAssertEqual(before.last?.kind, .surahTitle(try XCTUnwrap(library.surah(4))))
        let after = try XCTUnwrap(library.mushafLines(77))
        if case .basmala = after[0].kind {} else { XCTFail("basmala") }
        XCTAssertEqual(words(after[1]).first?.verse, QuranVerseRef(surah: 4, ayah: 1))
    }

    func testWordsKeepPauseMarksWithTheirWord() {
        XCTAssertEqual(QuranMushafLayout.words(of: "وَٱلصَّلَوٰةِ ۚ وَإِنَّهَا"), ["وَٱلصَّلَوٰةِ ۚ", "وَإِنَّهَا"])
        XCTAssertEqual(QuranMushafLayout.words(of: "۞ وَقَالَ ٱرْكَبُوا۟"), ["۞ وَقَالَ", "ٱرْكَبُوا۟"])
    }

    func testPageFontRegistersAndCoversTheText() async throws {
        XCTAssertTrue(MushafFont.register())
        let font = try XCTUnwrap(MushafFont.font(size: 20))
        XCTAssertEqual(CTFontCopyPostScriptName(font) as String, MushafFont.postScriptName)
        let licence = try String(contentsOf: try XCTUnwrap(MushafFont.licenseURL), encoding: .utf8)
        XCTAssertTrue(licence.contains("SIL Open Font License"))

        let library = try await QuranFixture.library()
        var text = "\u{06DD}٠١٢٣٤٥٦٧٨٩"
        for surah in library.surahs {
            text += surah.bismillah ?? ""
            for verse in library.verses(of: surah.id) { text += verse.arabicText }
        }
        XCTAssertEqual(MushafFont.missingCharacters(in: text), [])
    }

    func testDisplayOnlyMapsTheTwoMarksTheFontSpellsDifferently() {
        XCTAssertEqual(MushafFont.display("مَجْر\u{06EA}ىٰهَا"), "مَجْر\u{065C}ىٰهَا")
        XCTAssertEqual(MushafFont.display("تَأْمَ\u{06EB}نَّا"), "تَأْمَ\u{06EC}نَّا")
        XCTAssertEqual(MushafFont.display("بِسْمِ ٱللَّهِ"), "بِسْمِ ٱللَّهِ")
    }
}
