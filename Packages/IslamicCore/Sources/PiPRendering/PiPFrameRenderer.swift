import CoreGraphics
import CoreText
import Foundation
import PiPCore
import QuranText

/// Draws one PiP frame with Core Text and Core Graphics only, so the same code runs in the app
/// (into the `CVPixelBuffer` the sample buffer wraps) and in `swift test`.
///
/// Content first, laid out by `PiPLayout` around the places iOS draws its controls: the title
/// and subtitle at the top between the corner buttons, the counter under them in large type,
/// the page of the text, the information line (position, page, what play / pause does next)
/// above the system progress bar, and a thin progress line. Right to left; Arabic shaping and
/// marks by Core Text; verses in the bundled Quran font.
///
/// The text is never changed, shrunk below the layout's smallest body size or cut: the largest
/// size that fits the body box is used, and a text that does not fit at the smallest size is
/// split into pages (`CoreTextPiPPaginator`), every page drawn at that size. Each line (header,
/// counter, information) stays on one line, at a smaller size if it must.
public enum PiPFrameRenderer {
    /// The production frame size.
    public static var width: Int { PiPLayout.production.width }
    public static var height: Int { PiPLayout.production.height }
    public static var fontSizes: [CGFloat] { PiPLayout.production.bodySizes }
    public static var minimumFontSize: CGFloat { fontSizes.last! }

    public enum Appearance: Sendable {
        case light
        case dark
    }

    public struct Rendered {
        public let image: CGImage
        /// Characters (UTF-16) of the page Core Text placed in the body frame.
        public let bodyCharactersDrawn: Int
        public let bodyFrame: CTFrame
        /// Where each part was drawn, in top-left coordinates (tests check them against the
        /// system controls).
        public let regions: Regions
    }

    /// The boxes the frame's parts were drawn in (nil when the part was not drawn).
    public struct Regions {
        public let header: CGRect
        public let counter: CGRect?
        public let body: CGRect
        public let info: CGRect
        /// Every one-line part (header, counter, information) kept to one line.
        public let linesFit: Bool
    }

    /// Renders to an image (tests, previews).
    public static func render(_ frame: PiPFrame, appearance: Appearance, badge: String? = nil,
                              layout: PiPLayout = .production) -> Rendered? {
        guard let context = CGContext(data: nil, width: layout.width, height: layout.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let drawn = drawParts(frame, appearance: appearance, badge: badge, layout: layout, in: context),
              let image = context.makeImage() else { return nil }
        return Rendered(image: image, bodyCharactersDrawn: CTFrameGetVisibleStringRange(drawn.body).length,
                        bodyFrame: drawn.body, regions: drawn.regions)
    }

    /// Draws into a context of the layout's size in Core Graphics coordinates (origin bottom
    /// left). Returns the body's Core Text frame.
    @discardableResult
    public static func draw(_ frame: PiPFrame, appearance: Appearance, badge: String? = nil,
                            layout: PiPLayout = .production, in context: CGContext) -> CTFrame? {
        drawParts(frame, appearance: appearance, badge: badge, layout: layout, in: context)?.body
    }

    private static func drawParts(_ frame: PiPFrame, appearance: Appearance, badge: String?, layout: PiPLayout,
                                  in context: CGContext) -> (body: CTFrame, regions: Regions)? {
        let colors = Colors(appearance)
        context.setFillColor(colors.background)
        context.fill(layout.bounds)
        var linesFit = true

        // Header: «badge · title · subtitle», one line between the corner controls.
        var header = [frame.content.title, frame.content.subtitle].filter { !$0.isEmpty }.joined(separator: " · ")
        if let badge { header = "\(badge) · \(header)" }
        let headerLine = oneLine(header, sizes: layout.headerSizes, bold: true, color: colors.accent, in: layout.header)
        linesFit = linesFit && headerLine.fits
        drawFrame(headerLine.string, in: layout.header, layout: layout, context: context)

        // Counter: large, under the header, away from every system control.
        let counterLine = frame.counterLine
        if let counterLine {
            let line = oneLine(counterLine, sizes: layout.counterSizes, bold: true, color: colors.primary,
                               in: layout.counter)
            linesFit = linesFit && line.fits
            drawFrame(line.string, in: layout.counter, layout: layout, context: context)
        }

        // Body: the page, centred in its box.
        let bodyBox = layout.body(withCounter: counterLine != nil)
        let body = bodyString(frame.pageText, style: frame.content.textStyle, size: CGFloat(frame.fontSize),
                              color: colors.primary)
        let measured = measure(body, width: bodyBox.width)
        let top = bodyBox.minY + max(0, (bodyBox.height - measured) / 2)
        let bodyRect = CGRect(x: bodyBox.minX, y: top, width: bodyBox.width, height: min(measured, bodyBox.height))
        let bodyFrame = drawFrame(body, in: bodyRect, layout: layout, context: context)

        // Information line above the system progress bar.
        let info = oneLine(frame.infoLine, sizes: layout.infoSizes, bold: false, color: colors.secondary,
                           in: layout.info)
        linesFit = linesFit && info.fits
        drawFrame(info.string, in: layout.info, layout: layout, context: context)

        // Progress line, filling from the right edge (right to left).
        let bar = flipped(layout.progressLine, layout: layout)
        let radius = bar.height / 2
        context.setFillColor(colors.track)
        context.addPath(CGPath(roundedRect: bar, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        let filled = bar.width * CGFloat(frame.progress)
        if filled > 0 {
            context.setFillColor(colors.secondary)
            context.addPath(CGPath(roundedRect: CGRect(x: bar.maxX - filled, y: bar.minY, width: filled, height: bar.height),
                                   cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.fillPath()
        }
        return (bodyFrame, Regions(header: layout.header, counter: counterLine == nil ? nil : layout.counter,
                                   body: bodyRect, info: layout.info, linesFit: linesFit))
    }

    /// A line at the largest of `sizes` that keeps it on one line in `box`.
    static func oneLine(_ text: String, sizes: [CGFloat], bold: Bool, color: CGColor,
                        in box: CGRect) -> (string: NSAttributedString, fits: Bool) {
        let strings = sizes.map {
            attributed(text, font: systemFont(size: $0, bold: bold), color: color, lineHeight: 1.1, alignment: .center)
        }
        if let fitting = strings.first(where: { isOneLine($0, in: box) }) { return (fitting, true) }
        return (strings.last!, false)
    }

    /// One line, inside the box's height.
    static func isOneLine(_ string: NSAttributedString, in box: CGRect) -> Bool {
        guard string.length > 0 else { return true }
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0),
                                             CGPath(rect: CGRect(origin: .zero, size: box.size), transform: nil), nil)
        let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
        return lines.count == 1 && CTFrameGetVisibleStringRange(frame).length == string.length
    }

    // MARK: Text

    static func bodyString(_ text: String, style: PiPTextStyle, size: CGFloat, color: CGColor) -> NSAttributedString {
        switch style {
        case .quran:
            let font = QuranFont.font(size: size) ?? systemFont(size: size, bold: false)
            return attributed(text, font: font, color: color, lineHeight: 1.5, alignment: .center)
        case .standard:
            return attributed(text, font: systemFont(size: size, bold: true), color: color, lineHeight: 1.25,
                              alignment: .center)
        }
    }

    /// Whether the whole string fits a body box of `size`.
    static func fits(_ string: NSAttributedString, in size: CGSize) -> Bool {
        guard string.length > 0 else { return true }
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        return CTFrameGetVisibleStringRange(frame).length == string.length
    }

    static func systemFont(size: CGFloat, bold: Bool) -> CTFont {
        var font = CTFontCreateUIFontForLanguage(.system, size, "ar" as CFString)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        if bold, let boldFont = CTFontCreateCopyWithSymbolicTraits(font, size, nil, .traitBold, .traitBold) {
            font = boldFont
        }
        return font
    }

    private static func attributed(_ text: String, font: CTFont, color: CGColor, lineHeight: CGFloat,
                                   alignment: CTTextAlignment) -> NSAttributedString {
        var alignment = alignment
        var direction = CTWritingDirection.rightToLeft
        var multiple = lineHeight
        var breakMode = CTLineBreakMode.byWordWrapping
        // The setting values are read during CTParagraphStyleCreate, so it is called while the
        // pointers are valid.
        let paragraph: CTParagraphStyle = withUnsafeBytes(of: &alignment) { a in
            withUnsafeBytes(of: &direction) { d in
                withUnsafeBytes(of: &multiple) { m in
                    withUnsafeBytes(of: &breakMode) { b in
                        let settings = [
                            CTParagraphStyleSetting(spec: .alignment, valueSize: a.count, value: a.baseAddress!),
                            CTParagraphStyleSetting(spec: .baseWritingDirection, valueSize: d.count, value: d.baseAddress!),
                            CTParagraphStyleSetting(spec: .lineHeightMultiple, valueSize: m.count, value: m.baseAddress!),
                            CTParagraphStyleSetting(spec: .lineBreakMode, valueSize: b.count, value: b.baseAddress!),
                        ]
                        return CTParagraphStyleCreate(settings, settings.count)
                    }
                }
            }
        }
        return NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
        ])
    }

    private static func measure(_ string: NSAttributedString, width: CGFloat) -> CGFloat {
        guard string.length > 0 else { return 0 }
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        // A few pixels of slack so the last line is never dropped by rounding.
        return size.height.rounded(.up) + 4
    }

    /// `rect` in top-left coordinates.
    @discardableResult
    private static func drawFrame(_ string: NSAttributedString, in rect: CGRect, layout: PiPLayout,
                                  context: CGContext) -> CTFrame {
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0),
                                             CGPath(rect: flipped(rect, layout: layout), transform: nil), nil)
        CTFrameDraw(frame, context)
        return frame
    }

    /// Top-left coordinates to Core Graphics ones.
    private static func flipped(_ rect: CGRect, layout: PiPLayout) -> CGRect {
        CGRect(x: rect.minX, y: CGFloat(layout.height) - rect.maxY, width: rect.width, height: rect.height)
    }

    // MARK: Colours

    private struct Colors {
        let background: CGColor
        let primary: CGColor
        let secondary: CGColor
        let accent: CGColor
        let track: CGColor

        init(_ appearance: Appearance) {
            func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
                CGColor(srgbRed: r, green: g, blue: b, alpha: a)
            }
            switch appearance {
            case .dark:
                // The background of the device-proven POC frames.
                background = rgb(0.05, 0.22, 0.16)
                primary = rgb(1, 1, 1)
                secondary = rgb(1, 1, 1, 0.8)
                accent = rgb(0.62, 0.90, 0.76)
                track = rgb(1, 1, 1, 0.2)
            case .light:
                background = rgb(0.98, 0.97, 0.94)
                primary = rgb(0.10, 0.12, 0.11)
                secondary = rgb(0.30, 0.33, 0.31)
                accent = rgb(0.05, 0.40, 0.29)
                track = rgb(0.05, 0.40, 0.29, 0.2)
            }
        }
    }
}

/// Lays out an item's text for the PiP window with the renderer's own fonts and layout: the
/// largest size at which it fits on one page, otherwise pages at the smallest readable size.
public struct CoreTextPiPPaginator: PiPPaginating {
    public let layout: PiPLayout

    public init(layout: PiPLayout = .production) {
        self.layout = layout
    }

    public func paginate(_ text: String, style: PiPTextStyle, withCounter: Bool) -> PiPPagination {
        let color = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let box = layout.body(withCounter: withCounter).size
        for size in layout.bodySizes
        where PiPFrameRenderer.fits(PiPFrameRenderer.bodyString(text, style: style, size: size, color: color), in: box) {
            return PiPPagination(fontSize: Double(size), pages: [text])
        }
        let size = layout.bodySizes.last!
        let pages = PiPTextPaginator.pages(text) { slice in
            PiPFrameRenderer.fits(PiPFrameRenderer.bodyString(String(slice), style: style, size: size, color: color),
                                  in: box)
        }
        return PiPPagination(fontSize: Double(size), pages: pages)
    }
}
