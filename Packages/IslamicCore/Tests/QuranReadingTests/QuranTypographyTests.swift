import XCTest
import CoreText
@testable import QuranReading
@testable import QuranText

/// Phase 4B: the bundled Quran font renders the whole Tanzil text.
final class QuranTypographyTests: XCTestCase {
    func testFontRegistersWithItsLicence() throws {
        XCTAssertTrue(QuranFont.register())
        XCTAssertTrue(QuranFont.register(), "idempotent")
        let font = try XCTUnwrap(QuranFont.font(size: 24))
        XCTAssertEqual(CTFontCopyPostScriptName(font) as String, "AmiriQuran-Regular")
        let licence = try String(contentsOf: try XCTUnwrap(QuranFont.licenseURL), encoding: .utf8)
        XCTAssertTrue(licence.contains("SIL Open Font License"))
    }

    /// Every character of every verse, surah name and basmala has a glyph in the font.
    func testFontCoversEveryCharacterOfTheQuran() async throws {
        let library = try await QuranFixture.library()
        var text = ""
        for surah in library.surahs {
            text += surah.nameArabic + (surah.bismillah ?? "")
            for verse in library.verses(of: surah.id) { text += verse.arabicText }
        }
        XCTAssertEqual(QuranFont.missingCharacters(in: text), [])
    }

    /// Shaping leaves no missing glyph, and long verses wrap without losing a character.
    func testLongVersesShapeAndWrapCompletely() async throws {
        let library = try await QuranFixture.library()
        let longest = try XCTUnwrap(library.verse(QuranVerseRef(surah: 2, ayah: 282)))
        for width in [320.0, 390.0, 700.0] {
            let result = try XCTUnwrap(QuranTextLayout.layout(longest.arabicText, size: 26, width: CGFloat(width)))
            XCTAssertEqual(result.missingGlyphs, 0)
            XCTAssertEqual(result.charactersLaidOut, (longest.arabicText as NSString).length, "width \(width)")
            XCTAssertGreaterThan(result.lineCount, 5)
        }
        // Every verse of a surah with many marks shapes with no missing glyph.
        for verse in library.verses(of: 2) {
            let result = try XCTUnwrap(QuranTextLayout.layout(verse.arabicText, size: 22, width: 360))
            XCTAssertEqual(result.missingGlyphs, 0, verse.id)
            XCTAssertEqual(result.charactersLaidOut, (verse.arabicText as NSString).length, verse.id)
        }
    }

    func testBiggerTextNeedsMoreLines() async throws {
        let library = try await QuranFixture.library()
        let verse = try XCTUnwrap(library.verse(QuranVerseRef(surah: 2, ayah: 255))).arabicText
        let small = try XCTUnwrap(QuranTextLayout.layout(verse, size: 18, width: 360))
        let large = try XCTUnwrap(QuranTextLayout.layout(verse, size: 40, width: 360))
        XCTAssertGreaterThan(large.lineCount, small.lineCount, "Dynamic Type sizes reflow")
    }
}
