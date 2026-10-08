import CoreVideo
import HisnReading
import QuartzCore
import UIKit

/// Draws one Hisn PiP frame (1280×720, the proven size; PiP takes its 16:9 window from it):
/// «حصن المسلم» and the chapter at the top, the dhikr text in the middle, and the playback
/// state, times and a progress bar at the bottom. Dark background with light text in both
/// appearances, so it reads the same over any app.
///
/// Long text is never changed or cut: the largest size from `textSizes` that fits is used, and
/// text that does not fit at the smallest size is split into pages (exact slices of the text,
/// broken at spaces) shown in turn every `pageSeconds`, with «n/m» in the footer.
final class HisnPiPFrameRenderer {
    static let width = 1280
    static let height = 720
    static let textSizes: [CGFloat] = [84, 72, 62, 54, 46]
    static let pageSeconds: CFTimeInterval = 8

    private let background = UIColor(red: 0.05, green: 0.22, blue: 0.16, alpha: 1)
    private var layoutCache: (text: String, size: CGFloat, pages: [Range<String.Index>])?

    func makePixelBuffer(content: HisnPiPContent) -> CVPixelBuffer? {
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
        ]
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, Self.width, Self.height, kCVPixelFormatType_32BGRA,
                                  attrs as CFDictionary, &pixelBuffer) == kCVReturnSuccess,
              let pb = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: Self.width, height: Self.height,
                                  bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(Self.height))
        ctx.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(ctx)
        defer { UIGraphicsPopContext() }

        let bounds = CGRect(x: 0, y: 0, width: Self.width, height: Self.height)
        background.setFill()
        UIRectFill(bounds)

        // Header: app section and chapter, one line each, right to left.
        #if HISN_AUDIO_FIXTURE
        let header = "نغمة اختبار · حصن المسلم · \(content.chapterTitle)"
        #else
        let header = "حصن المسلم · \(content.chapterTitle)"
        #endif
        draw(header, size: 34, weight: .semibold, alpha: 0.75,
             in: CGRect(x: 48, y: 28, width: bounds.width - 96, height: 48), lines: 1)

        // Body: the dhikr text.
        let textRect = CGRect(x: 56, y: 96, width: bounds.width - 112, height: 470)
        let layout = layoutText(content.itemText, in: textRect.size)
        let pageIndex = layout.pages.count > 1
            ? Int(CACurrentMediaTime() / Self.pageSeconds) % layout.pages.count : 0
        let page = layout.pages.isEmpty ? Substring(content.itemText) : content.itemText[layout.pages[pageIndex]]
        let body = attributed(String(page), size: layout.size, weight: .bold, alpha: 1)
        let measured = body.boundingRect(with: textRect.size, options: [.usesLineFragmentOrigin, .usesFontLeading],
                                         context: nil)
        let y = textRect.minY + max(0, (textRect.height - measured.height) / 2)
        body.draw(with: CGRect(x: textRect.minX, y: y, width: textRect.width, height: min(measured.height, textRect.height)),
                  options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)

        // Footer: progress bar, state, times, page.
        let barRect = CGRect(x: 56, y: 600, width: bounds.width - 112, height: 10)
        UIColor(white: 1, alpha: 0.2).setFill()
        UIBezierPath(roundedRect: barRect, cornerRadius: 5).fill()
        if let progress = content.progress {
            // Right to left: the bar fills from the right edge.
            let filled = barRect.width * progress
            UIColor(white: 1, alpha: 0.9).setFill()
            UIBezierPath(roundedRect: CGRect(x: barRect.maxX - filled, y: barRect.minY, width: filled,
                                             height: barRect.height), cornerRadius: 5).fill()
        }
        var footer = "\(stateText(content.playback))   \(timeText(content.currentTime))"
        if let duration = content.duration { footer += " / \(timeText(duration))" }
        if layout.pages.count > 1 { footer += "   ·   \(pageIndex + 1)/\(layout.pages.count)" }
        draw(footer, size: 34, weight: .regular, alpha: 0.8,
             in: CGRect(x: 48, y: 630, width: bounds.width - 96, height: 50), lines: 1, monospacedDigits: true)
        return pb
    }

    // MARK: Layout

    private func layoutText(_ text: String, in size: CGSize) -> (size: CGFloat, pages: [Range<String.Index>]) {
        if let cache = layoutCache, cache.text == text { return (cache.size, cache.pages) }
        var result: (size: CGFloat, pages: [Range<String.Index>])?
        for fontSize in Self.textSizes where fits(Substring(text), size: fontSize, in: size) {
            result = (fontSize, [text.startIndex..<text.endIndex])
            break
        }
        if result == nil {
            let smallest = Self.textSizes.last!
            result = (smallest, HisnPiPPaginator.pages(text) { fits($0, size: smallest, in: size) })
        }
        layoutCache = (text, result!.size, result!.pages)
        return result!
    }

    private func fits(_ text: Substring, size fontSize: CGFloat, in box: CGSize) -> Bool {
        let measured = attributed(String(text), size: fontSize, weight: .bold, alpha: 1)
            .boundingRect(with: CGSize(width: box.width, height: .greatestFiniteMagnitude),
                          options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return ceil(measured.height) <= box.height
    }

    private func attributed(_ text: String, size: CGFloat, weight: UIFont.Weight, alpha: CGFloat,
                            monospacedDigits: Bool = false) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.baseWritingDirection = .rightToLeft
        para.lineBreakMode = .byWordWrapping
        let font = monospacedDigits ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                                    : UIFont.systemFont(ofSize: size, weight: weight)
        return NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: UIColor(white: 1, alpha: alpha), .paragraphStyle: para,
        ])
    }

    private func draw(_ text: String, size: CGFloat, weight: UIFont.Weight, alpha: CGFloat, in rect: CGRect,
                      lines: Int, monospacedDigits: Bool = false) {
        let string = NSMutableAttributedString(attributedString: attributed(text, size: size, weight: weight,
                                                                            alpha: alpha, monospacedDigits: monospacedDigits))
        let para = (string.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?
            .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        string.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: string.length))
        string.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
    }

    private func stateText(_ state: HisnAudioPlaybackState) -> String {
        switch state {
        case .playing: return "▶︎ يُشغَّل"
        case .paused: return "⏸ متوقف مؤقتًا"
        case .finished: return "■ انتهى التسجيل"
        case .ready: return "■ جاهز"
        case .loading: return "…"
        case .idle, .failed: return "التسجيل غير متوفر"
        }
    }

    private func timeText(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(0, seconds).rounded(.down)).formatted(.time(pattern: .minuteSecond))
    }
}
