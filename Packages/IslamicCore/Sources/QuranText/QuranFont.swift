import CoreText
import Foundation

/// The bundled Quran typeface: Amiri Quran (SIL Open Font License 1.1, see
/// `AmiriQuran-OFL.txt`). It carries every character of the Tanzil Uthmani text, with the
/// OpenType shaping (GSUB/GPOS) the Quranic marks need, so verses are never shown with a
/// substituted system font. Core Text only; works in the app and in tests.
public enum QuranFont {
    public static let familyName = "Amiri Quran"
    public static let postScriptName = "AmiriQuran-Regular"
    static let fileName = "AmiriQuran-Regular"

    private static let registration: Bool = {
        guard let url = fontURL else { return false }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return true }
        // Already registered in this process counts as registered.
        return isAvailable
    }()

    /// The font file inside the package bundle.
    public static var fontURL: URL? {
        Bundle.module.url(forResource: fileName, withExtension: "ttf")
            ?? Bundle.module.url(forResource: fileName, withExtension: "ttf", subdirectory: "Resources")
    }

    /// The licence text shipped with the font.
    public static var licenseURL: URL? {
        Bundle.module.url(forResource: "AmiriQuran-OFL", withExtension: "txt")
            ?? Bundle.module.url(forResource: "AmiriQuran-OFL", withExtension: "txt", subdirectory: "Resources")
    }

    /// Registers the font for this process (idempotent). Call once at launch.
    @discardableResult
    public static func register() -> Bool { registration }

    static var isAvailable: Bool {
        let font = CTFontCreateWithName(postScriptName as CFString, 20, nil)
        return (CTFontCopyPostScriptName(font) as String) == postScriptName
    }

    /// The Quran font at a point size; nil if it could not be registered.
    public static func font(size: CGFloat) -> CTFont? {
        guard register() else { return nil }
        let font = CTFontCreateWithName(postScriptName as CFString, size, nil)
        return (CTFontCopyPostScriptName(font) as String) == postScriptName ? font : nil
    }

    /// UTF-16 units of `text` the font has no glyph for (spaces and line breaks excluded).
    public static func missingCharacters(in text: String) -> Set<Character> {
        guard let font = font(size: 20) else { return Set(text) }
        var missing = Set<Character>()
        for character in Set(text) where !character.isWhitespace {
            let units = Array(String(character).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            if !CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count) || glyphs.contains(0) {
                // A combining mark alone may report no glyph; check it on a base letter.
                let combined = Array(("\u{0628}" + String(character)).utf16)
                var pair = [CGGlyph](repeating: 0, count: combined.count)
                if !CTFontGetGlyphsForCharacters(font, combined, &pair, combined.count) || pair.contains(0) {
                    missing.insert(character)
                }
            }
        }
        return missing
    }
}

/// Lays out Quran text with the Quran font, right to left, wrapping at word boundaries, and
/// reports whether the whole text fitted. Used by tests and by the share card.
public enum QuranTextLayout {
    public struct Result {
        public let size: CGSize
        public let lineCount: Int
        public let charactersLaidOut: Int
        /// Glyphs the font could not supply (glyph 0 after shaping).
        public let missingGlyphs: Int
    }

    public static func attributed(_ text: String, size: CGFloat, lineHeight: CGFloat = 1.9) -> NSAttributedString? {
        guard let font = QuranFont.font(size: size) else { return nil }
        var alignment = CTTextAlignment.natural
        var direction = CTWritingDirection.rightToLeft
        var breakMode = CTLineBreakMode.byWordWrapping
        var multiple = lineHeight
        let style: CTParagraphStyle = withUnsafeBytes(of: &alignment) { a in
            withUnsafeBytes(of: &direction) { d in
                withUnsafeBytes(of: &breakMode) { b in
                    withUnsafeBytes(of: &multiple) { m in
                        let settings = [
                            CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: a.baseAddress!),
                            CTParagraphStyleSetting(spec: .baseWritingDirection, valueSize: MemoryLayout<CTWritingDirection>.size, value: d.baseAddress!),
                            CTParagraphStyleSetting(spec: .lineBreakMode, valueSize: MemoryLayout<CTLineBreakMode>.size, value: b.baseAddress!),
                            CTParagraphStyleSetting(spec: .lineHeightMultiple, valueSize: MemoryLayout<CGFloat>.size, value: m.baseAddress!),
                        ]
                        return CTParagraphStyleCreate(settings, settings.count)
                    }
                }
            }
        }
        return NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): style,
        ])
    }

    /// Lays the text out in `width` points with unlimited height.
    public static func layout(_ text: String, size: CGFloat, width: CGFloat) -> Result? {
        guard let string = attributed(text, size: size) else { return nil }
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: 0), nil,
                                                               CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: ceil(fit.height) + 8), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
        var missing = 0
        for line in lines {
            for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
                let count = CTRunGetGlyphCount(run)
                var glyphs = [CGGlyph](repeating: 0, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                missing += glyphs.filter { $0 == 0 }.count
            }
        }
        return Result(size: fit, lineCount: lines.count, charactersLaidOut: CTFrameGetVisibleStringRange(frame).length,
                      missingGlyphs: missing)
    }
}
