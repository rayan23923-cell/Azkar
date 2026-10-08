import CoreGraphics
import CoreText
import Foundation
import PiPCore
import QuranText

/// Draws one PiP frame with Core Text and Core Graphics only, so the same code runs in the app
/// (into the `CVPixelBuffer` the sample buffer wraps) and in `swift test`.
///
/// 1280×720 (16:9, the proven size; the PiP window takes its shape from it). From the top: the
/// title and subtitle («سورة البقرة · الآية 10»), the page of the text, a progress bar and the
/// footer (state, counter, «n من m», «صفحة p من q»). Right to left; Arabic shaping and marks by
/// Core Text; verses in the bundled Quran font.
///
/// The text is never changed, shrunk below `minimumFontSize` or cut: the largest size from
/// `fontSizes` that fits the body box is used, and a text that does not fit at the smallest size
/// is split into pages (`CoreTextPiPPaginator`), every page drawn at that size.
public enum PiPFrameRenderer {
    public static let width = 1280
    public static let height = 720
    public static let fontSizes: [CGFloat] = [84, 72, 62, 54]
    public static var minimumFontSize: CGFloat { fontSizes.last! }

    /// The body box, in top-left coordinates.
    static let bodyBox = CGRect(x: 56, y: 100, width: CGFloat(width) - 112, height: 474)
    static let headerBox = CGRect(x: 48, y: 26, width: CGFloat(width) - 96, height: 60)
    static let barBox = CGRect(x: 56, y: 600, width: CGFloat(width) - 112, height: 10)
    static let footerBox = CGRect(x: 48, y: 626, width: CGFloat(width) - 96, height: 60)

    public enum Appearance: Sendable {
        case light
        case dark
    }

    public struct Rendered {
        public let image: CGImage
        /// Characters (UTF-16) of the page Core Text placed in the body frame.
        public let bodyCharactersDrawn: Int
        public let bodyFrame: CTFrame
    }

    /// Renders to an image (tests, previews).
    public static func render(_ frame: PiPFrame, appearance: Appearance, badge: String? = nil) -> Rendered? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let body = draw(frame, appearance: appearance, badge: badge, in: context),
              let image = context.makeImage() else { return nil }
        return Rendered(image: image, bodyCharactersDrawn: CTFrameGetVisibleStringRange(body).length, bodyFrame: body)
    }

    /// Draws into a context of `width`×`height` in Core Graphics coordinates (origin bottom left).
    /// Returns the body's Core Text frame.
    @discardableResult
    public static func draw(_ frame: PiPFrame, appearance: Appearance, badge: String? = nil,
                            in context: CGContext) -> CTFrame? {
        let colors = Colors(appearance)
        context.setFillColor(colors.background)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Header: «badge · title · subtitle», one line.
        var header = [frame.content.title, frame.content.subtitle].filter { !$0.isEmpty }.joined(separator: " · ")
        if let badge { header = "\(badge) · \(header)" }
        drawText(header, font: systemFont(size: 38, bold: true), color: colors.accent, lineHeight: 1.1,
                 alignment: .center, in: headerBox, context: context)

        // Body: the page, centred in its box.
        let body = bodyString(frame.pageText, style: frame.content.textStyle, size: CGFloat(frame.fontSize),
                              color: colors.primary)
        let measured = measure(body, width: bodyBox.width)
        let top = bodyBox.minY + max(0, (bodyBox.height - measured) / 2)
        let bodyRect = CGRect(x: bodyBox.minX, y: top, width: bodyBox.width, height: min(measured, bodyBox.height))
        let bodyFrame = drawFrame(body, in: bodyRect, context: context)

        // Progress bar, filling from the right edge (right to left).
        let bar = flipped(barBox)
        context.setFillColor(colors.track)
        context.addPath(CGPath(roundedRect: bar, cornerWidth: 5, cornerHeight: 5, transform: nil))
        context.fillPath()
        let filled = bar.width * CGFloat(frame.progress)
        if filled > 0 {
            context.setFillColor(colors.secondary)
            context.addPath(CGPath(roundedRect: CGRect(x: bar.maxX - filled, y: bar.minY, width: filled, height: bar.height),
                                   cornerWidth: 5, cornerHeight: 5, transform: nil))
            context.fillPath()
        }

        drawText(frame.footer, font: systemFont(size: 32, bold: false), color: colors.secondary, lineHeight: 1.1,
                 alignment: .center, in: footerBox, context: context)
        return bodyFrame
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

    /// Whether the whole string fits the body box.
    static func fits(_ string: NSAttributedString) -> Bool {
        guard string.length > 0 else { return true }
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let path = CGPath(rect: CGRect(origin: .zero, size: bodyBox.size), transform: nil)
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

    private static func drawText(_ text: String, font: CTFont, color: CGColor, lineHeight: CGFloat,
                                 alignment: CTTextAlignment, in box: CGRect, context: CGContext) {
        guard !text.isEmpty else { return }
        let string = attributed(text, font: font, color: color, lineHeight: lineHeight, alignment: alignment)
        drawFrame(string, in: box, context: context)
    }

    /// `rect` in top-left coordinates.
    @discardableResult
    private static func drawFrame(_ string: NSAttributedString, in rect: CGRect, context: CGContext) -> CTFrame {
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0),
                                             CGPath(rect: flipped(rect), transform: nil), nil)
        CTFrameDraw(frame, context)
        return frame
    }

    /// Top-left coordinates to Core Graphics ones.
    private static func flipped(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: CGFloat(height) - rect.maxY, width: rect.width, height: rect.height)
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

/// Lays out an item's text for the PiP window with the renderer's own fonts and box: the
/// largest size at which it fits on one page, otherwise pages at the smallest readable size.
public struct CoreTextPiPPaginator: PiPPaginating {
    public init() {}

    public func paginate(_ text: String, style: PiPTextStyle) -> PiPPagination {
        let color = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        for size in PiPFrameRenderer.fontSizes
        where PiPFrameRenderer.fits(PiPFrameRenderer.bodyString(text, style: style, size: size, color: color)) {
            return PiPPagination(fontSize: Double(size), pages: [text])
        }
        let size = PiPFrameRenderer.minimumFontSize
        let pages = PiPTextPaginator.pages(text) { slice in
            PiPFrameRenderer.fits(PiPFrameRenderer.bodyString(String(slice), style: style, size: size, color: color))
        }
        return PiPPagination(fontSize: Double(size), pages: pages)
    }
}
