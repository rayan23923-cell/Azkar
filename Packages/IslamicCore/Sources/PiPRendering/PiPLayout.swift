import CoreGraphics
import Foundation

/// Where everything goes in a PiP frame of a given size, in top-left coordinates.
///
/// iOS draws its own controls over a sample-buffer PiP window and the app cannot move, resize
/// or remove them: close and return-to-app in the top corners, skip back / play-pause / skip
/// forward in a row across the middle, and the progress bar along the bottom. They show when
/// the window is tapped and the system hides them again. Their places here were measured on an
/// iPhone screenshot of the 9:16 window (2026-10-09), with a margin, as fractions of the
/// window's width; the controls keep their size in points, so in a smaller window they cover
/// more and these places are an estimate, not a guarantee.
///
/// The header, the counter and the information line never sit under a control. In a portrait
/// window the text is kept to the upper half, between the corner controls and the middle row,
/// and the counter goes in large type below the middle row; nothing is drawn where a control
/// shows. A landscape window is too short for that: the text is one block from the header to
/// the information line, and the middle row covers its centre while the controls are shown.
///
/// Every measure is a fraction of the frame's shorter side, so a layout is the same at any
/// scale.
public struct PiPLayout: Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
    }

    /// 16:9, the size the sample-buffer PiP path was proven with on a device.
    public static let landscape = PiPLayout(width: 1280, height: 720)
    /// 9:16. The window takes the shape of the frames, so this gives a portrait window. Not
    /// yet run on a device.
    public static let portrait = PiPLayout(width: 720, height: 1280)
    /// The default: what the app draws unless the user picks portrait.
    public static let production = landscape

    /// The window shape the user picks in Settings («اتجاه النافذة العائمة»). Landscape is the
    /// default; portrait is offered for testing on a device.
    public enum Orientation: String, CaseIterable, Sendable {
        case landscape
        case portrait

        public var title: String {
            switch self {
            case .landscape: return "أفقي"
            case .portrait: return "عمودي (تجريبي)"
            }
        }

        public var layout: PiPLayout {
            switch self {
            case .landscape: return .landscape
            case .portrait: return .portrait
            }
        }
    }

    /// The UserDefaults key of the orientation setting.
    public static let orientationKey = "pip.orientation"

    /// The layout for the saved setting; landscape when it is missing or unknown.
    public static func saved(in defaults: UserDefaults = .standard) -> PiPLayout {
        (defaults.string(forKey: orientationKey).flatMap(Orientation.init(rawValue:)) ?? .landscape).layout
    }

    public var isPortrait: Bool { height > width }
    public var size: CGSize { CGSize(width: width, height: height) }
    public var bounds: CGRect { CGRect(origin: .zero, size: size) }
    /// The shorter side: the unit every measure is a fraction of.
    public var unit: CGFloat { CGFloat(min(width, height)) }
    var margin: CGFloat { (unit * 0.045).rounded() }

    // MARK: System controls (reserved)

    /// Close (top left) and return to the app (top right); both reserved, as their sides swap
    /// with the system language.
    public var cornerControls: [CGRect] {
        // Measured: buttons 0.13 W across, their bottom at 0.18 W.
        let size = CGSize(width: unit * 0.22, height: unit * 0.19)
        return [CGRect(origin: .zero, size: size),
                CGRect(origin: CGPoint(x: CGFloat(width) - size.width, y: 0), size: size)]
    }

    /// Skip back, play / pause, skip forward.
    public var centerControls: CGRect {
        // Measured: 0.05 W to 0.95 W across, 0.26 W tall, centred.
        let size = CGSize(width: min(CGFloat(width) * 0.96, unit * 1.0), height: unit * 0.29)
        return CGRect(x: (CGFloat(width) - size.width) / 2, y: (CGFloat(height) - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// The system progress bar.
    public var progressControl: CGRect {
        // Measured: the bar's top 0.14 W above the bottom.
        let height = unit * 0.15
        return CGRect(x: 0, y: CGFloat(self.height) - height, width: CGFloat(width), height: height)
    }

    public var systemControls: [CGRect] { cornerControls + [centerControls, progressControl] }

    // MARK: Content

    /// Space kept between a part and a system control.
    var gap: CGFloat { (unit * 0.02).rounded() }
    /// The bottom of the corner controls.
    var cornersBottom: CGFloat { cornerControls.map(\.maxY).max() ?? 0 }

    /// Title and subtitle, between the corner controls.
    public var header: CGRect {
        let side = unit * 0.22 + gap
        return CGRect(x: side, y: margin * 0.6, width: CGFloat(width) - 2 * side, height: unit * 0.085)
    }

    /// The counter («التكرار 37 من 100»), in large type. Portrait: centred in the space between
    /// the middle row and the information line, so the upper half is all text. Landscape: above
    /// the text, under the header between the corner controls in a wide window, across the
    /// window under the corner controls in a narrow one (between them it would have to shrink).
    public var counter: CGRect {
        if isPortrait {
            let height = unit * 0.13
            let top = centerControls.maxY + gap
            let space = info.minY - gap - top
            return CGRect(x: margin, y: top + max(0, (space - height) / 2), width: CGFloat(width) - 2 * margin,
                          height: min(height, space))
        }
        let height = unit * 0.09
        if header.width >= unit * 1.1 {
            return CGRect(x: header.minX, y: header.maxY + gap / 2, width: header.width, height: height)
        }
        return CGRect(x: margin, y: cornersBottom + gap, width: CGFloat(width) - 2 * margin, height: height)
    }

    /// Position, page and what play / pause does next, just above the system progress bar.
    public var info: CGRect {
        let height = unit * 0.075
        return CGRect(x: margin, y: progressControl.minY - gap - height, width: CGFloat(width) - 2 * margin,
                      height: height)
    }

    /// The frame's own progress line, inside the system progress bar's place (it says nothing
    /// essential, so being covered while the controls show costs nothing).
    public var progressLine: CGRect {
        CGRect(x: margin, y: CGFloat(height) - unit * 0.05, width: CGFloat(width) - 2 * margin, height: unit * 0.011)
    }

    /// The text area. Portrait: the upper half, from under the corner controls to just above
    /// the middle row (the counter is below the row, so it takes nothing from here). Landscape:
    /// from under the header (and counter) to the information line.
    public func body(withCounter: Bool) -> CGRect {
        if isPortrait {
            let top = max(header.maxY, cornersBottom) + gap
            return CGRect(x: margin, y: top, width: CGFloat(width) - 2 * margin,
                          height: centerControls.minY - gap - top)
        }
        let top = max(withCounter ? counter.maxY : header.maxY, cornersBottom) + gap
        return CGRect(x: margin, y: top, width: CGFloat(width) - 2 * margin, height: info.minY - gap - top)
    }

    /// Where the text is drawn: the one text area. Kept as a list for the renderer and the
    /// paginator, which place text block by block.
    public func textBlocks(withCounter: Bool) -> [CGRect] { [body(withCounter: withCounter)] }

    /// The text is clear of the middle control row (portrait).
    public var textAvoidsCenterControls: Bool { body(withCounter: true).maxY <= centerControls.minY }

    // MARK: Type sizes, largest first

    /// Body sizes: the largest that fits on one page is used; a longer text is paged at the
    /// smallest, which stays readable in a small window.
    public var bodySizes: [CGFloat] { [0.135, 0.12, 0.105, 0.095, 0.086].map { (unit * $0).rounded() } }
    var headerSizes: [CGFloat] { [0.05, 0.044, 0.038, 0.032].map { (unit * $0).rounded() } }
    var counterSizes: [CGFloat] {
        // Portrait has a band of its own for the counter, so it is drawn larger there.
        (isPortrait ? [0.09, 0.078, 0.066, 0.056, 0.046, 0.038] : [0.064, 0.056, 0.048, 0.041, 0.034])
            .map { (unit * $0).rounded() }
    }
    var infoSizes: [CGFloat] { [0.042, 0.037, 0.032, 0.028].map { (unit * $0).rounded() } }
}
