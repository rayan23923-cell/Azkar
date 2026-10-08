import CoreGraphics
import CoreText
import Foundation
import HisnReading

/// Draws a Hisn item as a share image with Core Text and Core Graphics only, so the same
/// code runs in the app and in `swift test`.
///
/// Layout (pixels): 1080 wide, at least 1080 tall (square for short text), taller as the text
/// needs. From the top: «حصن المسلم», the chapter title, a rule, then the item's whole text,
/// right to left, at one fixed readable size. The height comes from Core Text's measurement of
/// the full text; the renderer checks that every character was laid out and fails rather than
/// return a cut image. Text is never shrunk, ellipsized or split.
public enum HisnShareCardRenderer {
    public enum Appearance: Sendable {
        case light
        case dark
    }

    public static let width = 1080
    public static let minimumHeight = 1080
    static let margin: CGFloat = 96
    static let headerSize: CGFloat = 34
    static let titleSize: CGFloat = 40
    static let bodySize: CGFloat = 50

    /// What is drawn, before drawing: the strings, in order, and the measured height.
    public struct Layout {
        public let header: String
        public let title: String
        public let body: String
        public let height: Int
        fileprivate let blocks: [Block]
    }

    fileprivate struct Block {
        let string: NSAttributedString
        let top: CGFloat
        let height: CGFloat
    }

    public struct Card {
        public let image: CGImage
        public let layout: Layout
        /// Characters (UTF-16) of the body Core Text placed in the drawn frame.
        public let bodyCharactersDrawn: Int
        /// The drawn body frame, for inspection in tests (line runs and their direction).
        public let bodyFrame: CTFrame
    }

    public static func layout(_ content: HisnShareContent, appearance: Appearance) -> Layout {
        let colors = Colors(appearance)
        let textWidth = CGFloat(width) - 2 * margin
        let header = "حصن المسلم"
        let headerString = attributed(header, size: headerSize, bold: false, color: colors.accent, lineHeight: 1.2)
        let titleString = attributed(content.chapterTitle, size: titleSize, bold: true, color: colors.secondary,
                                     lineHeight: 1.3)
        let bodyString = attributed(content.text, size: bodySize, bold: true, color: colors.primary, lineHeight: 1.45)

        var y = margin
        let headerHeight = measure(headerString, width: textWidth)
        let headerBlock = Block(string: headerString, top: y, height: headerHeight)
        y += headerHeight + 12
        let titleHeight = measure(titleString, width: textWidth)
        let titleBlock = Block(string: titleString, top: y, height: titleHeight)
        y += titleHeight + 40
        let ruleY = y
        y += 2 + 48
        let bodyHeight = measure(bodyString, width: textWidth)
        let bottom: CGFloat = 112
        let natural = y + bodyHeight + bottom
        let height = max(CGFloat(minimumHeight), natural.rounded(.up))
        // Short text sits in the middle of the space below the rule.
        let bodyTop = y + max(0, (height - natural) / 2)
        let blocks = [headerBlock, titleBlock, Block(string: NSAttributedString(string: ""), top: ruleY, height: 2),
                      Block(string: bodyString, top: bodyTop, height: bodyHeight)]
        return Layout(header: header, title: content.chapterTitle, body: content.text, height: Int(height),
                      blocks: blocks)
    }

    /// Nil when the text is empty or could not be laid out in full.
    public static func render(_ content: HisnShareContent, appearance: Appearance) -> Card? {
        guard !content.text.isEmpty else { return nil }
        let colors = Colors(appearance)
        let layout = layout(content, appearance: appearance)
        let height = layout.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(colors.background)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let textWidth = CGFloat(width) - 2 * margin

        var bodyFrame: CTFrame?
        for (index, block) in layout.blocks.enumerated() {
            // Core Graphics counts y from the bottom.
            let rect = CGRect(x: margin, y: CGFloat(height) - block.top - block.height, width: textWidth,
                              height: block.height)
            if index == 2 {
                context.setFillColor(colors.rule)
                context.fill(CGRect(x: margin, y: rect.minY, width: textWidth, height: 2))
                continue
            }
            let frame = drawFrame(block.string, in: rect, context: context)
            if index == 3 { bodyFrame = frame }
        }
        guard let bodyFrame, let image = context.makeImage() else { return nil }
        let drawn = CTFrameGetVisibleStringRange(bodyFrame).length
        guard drawn == (content.text as NSString).length else { return nil }
        return Card(image: image, layout: layout, bodyCharactersDrawn: drawn, bodyFrame: bodyFrame)
    }

    // MARK: Text

    private static func attributed(_ text: String, size: CGFloat, bold: Bool, color: CGColor,
                                   lineHeight: CGFloat) -> NSAttributedString {
        var font = CTFontCreateUIFontForLanguage(.system, size, "ar" as CFString)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        if bold, let boldFont = CTFontCreateCopyWithSymbolicTraits(font, size, nil, .traitBold, .traitBold) {
            font = boldFont
        }
        var alignment = CTTextAlignment.natural
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

    private static func drawFrame(_ string: NSAttributedString, in rect: CGRect, context: CGContext) -> CTFrame {
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil),
                                             nil)
        CTFrameDraw(frame, context)
        return frame
    }

    // MARK: Colours

    private struct Colors {
        let background: CGColor
        let primary: CGColor
        let secondary: CGColor
        let accent: CGColor
        let rule: CGColor

        init(_ appearance: Appearance) {
            func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
                CGColor(srgbRed: r, green: g, blue: b, alpha: a)
            }
            switch appearance {
            case .light:
                background = rgb(0.98, 0.97, 0.94)
                primary = rgb(0.10, 0.12, 0.11)
                secondary = rgb(0.30, 0.33, 0.31)
                accent = rgb(0.05, 0.40, 0.29)
                rule = rgb(0.05, 0.40, 0.29, 0.35)
            case .dark:
                background = rgb(0.07, 0.11, 0.10)
                primary = rgb(0.95, 0.95, 0.93)
                secondary = rgb(0.75, 0.78, 0.76)
                accent = rgb(0.45, 0.80, 0.64)
                rule = rgb(0.45, 0.80, 0.64, 0.35)
            }
        }
    }
}
