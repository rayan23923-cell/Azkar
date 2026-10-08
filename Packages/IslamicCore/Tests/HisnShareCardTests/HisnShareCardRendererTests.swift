import CoreGraphics
import CoreText
import XCTest
import IslamicCore
import HisnReading
@testable import HisnShareCard

/// Phase 3E: the share card keeps the whole text, right to left, at a stable size.
final class HisnShareCardRendererTests: XCTestCase {
    private static var cached: HisnLibrary?

    private func library() async throws -> HisnLibrary {
        if let cached = Self.cached { return cached }
        let library = HisnLibrary(book: try await BundledHisnRepository().loadBook())
        Self.cached = library
        return library
    }

    private func content(_ itemId: String) async throws -> (HisnItem, HisnShareContent) {
        let loaded = try await library()
        for chapter in loaded.book.chapters {
            if let item = chapter.items.first(where: { $0.id == itemId }) {
                return (item, HisnShareContent(item: item, chapterTitle: chapter.titleArabic))
            }
        }
        throw XCTSkip("missing \(itemId)")
    }

    /// very short, medium, long (multi-line), multi-line, parentheses, Quran citation,
    /// non-recitation (narration, labels, closing).
    private let cases = ["hisn-087-01", "hisn-001-01", "hisn-001-04", "hisn-027-02", "hisn-016-05",
                         "hisn-021-01", "hisn-001-03", "hisn-029-14", "hisn-133-01"]

    private func pixels(_ image: CGImage) -> [UInt8] {
        let data = image.dataProvider!.data! as Data
        return [UInt8](data)
    }

    func testEveryCaseKeepsTheWholeText() async throws {
        for id in cases {
            let (item, content) = try await content(id)
            let card = try XCTUnwrap(HisnShareCardRenderer.render(content, appearance: .light), id)
            XCTAssertEqual(card.image.width, 1080, id)
            XCTAssertGreaterThanOrEqual(card.image.height, 1080, id)
            XCTAssertEqual(card.layout.body, item.arabicText, "\(id): the domain text, unchanged")
            XCTAssertEqual(card.bodyCharactersDrawn, (item.arabicText as NSString).length, "\(id): nothing cut")
            XCTAssertEqual(card.layout.header, "حصن المسلم")
        }
    }

    func testOnlyHeaderTitleAndTextAreDrawn() async throws {
        let (item, content) = try await content("hisn-001-03")
        let layout = HisnShareCardRenderer.layout(content, appearance: .light)
        let drawn = [layout.header, layout.title, layout.body]
        XCTAssertEqual(drawn, ["حصن المسلم", content.chapterTitle, item.arabicText])
        for text in drawn {
            for internal in [item.id, item.chapterId, "CONTENT_REVIEW", "PENDING", "rights"] {
                XCTAssertFalse(text.contains(internal), internal)
            }
        }
    }

    func testHeightGrowsWithTheText() async throws {
        let shortContent = try await content("hisn-087-01").1
        let mediumContent = try await content("hisn-021-01").1
        let longContent = try await content("hisn-001-04").1
        let short = try XCTUnwrap(HisnShareCardRenderer.render(shortContent, appearance: .light))
        let medium = try XCTUnwrap(HisnShareCardRenderer.render(mediumContent, appearance: .light))
        let long = try XCTUnwrap(HisnShareCardRenderer.render(longContent, appearance: .light))
        XCTAssertEqual(short.image.height, 1080, "short text: square")
        XCTAssertLessThanOrEqual(medium.image.height, long.image.height)
        XCTAssertGreaterThan(long.image.height, 2000, "1864 characters at full size need a tall card")
        let lines = CTFrameGetLines(long.bodyFrame) as! [CTLine]
        XCTAssertGreaterThan(lines.count, 20, "long text wraps over many lines")
    }

    func testTextRunsRightToLeft() async throws {
        for id in ["hisn-001-01", "hisn-001-04", "hisn-021-01", "hisn-029-14"] {
            let itemContent = try await content(id).1
            let card = try XCTUnwrap(HisnShareCardRenderer.render(itemContent, appearance: .light))
            let lines = CTFrameGetLines(card.bodyFrame) as! [CTLine]
            XCTAssertFalse(lines.isEmpty)
            for line in lines {
                let runs = CTLineGetGlyphRuns(line) as! [CTRun]
                let rtl = runs.contains { CTRunGetStatus($0).contains(.rightToLeft) }
                let range = CTLineGetStringRange(line)
                if range.length > 1 { XCTAssertTrue(rtl, "\(id): a line without right-to-left runs") }
            }
        }
    }

    func testImageIsNotEmptyAndFollowsAppearance() async throws {
        let content = try await content("hisn-001-01").1
        let light = try XCTUnwrap(HisnShareCardRenderer.render(content, appearance: .light))
        let dark = try XCTUnwrap(HisnShareCardRenderer.render(content, appearance: .dark))
        let lightPixels = pixels(light.image)
        let darkPixels = pixels(dark.image)
        XCTAssertNotEqual(Array(lightPixels.prefix(4)), Array(darkPixels.prefix(4)), "different backgrounds")
        var inked = 0
        for offset in stride(from: 0, to: lightPixels.count, by: 4)
            where lightPixels[offset] != lightPixels[0] || lightPixels[offset + 1] != lightPixels[1]
                || lightPixels[offset + 2] != lightPixels[2] {
            inked += 1
        }
        XCTAssertGreaterThan(inked, 5000, "text was drawn")
    }

    func testRenderingIsDeterministic() async throws {
        let content = try await content("hisn-027-02").1
        let first = try XCTUnwrap(HisnShareCardRenderer.render(content, appearance: .dark))
        let second = try XCTUnwrap(HisnShareCardRenderer.render(content, appearance: .dark))
        XCTAssertEqual(first.image.height, second.image.height)
        XCTAssertEqual(pixels(first.image), pixels(second.image))
    }

    func testRendererHasNoNetworkOrPlatformUIPath() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/HisnShareCard/HisnShareCardRenderer.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        for word in ["URLSession", "http", "import UIKit", "import AppKit", "AVKit", "PiP"] {
            XCTAssertFalse(source.contains(word), word)
        }
    }
}
