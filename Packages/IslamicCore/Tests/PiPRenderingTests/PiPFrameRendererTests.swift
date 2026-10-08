import CoreGraphics
import CoreText
import XCTest
import HisnReading
import IslamicCore
import PiPCore
import QuranText
@testable import PiPRendering

/// The PiP frame: Arabic right to left, the whole text on readable pages, both appearances.
final class PiPFrameRendererTests: XCTestCase {
    private static var hisn: HisnLibrary?

    private func hisnItems() async throws -> [HisnItem] {
        if Self.hisn == nil { Self.hisn = HisnLibrary(book: try await BundledHisnRepository().loadBook()) }
        return Self.hisn!.book.chapters.flatMap(\.items)
    }

    private func longestHisnText() async throws -> String {
        let items = try await hisnItems()
        return try XCTUnwrap(items.max { $0.arabicText.count < $1.arabicText.count }?.arabicText)
    }

    private func verse(_ surah: Int, _ ayah: Int) async throws -> String {
        let verses = try await BundledQuranRepository().loadVerses(surahId: surah)
        return verses[ayah - 1].arabicText
    }

    private func frame(_ text: String, style: PiPTextStyle = .standard, page: Int = 0) -> PiPFrame {
        let pagination = CoreTextPiPPaginator().paginate(text, style: style)
        let content = PiPContent(contentType: style == .quran ? .quran : .hisn, contentID: "id", containerID: "c",
                                 title: "أذكار الصباح", subtitle: "الذكر 4", text: text, textStyle: style,
                                 index: 3, total: 10, detail: "التكرار 2 من 3")
        return PiPFrame(content: content, pageText: pagination.pages[page], page: page,
                        pageCount: pagination.pages.count, fontSize: pagination.fontSize, mode: .text,
                        isPlaying: false, time: 4, duration: 10, rate: 0)
    }

    private func runs(_ frame: CTFrame) -> [CTRun] {
        (CTFrameGetLines(frame) as? [CTLine] ?? []).flatMap { CTLineGetGlyphRuns($0) as? [CTRun] ?? [] }
    }

    // MARK: Pages

    func testShortTextIsOnePageAtTheLargestSize() {
        let pagination = CoreTextPiPPaginator().paginate("سُبْحَانَ اللَّهِ وَبِحَمْدِهِ", style: .standard)
        XCTAssertEqual(pagination.pages, ["سُبْحَانَ اللَّهِ وَبِحَمْدِهِ"])
        XCTAssertEqual(pagination.fontSize, Double(PiPFrameRenderer.fontSizes[0]))
    }

    func testLongTextIsSplitIntoReadablePagesWithoutChangingIt() async throws {
        let text = try await longestHisnText()
        let pagination = CoreTextPiPPaginator().paginate(text, style: .standard)
        XCTAssertGreaterThan(pagination.pages.count, 1, "the longest Hisn item needs pages")
        XCTAssertEqual(pagination.pages.joined(), text, "pages are exact slices of the stored text")
        XCTAssertEqual(pagination.fontSize, Double(PiPFrameRenderer.minimumFontSize), "never below the readable size")
        for page in pagination.pages {
            let body = PiPFrameRenderer.bodyString(page, style: .standard, size: PiPFrameRenderer.minimumFontSize,
                                                   color: CGColor(gray: 0, alpha: 1))
            XCTAssertTrue(PiPFrameRenderer.fits(body), "every page fits the window")
        }
    }

    func testEveryPageIsDrawnInFull() async throws {
        let text = try await longestHisnText()
        let pageCount = CoreTextPiPPaginator().paginate(text, style: .standard).pages.count
        for page in 0..<pageCount {
            let frame = self.frame(text, page: page)
            let rendered = try XCTUnwrap(PiPFrameRenderer.render(frame, appearance: .dark))
            let visible = (frame.pageText.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).length
            XCTAssertGreaterThanOrEqual(rendered.bodyCharactersDrawn, visible, "page \(page): nothing cut")
        }
    }

    func testMediumTextTakesAMiddleSize() async throws {
        let items = try await hisnItems()
        let paginator = CoreTextPiPPaginator()
        let sizes = Set(items.prefix(60).map { paginator.paginate($0.arabicText, style: .standard).fontSize })
        XCTAssertGreaterThan(sizes.count, 1, "the size follows the text length")
        XCTAssertTrue(sizes.allSatisfy { $0 >= Double(PiPFrameRenderer.minimumFontSize) })
    }

    // MARK: Arabic

    func testTextRunsRightToLeftWithDiacritics() throws {
        let text = "اللَّهُمَّ بِكَ أَصْبَحْنَا، وَبِكَ أَمْسَيْنَا، وَبِكَ نَحْيَا، وَبِكَ نَمُوتُ، وَإِلَيْكَ النُّشُورُ"
        let rendered = try XCTUnwrap(PiPFrameRenderer.render(frame(text), appearance: .dark))
        XCTAssertEqual(rendered.image.width, PiPFrameRenderer.width)
        XCTAssertEqual(rendered.image.height, PiPFrameRenderer.height)
        XCTAssertEqual(rendered.bodyCharactersDrawn, (text as NSString).length, "every letter and mark is laid out")
        let lines = CTFrameGetLines(rendered.bodyFrame) as? [CTLine] ?? []
        XCTAssertFalse(lines.isEmpty)
        for line in lines where CTLineGetStringRange(line).length > 1 {
            let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
            XCTAssertTrue(runs.contains { CTRunGetStatus($0).contains(.rightToLeft) })
        }
    }

    func testQuranVersesUseTheQuranFont() async throws {
        let text = try await verse(2, 255)
        let rendered = try XCTUnwrap(PiPFrameRenderer.render(frame(text, style: .quran), appearance: .light))
        let fonts = runs(rendered.bodyFrame).compactMap { run -> String? in
            guard let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName as String] else { return nil }
            return CTFontCopyPostScriptName(font as! CTFont) as String
        }
        XCTAssertFalse(fonts.isEmpty)
        XCTAssertTrue(fonts.allSatisfy { $0 == QuranFont.postScriptName }, "\(Set(fonts))")
    }

    func testLongestVerseIsPaginated() async throws {
        let text = try await verse(2, 282)
        let pagination = CoreTextPiPPaginator().paginate(text, style: .quran)
        XCTAssertGreaterThan(pagination.pages.count, 1)
        XCTAssertEqual(pagination.pages.joined(), text)
    }

    // MARK: Appearance

    private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        let data = image.dataProvider!.data! as Data
        let offset = y * image.bytesPerRow + x * 4
        return Array(data[offset..<offset + 4])
    }

    func testLightAndDarkAppearances() throws {
        let frame = self.frame("الْحَمْدُ لِلَّهِ")
        let dark = try XCTUnwrap(PiPFrameRenderer.render(frame, appearance: .dark)).image
        let light = try XCTUnwrap(PiPFrameRenderer.render(frame, appearance: .light)).image
        let darkCorner = pixel(dark, x: 2, y: 2)
        let lightCorner = pixel(light, x: 2, y: 2)
        XCTAssertNotEqual(darkCorner, lightCorner)
        XCTAssertLessThan(Int(darkCorner[0]) + Int(darkCorner[1]) + Int(darkCorner[2]), 200)
        XCTAssertGreaterThan(Int(lightCorner[0]) + Int(lightCorner[1]) + Int(lightCorner[2]), 600)
    }

    func testBadgeIsOnlyDrawnWhenGiven() throws {
        // The fixture build passes a badge; production passes none. Both render.
        XCTAssertNotNil(PiPFrameRenderer.render(frame("الْحَمْدُ لِلَّهِ"), appearance: .dark, badge: nil))
        XCTAssertNotNil(PiPFrameRenderer.render(frame("الْحَمْدُ لِلَّهِ"), appearance: .dark, badge: "نغمة اختبار"))
    }
}
