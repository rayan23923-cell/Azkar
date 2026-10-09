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
        let pagination = CoreTextPiPPaginator().paginate(text, style: style, withCounter: true)
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

    /// Every body line with its text, across the text blocks, and the width of its block.
    private func bodyLines(_ rendered: PiPFrameRenderer.Rendered,
                           page: String) -> [(line: CTLine, text: String, blockWidth: CGFloat)] {
        var offset = 0
        var result: [(line: CTLine, text: String, blockWidth: CGFloat)] = []
        for (frame, block) in zip(rendered.bodyFrames, rendered.regions.bodyBlocks) {
            for line in CTFrameGetLines(frame) as? [CTLine] ?? [] {
                let range = CTLineGetStringRange(line)
                let text = (page as NSString).substring(with: NSRange(location: offset + range.location,
                                                                       length: range.length))
                result.append((line, text, block.width))
            }
            offset += CTFrameGetVisibleStringRange(frame).length
        }
        return result
    }

    private func hasArabicLetters(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0621...0x064A).contains($0.value) }
    }

    // MARK: Pages

    func testShortTextIsOnePageAtTheLargestSize() {
        let pagination = CoreTextPiPPaginator().paginate("سُبْحَانَ اللَّهِ وَبِحَمْدِهِ", style: .standard, withCounter: false)
        XCTAssertEqual(pagination.pages, ["سُبْحَانَ اللَّهِ وَبِحَمْدِهِ"])
        XCTAssertEqual(pagination.fontSize, Double(PiPFrameRenderer.fontSizes[0]))
    }

    func testLongTextIsSplitIntoReadablePagesWithoutChangingIt() async throws {
        let text = try await longestHisnText()
        let pagination = CoreTextPiPPaginator().paginate(text, style: .standard, withCounter: false)
        XCTAssertGreaterThan(pagination.pages.count, 1, "the longest Hisn item needs pages")
        XCTAssertEqual(pagination.pages.joined(), text, "pages are exact slices of the stored text")
        XCTAssertEqual(pagination.fontSize, Double(PiPFrameRenderer.minimumFontSize), "never below the readable size")
        for page in pagination.pages {
            let body = PiPFrameRenderer.bodyString(page, style: .standard, size: PiPFrameRenderer.minimumFontSize,
                                                   color: CGColor(gray: 0, alpha: 1))
            XCTAssertTrue(PiPFrameRenderer.fits(body, in: PiPLayout.production.body(withCounter: false).size),
                          "every page fits the window")
        }
    }

    func testEveryPageIsDrawnInFull() async throws {
        let text = try await longestHisnText()
        let pageCount = CoreTextPiPPaginator().paginate(text, style: .standard, withCounter: true).pages.count
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
        let sizes = Set(items.prefix(60).map { paginator.paginate($0.arabicText, style: .standard, withCounter: false).fontSize })
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

    /// The longest counter PiP can show (a Hisn count above 100 on a paged item) stays on one
    /// line, right to left, in Arabic order «التكرار 137 من 1000», away from the system controls.
    func testHisnCounterFitsAndRunsRightToLeft() throws {
        for layout in [PiPLayout.landscape, .portrait] {
            for (completed, total) in [(0, 1), (0, 3), (36, 100), (99, 100), (100, 101), (136, 1000), (1000, 1000)] {
                let repetition = PiPRepetition(completed: completed, total: total)
                let detail = repetition.isComplete ? "اكتمل ✓ \(total) من \(total)  ·  اكتمل الباب"
                    : "التكرار \(repetition.current) من \(total)"
                let content = PiPContent(contentType: .hisn, contentID: "id", containerID: "c",
                                         title: "أذكار الصباح والمساء", subtitle: "الذكر 104",
                                         text: "سُبْحَانَ اللَّهِ وَبِحَمْدِهِ", index: 103, total: 132, detail: detail,
                                         repetition: repetition)
                for playing in [false, true] {
                    let frame = PiPFrame(content: content, pageText: "سُبْحَانَ ", page: 11, pageCount: 12,
                                         fontSize: Double(layout.bodySizes.last!), mode: .text, isPlaying: playing,
                                         time: 104, duration: 132, rate: 0)
                    XCTAssertTrue(frame.counterLine?.hasPrefix(detail) == true, "the count comes first")
                    let rendered = try XCTUnwrap(PiPFrameRenderer.render(frame, appearance: .dark, layout: layout))
                    XCTAssertTrue(rendered.regions.linesFit, "\(completed)/\(total): one line each, nothing cut")
                    let counter = try XCTUnwrap(rendered.regions.counter)
                    for control in layout.systemControls {
                        XCTAssertFalse(counter.intersects(control), "the counter is never under a system control")
                    }
                    for block in rendered.regions.bodyBlocks {
                        XCTAssertFalse(block.intersects(counter), "\(layout): the text never runs into the counter")
                    }
                    let line = PiPFrameRenderer.oneLine(try XCTUnwrap(frame.counterLine), sizes: layout.counterSizes,
                                                        bold: true, color: CGColor(gray: 1, alpha: 1), in: counter)
                    let runs = CTLineGetGlyphRuns(CTLineCreateWithAttributedString(line.string)) as? [CTRun] ?? []
                    XCTAssertTrue(runs.contains { CTRunGetStatus($0).contains(.rightToLeft) })
                }
            }
        }
    }

    // MARK: Layout

    private let layouts: [PiPLayout] = [.landscape, .portrait, PiPLayout(width: 640, height: 360),
                                        PiPLayout(width: 1920, height: 1080), PiPLayout(width: 540, height: 960),
                                        PiPLayout(width: 360, height: 640), PiPLayout(width: 1080, height: 1920)]
    private var portraitLayouts: [PiPLayout] { layouts.filter(\.isPortrait) }

    /// The header, counter and information line keep clear of every place iOS draws a control;
    /// everything stays inside the frame.
    func testContentKeepsClearOfTheSystemControls() {
        for layout in layouts {
            for part in [layout.header, layout.counter, layout.info] {
                XCTAssertTrue(layout.bounds.contains(part), "\(layout)")
                for control in layout.systemControls {
                    XCTAssertFalse(part.intersects(control), "\(layout): \(part) under \(control)")
                }
            }
            for withCounter in [false, true] {
                let body = layout.body(withCounter: withCounter)
                XCTAssertTrue(layout.bounds.contains(body))
                XCTAssertGreaterThan(body.height, layout.unit * 0.45, "the text keeps most of the window")
                for control in layout.cornerControls + [layout.progressControl] {
                    XCTAssertFalse(body.intersects(control), "\(layout): the text is never under the corners or bar")
                }
                XCTAssertFalse(body.intersects(layout.header))
                XCTAssertFalse(body.intersects(layout.info))
                if withCounter { XCTAssertFalse(body.intersects(layout.counter)) }
            }
            XCTAssertFalse(layout.body(withCounter: true).intersects(layout.counter))
        }
    }

    /// Portrait: the text has a block above and one below the middle control row, each holding
    /// at least two lines, and neither is under any system control. Landscape is too short for
    /// that and keeps one block.
    func testPortraitTextBlocksAvoidEveryControl() {
        for layout in layouts {
            for withCounter in [false, true] {
                let blocks = layout.textBlocks(withCounter: withCounter)
                let body = layout.body(withCounter: withCounter)
                XCTAssertEqual(blocks.count, layout.isPortrait ? 2 : 1, "\(layout)")
                for block in blocks {
                    XCTAssertTrue(body.contains(block), "\(layout)")
                    XCTAssertGreaterThanOrEqual(block.height, layout.bodySizes.last! * 1.5 * 2, "two lines each")
                    if layout.isPortrait {
                        for control in layout.systemControls {
                            XCTAssertFalse(block.intersects(control), "\(layout): \(block) under \(control)")
                        }
                    }
                }
                if blocks.count == 2 { XCTAssertLessThan(blocks[0].maxY, blocks[1].minY, "reading order") }
            }
            XCTAssertEqual(layout.textAvoidsCenterControls, layout.isPortrait)
        }
    }

    /// The iPhone screenshot of 2026-10-09: «مَٰلِكِ يَوۡمِ ٱلدِّينِ» was centred in a portrait
    /// window, right behind the play / pause button. A text that fits is now drawn whole above
    /// the middle row.
    func testShortVerseIsDrawnAboveThePlayButton() async throws {
        let text = try await verse(1, 4)
        for layout in portraitLayouts {
            for withCounter in [false, true] {
                let pagination = CoreTextPiPPaginator(layout: layout).paginate(text, style: .quran,
                                                                               withCounter: withCounter)
                XCTAssertEqual(pagination.pages, [text])
                // The largest size at which the verse fits the blocks: every larger one leaves
                // text over (the Quran font's lines are tall), and it is above the paging size.
                let size = CGFloat(pagination.fontSize)
                XCTAssertGreaterThan(size, layout.bodySizes.last!, "\(layout): not the paging size")
                for larger in layout.bodySizes where larger > size {
                    let string = PiPFrameRenderer.bodyString(text, style: .quran, size: larger,
                                                             color: CGColor(gray: 0, alpha: 1))
                    XCTAssertFalse(PiPFrameRenderer.place(string, in: layout.textBlocks(withCounter: withCounter)).complete,
                                   "\(layout): \(larger) would have fitted")
                }
                let content = PiPContent(contentType: .quran, contentID: "1:4", containerID: "1", title: "سورة الفاتحة",
                                         subtitle: "الآية 4", text: text, textStyle: .quran, index: 3, total: 7,
                                         detail: withCounter ? "التكرار 2 من 3" : nil)
                let frame = PiPFrame(content: content, pageText: text, page: 0, pageCount: 1,
                                     fontSize: pagination.fontSize, mode: .text, isPlaying: false, time: 4,
                                     duration: 7, rate: 0)
                let rendered = try XCTUnwrap(PiPFrameRenderer.render(frame, appearance: .dark, layout: layout))
                XCTAssertEqual(rendered.bodyCharactersDrawn, (text as NSString).length)
                XCTAssertEqual(rendered.regions.bodyBlocks.count, 1, "\(layout)")
                XCTAssertLessThanOrEqual(rendered.regions.body.maxY, layout.centerControls.minY,
                                         "\(layout): above the play / pause row")
            }
        }
    }

    /// Long texts in portrait go on from the upper block to the lower one, every letter drawn
    /// once, nothing under a system control.
    func testLongTextFlowsAroundTheMiddleControls() async throws {
        let samples: [(String, PiPTextStyle)] = [(try await longestHisnText(), .standard),
                                                 (try await verse(2, 282), .quran), (try await verse(2, 255), .quran)]
        for layout in portraitLayouts {
            let paginator = CoreTextPiPPaginator(layout: layout)
            for (text, style) in samples {
                let pagination = paginator.paginate(text, style: style, withCounter: true)
                XCTAssertEqual(pagination.pages.joined(), text)
                var usedBoth = false
                for (index, page) in pagination.pages.enumerated() {
                    let content = PiPContent(contentType: style == .quran ? .quran : .hisn, contentID: "id",
                                             containerID: "c", title: "عنوان", subtitle: "", text: text,
                                             textStyle: style, index: 0, total: 1, detail: "التكرار 1 من 3")
                    let frame = PiPFrame(content: content, pageText: page, page: index,
                                         pageCount: pagination.pages.count, fontSize: pagination.fontSize,
                                         mode: .text, isPlaying: false, time: 0, duration: 1, rate: 0)
                    let rendered = try XCTUnwrap(PiPFrameRenderer.render(frame, appearance: .light, layout: layout))
                    XCTAssertEqual(rendered.bodyCharactersDrawn, (page as NSString).length,
                                   "\(layout) page \(index): every character once")
                    XCTAssertEqual(rendered.bodyFrames.count, rendered.regions.bodyBlocks.count)
                    usedBoth = usedBoth || rendered.regions.bodyBlocks.count == 2
                    for block in rendered.regions.bodyBlocks {
                        for control in layout.systemControls {
                            XCTAssertFalse(block.intersects(control), "\(layout) page \(index)")
                        }
                        for part in [layout.header, layout.counter, layout.info] {
                            XCTAssertFalse(block.intersects(part))
                        }
                    }
                }
                XCTAssertTrue(usedBoth, "\(layout): a long text uses both blocks")
            }
        }
    }

    func testLayoutScalesWithTheFrame() {
        let small = PiPLayout(width: 640, height: 360)
        let large = PiPLayout(width: 1920, height: 1080)
        XCTAssertEqual(small.body(withCounter: true).width / CGFloat(small.width),
                       large.body(withCounter: true).width / CGFloat(large.width), accuracy: 0.01)
        XCTAssertEqual(small.bodySizes.last! / small.unit, large.bodySizes.last! / large.unit, accuracy: 0.01)
        XCTAssertTrue(PiPLayout.portrait.isPortrait)
        XCTAssertFalse(PiPLayout.landscape.isPortrait)
        XCTAssertEqual(PiPLayout.production, .landscape, "the device-proven 16:9")
        XCTAssertEqual(PiPFrameRenderer.width, 1280)
        XCTAssertEqual(PiPFrameRenderer.height, 720)
    }

    /// Short and long texts, verses, adhkar, duas and Hisn items in every layout: drawn whole,
    /// inside the frame, right to left, never below the readable size.
    func testEveryLayoutDrawsWholeTextReadably() async throws {
        let longHisn = try await longestHisnText()
        let longVerse = try await verse(2, 282)
        let shortVerse = try await verse(112, 1)
        let samples: [(String, PiPTextStyle)] = [
            ("سُبْحَانَ اللَّهِ", .standard), (longHisn, .standard), (shortVerse, .quran), (longVerse, .quran),
            // Dense marks, long words, Arabic and Western digits, punctuation.
            ("فَأَسْقَيْنَاكُمُوهُ وَلَيَسْتَخْلِفَنَّهُمْ أَنُلْزِمُكُمُوهَا فَسَيَكْفِيكَهُمُ ٱللَّهُ", .quran),
            ("سُبْحَانَ اللَّهِ وَبِحَمْدِهِ (١٠٠ مرة)، 100 مرة؛ «لا إله إلا الله» — 3 مرات!", .standard),
        ]
        for layout in layouts {
            let paginator = CoreTextPiPPaginator(layout: layout)
            for (text, style) in samples {
                for withCounter in [false, true] {
                    let pagination = paginator.paginate(text, style: style, withCounter: withCounter)
                    XCTAssertEqual(pagination.pages.joined(), text, "pages are exact slices")
                    XCTAssertGreaterThanOrEqual(pagination.fontSize, Double(layout.bodySizes.last!))
                    for (index, page) in pagination.pages.enumerated() {
                        let content = PiPContent(contentType: style == .quran ? .quran : .hisn, contentID: "id",
                                                 containerID: "c", title: "سورة البقرة", subtitle: "الآية 282",
                                                 text: text, textStyle: style, index: 281, total: 286,
                                                 detail: withCounter ? "التكرار 37 من 100" : nil)
                        let frame = PiPFrame(content: content, pageText: page, page: index,
                                             pageCount: pagination.pages.count, fontSize: pagination.fontSize,
                                             mode: .text, isPlaying: false, time: 1, duration: 286, rate: 0)
                        let rendered = try XCTUnwrap(PiPFrameRenderer.render(frame, appearance: .dark, layout: layout))
                        XCTAssertEqual(rendered.image.width, layout.width)
                        XCTAssertEqual(rendered.image.height, layout.height)
                        let visible = (page.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).length
                        XCTAssertGreaterThanOrEqual(rendered.bodyCharactersDrawn, visible, "\(layout) page \(index): cut")
                        XCTAssertTrue(layout.bounds.contains(rendered.regions.body))
                        XCTAssertTrue(rendered.regions.linesFit)
                        // Every line with Arabic letters runs right to left (a line of only
                        // digits or punctuation has no direction of its own).
                        let lines = bodyLines(rendered, page: page)
                        XCTAssertFalse(lines.isEmpty)
                        for (line, slice, blockWidth) in lines {
                            // Never squeezed: a line is no wider than its block.
                            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
                                - CTLineGetTrailingWhitespaceWidth(line)
                            XCTAssertLessThanOrEqual(CGFloat(width), blockWidth + 1, "\(layout) page \(index): «\(slice)»")
                            guard hasArabicLetters(slice) else { continue }
                            let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
                            XCTAssertTrue(runs.contains { CTRunGetStatus($0).contains(.rightToLeft) },
                                          "\(layout) page \(index): «\(slice)»")
                        }
                        if layout.isPortrait {
                            for block in rendered.regions.bodyBlocks {
                                XCTAssertFalse(block.intersects(layout.centerControls), "\(layout) page \(index)")
                            }
                        }
                    }
                }
            }
        }
    }

    /// The «اتجاه النافذة العائمة» setting: landscape unless portrait is picked.
    func testOrientationSetting() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "pip.orientation.test"))
        defaults.removePersistentDomain(forName: "pip.orientation.test")
        XCTAssertEqual(PiPLayout.saved(in: defaults), .landscape, "default")
        defaults.set("portrait", forKey: PiPLayout.orientationKey)
        XCTAssertEqual(PiPLayout.saved(in: defaults), .portrait)
        XCTAssertEqual(CoreTextPiPPaginator(layout: PiPLayout.saved(in: defaults)).layout, .portrait)
        defaults.set("sideways", forKey: PiPLayout.orientationKey)
        XCTAssertEqual(PiPLayout.saved(in: defaults), .landscape, "unknown value")
        defaults.set("landscape", forKey: PiPLayout.orientationKey)
        XCTAssertEqual(PiPLayout.saved(in: defaults), .landscape)
        XCTAssertEqual(PiPLayout.Orientation.allCases.map(\.layout), [.landscape, .portrait])
        defaults.removePersistentDomain(forName: "pip.orientation.test")
    }

    /// The readable minimum is larger than before (62 px of 720, was 54).
    func testSmallestBodySizeStaysReadable() {
        XCTAssertGreaterThanOrEqual(PiPFrameRenderer.minimumFontSize, 62)
        XCTAssertEqual(PiPLayout.portrait.bodySizes, PiPLayout.landscape.bodySizes, "same type size either way")
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
        let pagination = CoreTextPiPPaginator().paginate(text, style: .quran, withCounter: false)
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
