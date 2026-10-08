import XCTest
import CoreText
import IslamicCore
import QuranText
@testable import HisnShareCard

/// Phase 4A/4B: a verse card uses the Quran font and draws the whole verse.
final class QuranShareCardTests: XCTestCase {
    private func verse(_ surah: Int, _ ayah: Int) async throws -> (QuranSurah, QuranVerse) {
        let repository = BundledQuranRepository()
        return (try await repository.loadSurah(id: surah), try await repository.loadVerse(surahId: surah, ayahNumber: ayah))
    }

    func testLongVerseCardIsComplete() async throws {
        XCTAssertTrue(QuranFont.register())
        let (surah, verse) = try await verse(2, 282)
        let content = ShareCardContent(header: "القرآن الكريم", title: "سورة \(surah.nameArabic)، الآية 282",
                                       body: verse.arabicText, bodyFontName: QuranFont.postScriptName, bodyLineHeight: 1.9)
        let card = try XCTUnwrap(HisnShareCardRenderer.render(content, appearance: .light))
        XCTAssertEqual(card.layout.body, verse.arabicText, "the verse is drawn as stored")
        XCTAssertEqual(card.bodyCharactersDrawn, (verse.arabicText as NSString).length)
        XCTAssertGreaterThan(card.layout.height, 2000)
        XCTAssertEqual(card.image.width, 1080)
        let runs = (CTFrameGetLines(card.bodyFrame) as? [CTLine] ?? []).flatMap { CTLineGetGlyphRuns($0) as? [CTRun] ?? [] }
        for run in runs {
            let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName as String]
            XCTAssertEqual(CTFontCopyPostScriptName(font as! CTFont) as String, QuranFont.postScriptName)
        }
    }

    func testMissingFontFailsInsteadOfSubstituting() async throws {
        let (_, verse) = try await verse(1, 1)
        let content = ShareCardContent(header: "القرآن الكريم", title: "سورة الفاتحة", body: verse.arabicText,
                                       bodyFontName: "NoSuchQuranFont-Regular")
        XCTAssertNil(HisnShareCardRenderer.render(content, appearance: .dark))
    }

    func testHisnCardIsUnchanged() {
        let content = ShareCardContent(header: "حصن المسلم", title: "باب", body: "نص")
        XCTAssertEqual(HisnShareCardRenderer.layout(content, appearance: .light).header, "حصن المسلم")
    }
}
