import CoreText
import Foundation

/// The printed-page typeface: DigitalKhatt New Madina, drawn after the Madina mushaf script
/// (SIL Open Font License 1.1, see `DigitalKhatt-OFL.txt`). Used by the mushaf pages laid out
/// line for line as printed; the verse reader keeps Amiri Quran.
public enum MushafFont {
    public static let familyName = "DigitalKhatt New Madina"
    public static let postScriptName = "DigitalKhattNewMadinaRegular"
    static let fileName = "DigitalKhattNewMadina"

    private static let registration: Bool = {
        guard let url = fontURL else { return false }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return true }
        return isAvailable
    }()

    public static var fontURL: URL? {
        Bundle.module.url(forResource: fileName, withExtension: "ttf")
            ?? Bundle.module.url(forResource: fileName, withExtension: "ttf", subdirectory: "Resources")
    }

    public static var licenseURL: URL? {
        Bundle.module.url(forResource: "DigitalKhatt-OFL", withExtension: "txt")
            ?? Bundle.module.url(forResource: "DigitalKhatt-OFL", withExtension: "txt", subdirectory: "Resources")
    }

    /// Registers the font for this process (idempotent).
    @discardableResult
    public static func register() -> Bool { registration }

    static var isAvailable: Bool {
        let font = CTFontCreateWithName(postScriptName as CFString, 20, nil)
        return (CTFontCopyPostScriptName(font) as String) == postScriptName
    }

    public static func font(size: CGFloat) -> CTFont? {
        guard register() else { return nil }
        let font = CTFontCreateWithName(postScriptName as CFString, size, nil)
        return (CTFontCopyPostScriptName(font) as String) == postScriptName ? font : nil
    }

    /// The text as this font draws it. Tanzil writes the imala dot of 11:41 and the ishmam of
    /// 12:11 with U+06EA and U+06EB, which this font draws as U+065C and U+06EC; only the
    /// characters handed to the font change, never the stored text.
    public static func display(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { $0.value == 0x06EA || $0.value == 0x06EB }) else { return text }
        return String(String.UnicodeScalarView(text.unicodeScalars.map { scalar -> Unicode.Scalar in
            switch scalar.value {
            case 0x06EA: return "\u{065C}"
            case 0x06EB: return "\u{06EC}"
            default: return scalar
            }
        }))
    }

    /// Characters of `text` (as displayed) the font has no glyph for.
    public static func missingCharacters(in text: String) -> Set<Character> {
        guard let font = font(size: 20) else { return Set(text) }
        var missing = Set<Character>()
        for character in Set(display(text)) where !character.isWhitespace {
            let units = Array(String(character).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            if !CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count) || glyphs.contains(0) {
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
