import CoreGraphics
import CoreText
import Foundation
import ImageIO
import XCTest
import HisnReading
import IslamicCore
import PiPCore
import QuranText
@testable import PiPRendering

/// Writes PNG previews of PiP frames for a visual review, when `PIP_PREVIEW_DIR` is set (CI
/// uploads them as the `pip-frame-previews` artifact). Each frame is written as drawn and again
/// with the places the layout keeps for the iOS controls outlined in red. Those outlines are
/// the layout's estimate, not the real system controls, and no preview is a device capture.
final class PiPFramePreviewTests: XCTestCase {
    private struct Case {
        let name: String
        let layout: PiPLayout
        let text: String
        let style: PiPTextStyle
        let title: String
        let subtitle: String
        var detail: String? = nil
        var repetition: PiPRepetition? = nil
        var page: Int = 0
        var appearance: PiPFrameRenderer.Appearance = .dark
    }

    func testWritePreviews() async throws {
        guard let path = ProcessInfo.processInfo.environment["PIP_PREVIEW_DIR"], !path.isEmpty else {
            throw XCTSkip("PIP_PREVIEW_DIR not set")
        }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fatiha = try await BundledQuranRepository().loadVerses(surahId: 1)
        let baqara = try await BundledQuranRepository().loadVerses(surahId: 2)
        let items = try await BundledHisnRepository().loadBook().chapters.flatMap(\.items)
        let longHisn = try XCTUnwrap(items.max { $0.arabicText.count < $1.arabicText.count }).arabicText
        let mediumHisn = try XCTUnwrap(items.first { (120...220).contains($0.arabicText.count) }).arabicText
        let dense = "فَأَسْقَيْنَاكُمُوهُ وَلَيَسْتَخْلِفَنَّهُمْ أَنُلْزِمُكُمُوهَا فَسَيَكْفِيكَهُمُ ٱللَّهُ"
        let small = PiPLayout(width: 360, height: 640)

        var cases: [Case] = []
        for layout in [PiPLayout.portrait, .landscape] {
            let tag = layout.isPortrait ? "portrait" : "landscape"
            cases += [
                Case(name: "\(tag)-quran-short-1-4", layout: layout, text: fatiha[3].arabicText, style: .quran,
                     title: "سورة الفاتحة", subtitle: "الآية 4"),
                Case(name: "\(tag)-quran-long-2-282-page1", layout: layout, text: baqara[281].arabicText,
                     style: .quran, title: "سورة البقرة", subtitle: "الآية 282"),
                Case(name: "\(tag)-hisn-count-37-of-100", layout: layout, text: mediumHisn, style: .standard,
                     title: "أذكار الصباح والمساء", subtitle: "الذكر 18", detail: "التكرار 37 من 100",
                     repetition: PiPRepetition(completed: 36, total: 100)),
                Case(name: "\(tag)-hisn-complete-1000", layout: layout, text: "سُبْحَانَ اللَّهِ وَبِحَمْدِهِ",
                     style: .standard, title: "أذكار الصباح والمساء", subtitle: "الذكر 104",
                     detail: "اكتمل ✓ 1000 من 1000", repetition: PiPRepetition(completed: 1000, total: 1000)),
                Case(name: "\(tag)-dense-diacritics", layout: layout, text: dense, style: .quran,
                     title: "تشكيل كثيف", subtitle: "كلمات طويلة"),
            ]
        }
        cases += [
            Case(name: "portrait-quran-long-2-282-page2", layout: .portrait, text: baqara[281].arabicText,
                 style: .quran, title: "سورة البقرة", subtitle: "الآية 282", page: 1),
            Case(name: "portrait-hisn-long-count-3-light", layout: .portrait, text: longHisn, style: .standard,
                 title: "حصن المسلم", subtitle: "أطول ذكر", detail: "التكرار 1 من 3",
                 repetition: PiPRepetition(completed: 0, total: 3), appearance: .light),
            Case(name: "smallest-360x640-hisn-long", layout: small, text: longHisn, style: .standard,
                 title: "حصن المسلم", subtitle: "أطول ذكر", detail: "التكرار 37 من 100",
                 repetition: PiPRepetition(completed: 36, total: 100)),
            Case(name: "smallest-360x640-quran-short", layout: small, text: fatiha[3].arabicText, style: .quran,
                 title: "سورة الفاتحة", subtitle: "الآية 4"),
        ]

        for item in cases {
            let pagination = CoreTextPiPPaginator(layout: item.layout)
                .paginate(item.text, style: item.style, withCounter: item.repetition != nil)
            let page = min(item.page, pagination.pages.count - 1)
            let content = PiPContent(contentType: item.style == .quran ? .quran : .hisn, contentID: item.name,
                                     containerID: "preview", title: item.title, subtitle: item.subtitle,
                                     text: item.text, textStyle: item.style, index: 3, total: 7, detail: item.detail,
                                     repetition: item.repetition)
            let frame = PiPFrame(content: content, pageText: pagination.pages[page], page: page,
                                 pageCount: pagination.pages.count, fontSize: pagination.fontSize, mode: .text,
                                 isPlaying: false, time: 4, duration: 7, rate: 0)
            let rendered = try XCTUnwrap(PiPFrameRenderer.render(frame, appearance: item.appearance,
                                                                  layout: item.layout))
            XCTAssertEqual(rendered.bodyCharactersDrawn, (pagination.pages[page] as NSString).length, item.name)
            try write(rendered.image, to: directory.appendingPathComponent("\(item.name).png"))
            try write(try XCTUnwrap(withZones(rendered, layout: item.layout)),
                      to: directory.appendingPathComponent("\(item.name)-zones.png"))
        }
        try """
        PiP frame previews (PiPFrameRenderer output, from swift test). Not device captures.
        *-zones.png outline in red the places the layout keeps for the iOS controls (close,
        return to app, skip back / play-pause / skip forward, progress bar) and in green the
        text blocks. The red places are an estimate measured on one iPhone screenshot; the real
        controls are drawn by iOS, only while shown, and are not in these images.
        """.write(to: directory.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
    }

    /// The frame with the reserved control places (red) and the text blocks (green) outlined.
    private func withZones(_ rendered: PiPFrameRenderer.Rendered, layout: PiPLayout) -> CGImage? {
        guard let context = CGContext(data: nil, width: layout.width, height: layout.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(rendered.image, in: layout.bounds)
        func flipped(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: CGFloat(layout.height) - rect.maxY, width: rect.width, height: rect.height)
        }
        context.setLineWidth(max(2, layout.unit * 0.004))
        context.setFillColor(CGColor(srgbRed: 1, green: 0.1, blue: 0.1, alpha: 0.18))
        context.setStrokeColor(CGColor(srgbRed: 1, green: 0.1, blue: 0.1, alpha: 0.9))
        for control in layout.systemControls {
            context.fill(flipped(control))
            context.stroke(flipped(control))
        }
        context.setStrokeColor(CGColor(srgbRed: 0.1, green: 0.9, blue: 0.3, alpha: 0.9))
        for block in rendered.regions.bodyBlocks { context.stroke(flipped(block)) }
        // Label the middle row so a reviewer cannot take the outline for the real buttons.
        let label = NSAttributedString(string: "تقدير لمكان أزرار iOS (ليست الأزرار الفعلية)", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String):
                PiPFrameRenderer.systemFont(size: layout.unit * 0.032, bold: true),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(srgbRed: 1, green: 0.3, blue: 0.3, alpha: 1),
        ])
        let line = CTLineCreateWithAttributedString(label)
        let center = flipped(layout.centerControls)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.textPosition = CGPoint(x: center.midX - width / 2, y: center.minY + layout.unit * 0.012)
        CTLineDraw(line, context)
        return context.makeImage()
    }

    private func write(_ image: CGImage, to url: URL) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination), url.lastPathComponent)
    }
}
