import SwiftUI
import UIKit
import IslamicCore
import ContentKit
import QuranReading
import QuranText

/// How the Quran reader shows the text: verse by verse (the original reader) or as the pages of
/// the Madani mushaf. Stored per device; switched from either reader or from Settings.
enum QuranReadingMode: String, CaseIterable {
    case verses
    case mushaf

    static let key = "quran.readingMode"

    var title: String {
        switch self {
        case .verses: return "آية آية"
        case .mushaf: return "صفحات المصحف"
        }
    }
}

/// How a mushaf page is drawn: line for line as the printed Madina mushaf (15 lines, the
/// DigitalKhatt New Madina font), or flowing (Amiri Quran, at the size that fits the screen).
enum MushafPageStyle: String, CaseIterable {
    case printed
    case flowing

    static let key = "quran.mushafStyle"

    static var current: MushafPageStyle {
        UserDefaults.standard.string(forKey: key).flatMap(MushafPageStyle.init(rawValue:)) ?? .printed
    }

    var title: String {
        switch self {
        case .printed: return "مطابق للمطبوع (١٥ سطراً)"
        case .flowing: return "مرن (خط أميري)"
        }
    }
}

/// The reader for one route: shows the chosen mode, and keeps the place when switching.
struct QuranReadingScreen: View {
    let library: QuranLibrary
    let store: QuranPositionStore
    @AppStorage(QuranReadingMode.key) private var mode: QuranReadingMode = .verses
    @State private var start: QuranVerseRef
    @State private var highlightedAyah: Int?

    init(library: QuranLibrary, start: QuranVerseRef, store: QuranPositionStore, highlightedAyah: Int?) {
        self.library = library
        self.store = store
        _start = State(initialValue: start)
        _highlightedAyah = State(initialValue: highlightedAyah)
    }

    var body: some View {
        switch mode {
        case .verses:
            QuranReaderView(library: library, start: start, store: store, highlightedAyah: highlightedAyah) { ref in
                switchMode(to: .mushaf, at: ref)
            }
            .id("verses-\(start)")
        case .mushaf:
            QuranMushafView(library: library, start: start, store: store, highlightedAyah: highlightedAyah) { ref in
                switchMode(to: .verses, at: ref)
            }
            .id("mushaf-\(start)")
        }
    }

    private func switchMode(to newMode: QuranReadingMode, at ref: QuranVerseRef) {
        start = ref
        highlightedAyah = nil
        mode = newMode
    }
}

/// The Madani mushaf, one page at a time (604 pages), swiped right to left as a printed
/// mushaf turns. Each page carries exactly the verses of its printed page; in the printed style
/// its lines are the printed lines too. The page in view is saved as the reading position.
struct QuranMushafView: View {
    let library: QuranLibrary
    private let store: QuranPositionStore
    private let switchToVerses: (QuranVerseRef) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(MushafPageStyle.key) private var style: MushafPageStyle = .printed
    @State private var page: Int
    @State private var highlight: QuranVerseRef?
    @State private var showsGoTo = false
    @State private var opened = false
    /// Full screen: a tap on the page hides the bars above and below it (and the status bar),
    /// and the page grows into the space; another tap shows them. Remembered between visits.
    @AppStorage("quran.mushafFullScreen") private var fullScreen = false
    /// The verse saved last, used to keep the place when the page style changes.
    @State private var lastRef: QuranVerseRef
    private let start: QuranVerseRef

    init(library: QuranLibrary, start: QuranVerseRef, store: QuranPositionStore, highlightedAyah: Int?,
         switchToVerses: @escaping (QuranVerseRef) -> Void) {
        self.library = library
        self.store = store
        self.switchToVerses = switchToVerses
        self.start = start
        _lastRef = State(initialValue: start)
        let printed = MushafPageStyle.current == .printed && MushafFont.register() ? QuranMushafLayout.madina1421 : nil
        _page = State(initialValue: printed?.page(of: start) ?? library.page(of: start))
        _highlight = State(initialValue: highlightedAyah.map { QuranVerseRef(surah: start.surah, ayah: $0) })
    }

    private var palette: MushafPalette { MushafPalette(colorScheme) }

    /// The printed layout when that style is chosen and its font and data load; its page breaks
    /// are the 1421H print's.
    private var printed: QuranMushafLayout? {
        style == .printed && MushafFont.register() ? QuranMushafLayout.madina1421 : nil
    }

    private var source: MushafPageSource {
        MushafPageSource.shared(library: library, printed: printed != nil)
    }

    private func content(_ number: Int) -> QuranMushafPage? {
        source.page(number)
    }

    private func pageNumber(of ref: QuranVerseRef) -> Int {
        printed?.page(of: ref) ?? library.page(of: ref)
    }

    var body: some View {
        TabView(selection: $page) {
            // Each slot builds its page only when the pager shows it, so turning a page does
            // not rebuild the other 603.
            ForEach(1...library.pageCount, id: \.self) { number in
                MushafPageSlot(number: number, source: source, highlight: highlight, palette: palette)
                    .tag(number)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) { fullScreen.toggle() }
        }
        .accessibilityAction(named: fullScreen ? "إظهار الأشرطة" : "ملء الشاشة") {
            withAnimation(.easeInOut(duration: 0.25)) { fullScreen.toggle() }
        }
        .toolbar(fullScreen ? .hidden : .visible, for: .navigationBar)
        .toolbar(fullScreen ? .hidden : .visible, for: .tabBar)
        .statusBarHidden(fullScreen)
        .persistentSystemOverlays(fullScreen ? .hidden : .automatic)
        .background(palette.paper.ignoresSafeArea())
        .navigationTitle(content(page)?.surahName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showsGoTo = true } label: { Image(systemName: "number") }
                    .accessibilityLabel("الانتقال إلى صفحة")
                Button {
                    switchToVerses(currentRef)
                } label: { Image(systemName: "list.bullet") }
                .accessibilityLabel("عرض الآيات آية آية")
            }
        }
        .sheet(isPresented: $showsGoTo) {
            MushafGoToPage(count: library.pageCount) { page = $0 }
                .presentationDetents([.medium])
        }
        .onAppear {
            // Opening saves the verse opened, as the verse reader does.
            guard !opened else { return }
            opened = true
            store.save(QuranReadingPosition(start, savedAt: Date()))
        }
        .onChange(of: page) { _, _ in pageChanged() }
        .onChange(of: style) { _, _ in
            // The two styles break a few pages differently: stay on the same verse.
            let ref = highlight ?? lastRef
            page = pageNumber(of: ref)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { save() }
        }
        .onDisappear { save() }
        .task(id: highlight) {
            guard highlight != nil else { return }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            highlight = nil
        }
    }

    /// The page's first verse, unless the verse opened is on this page.
    private var currentRef: QuranVerseRef {
        if let highlight, pageNumber(of: highlight) == page { return highlight }
        return (printed?.pageStart(page) ?? library.pageStart(page)) ?? QuranVerseRef(surah: 1, ayah: 1)
    }

    private func pageChanged() {
        save()
        // A surah whose last verse is on the page counts as read today, as in the verse reader.
        lastRef = currentRef
        guard let content = content(page) else { return }
        for section in content.sections where section.endsSurah {
            AppServices.shared.dailyProgress.markCompleted(.quranSurah(section.surah.id), on: DayKey(date: Date()))
        }
    }

    private func save() {
        store.save(QuranReadingPosition(currentRef, savedAt: Date()))
    }
}

/// Builds and keeps pages: their verses, their printed lines, and the shaped words of each line
/// at a font size, so a page already seen is drawn again without shaping its text again.
@MainActor
final class MushafPageSource {
    private static var sources: [Bool: MushafPageSource] = [:]

    /// One source per style for the app's library (the library is the same throughout a run).
    static func shared(library: QuranLibrary, printed: Bool) -> MushafPageSource {
        if let source = sources[printed] { return source }
        let source = MushafPageSource(library: library, printed: printed)
        sources[printed] = source
        return source
    }

    let library: QuranLibrary
    let printed: Bool
    private var pages: [Int: QuranMushafPage] = [:]
    private var lines: [Int: [QuranMushafLine]] = [:]
    private var shaped: [ShapedKey: [ShapedRow?]] = [:]
    private var shapedOrder: [ShapedKey] = []

    private init(library: QuranLibrary, printed: Bool) {
        self.library = library
        self.printed = printed
    }

    func page(_ number: Int) -> QuranMushafPage? {
        if let page = pages[number] { return page }
        let page: QuranMushafPage?
        if printed, let layout = QuranMushafLayout.madina1421 {
            page = library.mushafPage(number, layout: layout)
        } else {
            page = library.mushafPage(number)
        }
        pages[number] = page
        return page
    }

    func lines(_ number: Int) -> [QuranMushafLine]? {
        guard printed else { return nil }
        if let cached = lines[number] { return cached }
        let built = library.mushafLines(number)
        lines[number] = built
        return built
    }

    struct ShapedKey: Hashable {
        let page: Int
        let fontSize: CGFloat
    }

    /// The page's text rows shaped at `fontSize` (nil for title and basmala rows). Only the last
    /// dozen pages are kept.
    func shapedRows(_ number: Int, fontSize: CGFloat) -> [ShapedRow?] {
        let key = ShapedKey(page: number, fontSize: fontSize)
        if let rows = shaped[key] { return rows }
        let rows = (lines(number) ?? []).map { line -> ShapedRow? in
            if case .text(let items) = line.kind { return ShapedRow(items: items, fontSize: fontSize) }
            return nil
        }
        shaped[key] = rows
        shapedOrder.append(key)
        if shapedOrder.count > 12 { shaped[shapedOrder.removeFirst()] = nil }
        return rows
    }
}

/// One row's words and verse-end signs, each shaped once with Core Text. With the ornament
/// artwork, a verse end is the marker image with the verse number shaped on its own; without
/// it, the font's end-of-verse sign.
struct ShapedRow {
    struct Piece {
        let line: CTLine
        let width: CGFloat
        let item: QuranMushafLine.Item
        /// The number's glyph bounds when the piece is drawn as a marker image.
        let markerDigits: CGRect?
    }

    let pieces: [Piece]
    let ascent: CGFloat
    let descent: CGFloat
    /// The marker's side and its centre's height above the baseline: those of the font's sign.
    let markerSize: CGFloat
    let markerCenter: CGFloat
    var total: CGFloat { pieces.reduce(0) { $0 + $1.width } }

    init(items: [QuranMushafLine.Item], fontSize: CGFloat) {
        let font = MushafFont.font(size: fontSize) ?? CTFontCreateUIFontForLanguage(.system, fontSize, nil)!
        let sign = CTLineGetBoundsWithOptions(Self.line("\u{06DD}", font: font), .useGlyphPathBounds)
        let markerSize = max(fontSize * 0.95, max(sign.width, sign.height) * 1.2)
        let usesArt = MushafArt.isAvailable
        let digitFont = CTFontCreateCopyWithAttributes(font, markerSize * 0.5, nil, nil)
        var pieces: [Piece] = []
        for item in items {
            switch item.kind {
            case .word(let word):
                let line = Self.line(MushafFont.display(word), font: font)
                pieces.append(Piece(line: line, width: Self.width(of: line), item: item, markerDigits: nil))
            case .verseEnd where usesArt:
                let line = Self.line(QuranMushafNames.digits(item.verse.ayah), font: digitFont)
                pieces.append(Piece(line: line, width: markerSize, item: item,
                                    markerDigits: CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)))
            case .verseEnd:
                let line = Self.line(QuranMushafNames.verseEnd(item.verse.ayah), font: font)
                pieces.append(Piece(line: line, width: Self.width(of: line), item: item, markerDigits: nil))
            }
        }
        self.pieces = pieces
        ascent = CTFontGetAscent(font)
        descent = CTFontGetDescent(font)
        self.markerSize = markerSize
        markerCenter = sign.isNull || sign.isEmpty ? fontSize * 0.3 : sign.midY
    }

    private static func line(_ text: String, font: CTFont) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            // Colour is set when drawing.
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]))
    }

    private static func width(of line: CTLine) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}

/// A page in the pager: built when shown, from the source's cache.
struct MushafPageSlot: View {
    let number: Int
    let source: MushafPageSource
    let highlight: QuranVerseRef?
    let palette: MushafPalette

    var body: some View {
        if let content = source.page(number) {
            if let lines = source.lines(number) {
                MushafPrintedPageView(page: content, lines: lines, source: source,
                                      highlight: content.holds(highlight) ? highlight : nil, palette: palette)
            } else {
                MushafPageView(page: content, highlight: highlight, palette: palette)
            }
        }
    }
}

private extension QuranMushafPage {
    func holds(_ ref: QuranVerseRef?) -> Bool {
        guard let ref else { return false }
        return contains(ref)
    }
}

// MARK: - Page

struct MushafPalette {
    let paper: Color
    let ink: UIColor
    let verseEnd: UIColor
    let highlight: UIColor
    let gold: Color
    let green: Color
    let greenDeep: Color
    let rose: Color

    init(_ scheme: ColorScheme) {
        if scheme == .dark {
            paper = Color(red: 0.10, green: 0.10, blue: 0.09)
            ink = UIColor(red: 0.93, green: 0.90, blue: 0.83, alpha: 1)
            verseEnd = UIColor(red: 0.55, green: 0.80, blue: 0.62, alpha: 1)
            highlight = UIColor(red: 0.95, green: 0.78, blue: 0.40, alpha: 1)
            gold = Color(red: 0.80, green: 0.66, blue: 0.36)
            green = Color(red: 0.20, green: 0.38, blue: 0.27)
            greenDeep = Color(red: 0.12, green: 0.25, blue: 0.17)
            rose = Color(red: 0.78, green: 0.55, blue: 0.62)
        } else {
            paper = Color(red: 0.99, green: 0.97, blue: 0.92)
            ink = UIColor(red: 0.10, green: 0.09, blue: 0.07, alpha: 1)
            verseEnd = UIColor(red: 0.16, green: 0.42, blue: 0.27, alpha: 1)
            highlight = UIColor(red: 0.70, green: 0.42, blue: 0.05, alpha: 1)
            gold = Color(red: 0.72, green: 0.56, blue: 0.24)
            green = Color(red: 0.42, green: 0.66, blue: 0.45)
            greenDeep = Color(red: 0.20, green: 0.45, blue: 0.28)
            rose = Color(red: 0.86, green: 0.55, blue: 0.66)
        }
    }
}

/// One page: juz and surah on top, the verses, the page number below.
struct MushafPageView: View {
    let page: QuranMushafPage
    let highlight: QuranVerseRef?
    let palette: MushafPalette

    private let horizontalPadding: CGFloat = 18
    private let headerHeight: CGFloat = 34
    private let footerHeight: CGFloat = 52

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - horizontalPadding * 2
            let available = geometry.size.height - headerHeight - footerHeight - 16
            let layout = MushafLayout(page: page, width: width, height: available, highlight: highlight, palette: palette)
            VStack(spacing: 0) {
                MushafPageHeader(page: page, palette: palette)
                    .padding(.horizontal, horizontalPadding)
                    .frame(height: headerHeight)
                Spacer(minLength: 0)
                VStack(spacing: layout.fontSize * 0.25) {
                    ForEach(Array(layout.blocks.enumerated()), id: \.offset) { _, block in
                        switch block {
                        case .banner(let name):
                            SurahBanner(name: name, palette: palette)
                                .frame(height: layout.bannerHeight)
                        case .basmala(let text):
                            Text(text)
                                .font(.custom(QuranFont.postScriptName, size: layout.fontSize))
                                .foregroundStyle(Color(palette.ink))
                                .frame(maxWidth: .infinity)
                                .frame(height: layout.basmalaHeight)
                        case .text(let attributed, let height):
                            JustifiedText(text: attributed)
                                .frame(width: width, height: height)
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                Spacer(minLength: 0)
                PageNumberOrnament(number: page.number, palette: palette)
                    .frame(height: footerHeight)
            }
            .padding(.bottom, 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("الصفحة \(page.number)، \(QuranMushafNames.juz(page.juz))، سورة \(page.surahName)")
        .accessibilityValue(page.sections.flatMap(\.verses).map(\.arabicText).joined(separator: " "))
    }

}

/// The juz and the surah, above the page.
struct MushafPageHeader: View {
    let page: QuranMushafPage
    let palette: MushafPalette

    var body: some View {
        HStack {
            Text(QuranMushafNames.juz(page.juz))
            Spacer()
            Text(page.surahName)
        }
        .font(.custom(QuranFont.postScriptName, size: 17))
        .foregroundStyle(Color(palette.ink).opacity(0.8))
    }
}

/// A page line for line as printed: 15 rows (8 on the first two pages), each a title band, the
/// basmala, or words spread across the measure. A row too long for the measure at the chosen
/// size is narrowed horizontally instead of wrapping, so no row ever breaks differently from
/// the print.
struct MushafPrintedPageView: View {
    let page: QuranMushafPage
    let lines: [QuranMushafLine]
    let source: MushafPageSource
    let highlight: QuranVerseRef?
    let palette: MushafPalette

    private let horizontalPadding: CGFloat = 14
    private let framePadding: CGFloat = 6
    private let headerHeight: CGFloat = 34
    private let footerHeight: CGFloat = 56
    /// The printed measure, in ems of the font.
    static let measure: CGFloat = 17

    var body: some View {
        GeometryReader { geometry in
            // With the artwork the lines sit inside the page frame, scaled to the screen.
            let framed = MushafArt.isAvailable
            let frameWidth = geometry.size.width - framePadding * 2
            let frameScale = framed ? min(0.85, max(0.45, frameWidth / 620)) : 0
            let inset = CGSize(width: MushafArt.frameTextInsets.width * frameScale,
                               height: MushafArt.frameTextInsets.height * frameScale)
            let width = framed ? frameWidth - inset.width * 2 : geometry.size.width - horizontalPadding * 2
            let frameHeight = geometry.size.height - headerHeight - footerHeight - 8
            let available = framed ? frameHeight - inset.height * 2 : frameHeight - 8
            let row = max(1, available / 15)
            let fontSize = max(10, min(width / Self.measure, row / 1.7)).rounded(.down)
            let measure = min(width, fontSize * Self.measure)
            let opening = page.number <= 2
            let shaped = source.shapedRows(page.number, fontSize: fontSize)
            VStack(spacing: 0) {
                MushafPageHeader(page: page, palette: palette)
                    .padding(.horizontal, horizontalPadding)
                    .frame(height: headerHeight)
                ZStack {
                    if framed {
                        MushafPageFrame(scale: frameScale)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            switch line.kind {
                            case .surahTitle(let surah):
                                SurahBanner(name: "سورة \(surah.nameArabic)", palette: palette)
                                    .frame(width: measure, height: row * 0.9)
                                    .frame(height: row)
                            case .basmala(let text):
                                Text(MushafFont.display(text))
                                    .font(.custom(MushafFont.postScriptName, fixedSize: fontSize))
                                    .foregroundStyle(Color(palette.ink))
                                    .fixedSize()
                                    .frame(width: measure, height: row)
                            case .text:
                                if index < shaped.count, let shapedRow = shaped[index] {
                                    MushafPrintedLine(row: shapedRow, fontSize: fontSize, measure: measure, centered: opening,
                                                      highlight: highlight, palette: palette)
                                        .frame(width: measure, height: row)
                                }
                            }
                        }
                    }
                }
                .frame(width: framed ? frameWidth : nil, height: frameHeight)
                .frame(maxWidth: .infinity)
                PageNumberOrnament(number: page.number, palette: palette)
                    .frame(height: footerHeight)
            }
            .padding(.bottom, 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("الصفحة \(page.number)، \(QuranMushafNames.juz(page.juz))، سورة \(page.surahName)")
        .accessibilityValue(page.sections.flatMap(\.verses).map(\.arabicText).joined(separator: " "))
    }
}

/// One printed row of words and verse-end signs, right to left, the space between words
/// stretched to fill the measure (the first two pages are centred, as printed). Drawn in one
/// Canvas from words already shaped, so a page turn costs no text layout.
struct MushafPrintedLine: View {
    let row: ShapedRow
    let fontSize: CGFloat
    let measure: CGFloat
    let centered: Bool
    let highlight: QuranVerseRef?
    let palette: MushafPalette

    var body: some View {
        Canvas { context, size in
            let total = row.total
            let gaps = CGFloat(max(0, row.pieces.count - 1))
            let minimumGap = fontSize * 0.12
            let scale = min(1, size.width / max(1, total + minimumGap * gaps))
            let gap = centered || gaps == 0 ? fontSize * 0.3 : max(0, (size.width - total * scale) / gaps)
            let used = total * scale + gap * gaps
            // Right to left: the first piece at the right edge (centred rows start inset).
            var x = centered ? (size.width + used) / 2 : size.width
            var origins: [CGFloat] = []
            for piece in row.pieces {
                x -= piece.width * scale
                origins.append(x)
                x -= gap
            }
            let baseline = size.height / 2 + (row.ascent - row.descent) / 2
            let markerY = baseline - row.markerCenter
            let marker = context.resolve(Image(MushafArt.verseMarker))
            for (piece, origin) in zip(row.pieces, origins) where piece.markerDigits != nil {
                let side = row.markerSize
                context.draw(marker, in: CGRect(x: origin + (piece.width * scale - side) / 2, y: markerY - side / 2,
                                                width: side, height: side))
            }
            context.withCGContext { cg in
                cg.textMatrix = .identity
                for (piece, origin) in zip(row.pieces, origins) {
                    cg.saveGState()
                    cg.setFillColor(color(for: piece.item).cgColor)
                    if let digits = piece.markerDigits {
                        // The number centred in the marker's inner circle.
                        let fit = min(1, row.markerSize * 0.62 / max(1, digits.width))
                        cg.translateBy(x: origin + piece.width * scale / 2 - digits.midX * fit, y: markerY + digits.midY)
                        cg.scaleBy(x: fit, y: -1)
                    } else {
                        cg.translateBy(x: origin, y: baseline)
                        cg.scaleBy(x: scale, y: -1)
                    }
                    cg.textPosition = .zero
                    CTLineDraw(piece.line, cg)
                    cg.restoreGState()
                }
            }
        }
        .frame(width: measure)
        .accessibilityHidden(true)
    }

    private func color(for item: QuranMushafLine.Item) -> UIColor {
        if item.verse == highlight { return palette.highlight }
        if item.kind == .verseEnd { return MushafArt.isAvailable ? palette.ink : palette.verseEnd }
        return palette.ink
    }
}

/// The page's blocks and the largest font size (14...30) at which they fit the space.
struct MushafLayout {
    enum Block {
        case banner(String)
        case basmala(String)
        case text(NSAttributedString, height: CGFloat)
    }

    private(set) var blocks: [Block] = []
    private(set) var fontSize: CGFloat = 14
    var bannerHeight: CGFloat { max(36, fontSize * 1.75) }
    var basmalaHeight: CGFloat { fontSize * 2.0 }

    init(page: QuranMushafPage, width: CGFloat, height: CGFloat, highlight: QuranVerseRef?, palette: MushafPalette) {
        guard width > 0, height > 0 else { return }
        QuranFont.register()
        var size: CGFloat = 30
        while size >= 14 {
            let candidate = Self.makeBlocks(page, size: size, width: width, highlight: highlight, palette: palette)
            if Self.totalHeight(of: candidate, size: size) <= height || size <= 14 {
                blocks = candidate
                fontSize = size
                return
            }
            size -= 1
        }
    }

    private static func totalHeight(of blocks: [Block], size: CGFloat) -> CGFloat {
        let spacing = size * 0.25 * CGFloat(max(0, blocks.count - 1))
        return blocks.reduce(spacing) { total, block in
            switch block {
            case .banner: return total + max(36, size * 1.75)
            case .basmala: return total + size * 2.0
            case .text(_, let height): return total + height
            }
        }
    }

    private static func makeBlocks(_ page: QuranMushafPage, size: CGFloat, width: CGFloat, highlight: QuranVerseRef?,
                               palette: MushafPalette) -> [Block] {
        let font = UIFont(name: QuranFont.postScriptName, size: size) ?? .systemFont(ofSize: size)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .justified
        paragraph.baseWritingDirection = .rightToLeft
        paragraph.lineSpacing = size * 0.30
        var result: [Block] = []
        for section in page.sections {
            if section.startsSurah {
                result.append(.banner("سورة \(section.surah.nameArabic)"))
                if let bismillah = section.surah.bismillah { result.append(.basmala(bismillah)) }
            }
            let text = NSMutableAttributedString()
            for verse in section.verses {
                let isHighlighted = highlight == QuranVerseRef(surah: verse.surahId, ayah: verse.ayahNumber)
                text.append(NSAttributedString(string: verse.arabicText, attributes: [
                    .font: font, .foregroundColor: isHighlighted ? palette.highlight : palette.ink, .paragraphStyle: paragraph,
                ]))
                text.append(NSAttributedString(string: "\u{00A0}" + QuranMushafNames.verseEnd(verse.ayahNumber) + " ", attributes: [
                    .font: font, .foregroundColor: palette.verseEnd, .paragraphStyle: paragraph,
                ]))
            }
            let bounds = text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            result.append(.text(text, height: ceil(bounds.height) + 2))
        }
        return result
    }
}

/// Justified right-to-left text (SwiftUI's Text cannot justify).
struct JustifiedText: UIViewRepresentable {
    let text: NSAttributedString

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return label
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.attributedText = text
    }
}

// MARK: - Ornament artwork

/// The mushaf ornaments supplied by the app's owner (Assets.xcassets, each with a dark
/// variant): the surah band, cut in three pieces so it stretches to any width; the page frame,
/// cut into a corner, two edge tiles and a middle ornament; the page-number medallion; and the
/// verse marker. Sizes are in pixels of the artwork (1x images).
enum MushafArt {
    static let bandEnd = "MushafBandEnd"
    static let bandSegment = "MushafBandSegment"
    static let bandCartouche = "MushafBandCartouche"
    static let frameCorner = "MushafFrameCorner"
    static let frameEdgeTop = "MushafFrameEdgeTop"
    static let frameEdgeSide = "MushafFrameEdgeSide"
    static let frameMid = "MushafFrameMid"
    static let pageMedallion = "MushafPageMedallion"
    static let verseMarker = "MushafVerseMarker"

    private static let all = [bandEnd, bandSegment, bandCartouche, frameCorner, frameEdgeTop, frameEdgeSide, frameMid,
                              pageMedallion, verseMarker]
    static let isAvailable = all.allSatisfy { UIImage(named: $0) != nil }

    static func size(_ name: String) -> CGSize { UIImage(named: name)?.size ?? .zero }

    /// Where text may start inside the frame: past the side band, and below the top band and
    /// the corner ornaments.
    static let frameTextInsets = CGSize(width: 50, height: 82)
    /// The middle of the frame's band, from its outer edge (the frame's outer line is 15
    /// pixels in; the band is 28 pixels wide).
    static let frameBandMiddle: CGFloat = 30
}

/// The surah title band; the drawn one without the artwork.
struct SurahBanner: View {
    let name: String
    let palette: MushafPalette

    var body: some View {
        if MushafArt.isAvailable {
            SurahBand(name: name, palette: palette)
        } else {
            DrawnSurahBanner(name: name, palette: palette)
        }
    }
}

/// The page number; the drawn one without the artwork.
struct PageNumberOrnament: View {
    let number: Int
    let palette: MushafPalette

    var body: some View {
        if MushafArt.isAvailable {
            PageMedallion(number: number, palette: palette)
        } else {
            DrawnPageNumber(number: number, palette: palette)
        }
    }
}

/// The surah band from the artwork: an end piece on each side, the floral segment repeated
/// (every other copy mirrored, so the copies meet seamlessly) and the cartouche with the name
/// in the middle. Only the segments stretch, a little, to fill the width.
struct SurahBand: View {
    let name: String
    let palette: MushafPalette

    private struct Geometry {
        let scale: CGFloat
        let top: CGFloat
        let height: CGFloat
        let endWidth: CGFloat
        let cartoucheWidth: CGFloat
        let segments: Int
        let segmentWidth: CGFloat
        let left: CGFloat

        init(size: CGSize) {
            let end = MushafArt.size(MushafArt.bandEnd)
            let segment = MushafArt.size(MushafArt.bandSegment)
            let cartouche = MushafArt.size(MushafArt.bandCartouche)
            let fixed = end.width * 2 + cartouche.width
            scale = min(size.height / max(1, cartouche.height), size.width / max(1, fixed))
            height = cartouche.height * scale
            top = (size.height - height) / 2
            endWidth = end.width * scale
            cartoucheWidth = cartouche.width * scale
            let side = (size.width - fixed * scale) / 2
            let natural = segment.width * scale
            segments = natural > 0 && side >= natural * 0.5 ? max(1, Int((side / natural).rounded())) : 0
            segmentWidth = segments > 0 ? side / CGFloat(segments) : 0
            left = segments > 0 ? 0 : max(0, side)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let geometry = Geometry(size: proxy.size)
            ZStack {
                Canvas { context, size in
                    let geometry = Geometry(size: size)
                    let end = context.resolve(Image(MushafArt.bandEnd))
                    let segment = context.resolve(Image(MushafArt.bandSegment))
                    let cartouche = context.resolve(Image(MushafArt.bandCartouche))
                    for mirrored in [false, true] {
                        var half = context
                        if mirrored {
                            half.translateBy(x: size.width, y: 0)
                            half.scaleBy(x: -1, y: 1)
                        }
                        for index in 0..<geometry.segments {
                            // A hair wider, so neighbouring copies leave no seam.
                            let rect = CGRect(x: geometry.left + geometry.endWidth + CGFloat(index) * geometry.segmentWidth,
                                              y: geometry.top, width: geometry.segmentWidth + 0.5, height: geometry.height)
                            MushafArtDrawing.draw(segment, in: rect, flipX: index % 2 == 1, context: half)
                        }
                        half.draw(end, in: CGRect(x: geometry.left, y: geometry.top, width: geometry.endWidth,
                                                  height: geometry.height))
                    }
                    context.draw(cartouche, in: CGRect(x: (size.width - geometry.cartoucheWidth) / 2, y: geometry.top,
                                                       width: geometry.cartoucheWidth, height: geometry.height))
                }
                Text(name)
                    .font(.custom(QuranFont.postScriptName, size: geometry.height * 0.36))
                    .foregroundStyle(Color(palette.ink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: geometry.cartoucheWidth * 0.68, height: geometry.height * 0.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The page number in the medallion from the artwork.
struct PageMedallion: View {
    let number: Int
    let palette: MushafPalette

    var body: some View {
        GeometryReader { proxy in
            let size = MushafArt.size(MushafArt.pageMedallion)
            let height = min(proxy.size.height, proxy.size.width * size.height / max(1, size.width))
            ZStack {
                Image(MushafArt.pageMedallion)
                    .resizable()
                    .scaledToFit()
                Text(QuranMushafNames.digits(number))
                    .font(.custom(QuranFont.postScriptName, size: height * 0.32).bold())
                    .foregroundStyle(Color(palette.ink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: height * 0.42)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("الصفحة \(number)")
    }
}

/// The page frame from the artwork: a corner in each corner (mirrored), the edge tiles repeated
/// between them, and the middle ornament at the middle of each side. `scale` is points per
/// pixel of the artwork.
struct MushafPageFrame: View {
    let scale: CGFloat

    var body: some View {
        Canvas { context, size in
            let corner = context.resolve(Image(MushafArt.frameCorner))
            let top = context.resolve(Image(MushafArt.frameEdgeTop))
            let side = context.resolve(Image(MushafArt.frameEdgeSide))
            let middle = context.resolve(Image(MushafArt.frameMid))
            let cornerSize = CGSize(width: corner.size.width * scale, height: corner.size.height * scale)
            let topSize = CGSize(width: top.size.width * scale, height: top.size.height * scale)
            let sideSize = CGSize(width: side.size.width * scale, height: side.size.height * scale)

            // Edges first, tiled between the corners and clipped there.
            for bottom in [false, true] {
                var edge = context
                let y = bottom ? size.height - topSize.height : 0
                edge.clip(to: Path(CGRect(x: cornerSize.width, y: y, width: max(0, size.width - cornerSize.width * 2),
                                          height: topSize.height)))
                var x = cornerSize.width
                while x < size.width - cornerSize.width {
                    MushafArtDrawing.draw(top, in: CGRect(x: x, y: y, width: topSize.width + 0.5, height: topSize.height),
                                          flipY: bottom, context: edge)
                    x += topSize.width
                }
            }
            for right in [false, true] {
                var edge = context
                let x = right ? size.width - sideSize.width : 0
                edge.clip(to: Path(CGRect(x: x, y: cornerSize.height, width: sideSize.width,
                                          height: max(0, size.height - cornerSize.height * 2))))
                var y = cornerSize.height
                while y < size.height - cornerSize.height {
                    MushafArtDrawing.draw(side, in: CGRect(x: x, y: y, width: sideSize.width, height: sideSize.height + 0.5),
                                          flipX: right, context: edge)
                    y += sideSize.height
                }
            }
            for (right, bottom) in [(false, false), (true, false), (false, true), (true, true)] {
                let rect = CGRect(x: right ? size.width - cornerSize.width : 0, y: bottom ? size.height - cornerSize.height : 0,
                                  width: cornerSize.width, height: cornerSize.height)
                MushafArtDrawing.draw(corner, in: rect, flipX: right, flipY: bottom, context: context)
            }
            // The middle ornaments, centred on the band.
            let band = MushafArt.frameBandMiddle * scale
            let middleSize = CGSize(width: middle.size.width * scale, height: middle.size.height * scale)
            let centres = [CGPoint(x: size.width / 2, y: band), CGPoint(x: size.width / 2, y: size.height - band),
                           CGPoint(x: band, y: size.height / 2), CGPoint(x: size.width - band, y: size.height / 2)]
            for (index, centre) in centres.enumerated() {
                var ornament = context
                ornament.translateBy(x: centre.x, y: centre.y)
                if index >= 2 { ornament.rotate(by: .degrees(90)) }
                if index == 1 { ornament.scaleBy(x: 1, y: -1) }
                ornament.draw(middle, in: CGRect(x: -middleSize.width / 2, y: -middleSize.height / 2,
                                                 width: middleSize.width, height: middleSize.height))
            }
        }
        .accessibilityHidden(true)
    }
}

enum MushafArtDrawing {
    /// Draws `image` in `rect`, mirrored about the rect's centre if asked.
    static func draw(_ image: GraphicsContext.ResolvedImage, in rect: CGRect, flipX: Bool = false, flipY: Bool = false,
                     context: GraphicsContext) {
        var flipped = context
        flipped.translateBy(x: rect.midX, y: rect.midY)
        flipped.scaleBy(x: flipX ? -1 : 1, y: flipY ? -1 : 1)
        flipped.draw(image, in: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height))
    }
}

// MARK: - Ornaments drawn in code (used when the artwork is missing)

/// The surah title band: a green panel with a lattice, gold borders, rosettes at both ends and
/// the name in a cartouche.
struct DrawnSurahBanner: View {
    let name: String
    let palette: MushafPalette

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [palette.green, palette.greenDeep], startPoint: .top, endPoint: .bottom))
                Canvas { context, canvas in
                    // Lattice of small diamonds.
                    let step = canvas.height / 3
                    var x: CGFloat = step / 2
                    while x < canvas.width {
                        for row in 0..<3 {
                            let y = step / 2 + CGFloat(row) * step
                            var diamond = Path()
                            diamond.move(to: CGPoint(x: x, y: y - step * 0.32))
                            diamond.addLine(to: CGPoint(x: x + step * 0.32, y: y))
                            diamond.addLine(to: CGPoint(x: x, y: y + step * 0.32))
                            diamond.addLine(to: CGPoint(x: x - step * 0.32, y: y))
                            diamond.closeSubpath()
                            context.stroke(diamond, with: .color(palette.gold.opacity(0.45)), lineWidth: 0.7)
                        }
                        x += step
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 3))
                RoundedRectangle(cornerRadius: 3).strokeBorder(palette.gold, lineWidth: 2)
                RoundedRectangle(cornerRadius: 2).inset(by: 4).strokeBorder(palette.gold.opacity(0.7), lineWidth: 0.8)
                HStack {
                    Rosette(palette: palette).frame(width: size.height * 0.7, height: size.height * 0.7)
                    Spacer()
                    Rosette(palette: palette).frame(width: size.height * 0.7, height: size.height * 0.7)
                }
                .padding(.horizontal, size.height * 0.35)
                Capsule()
                    .fill(palette.paper)
                    .overlay(Capsule().strokeBorder(palette.gold, lineWidth: 1.4))
                    .frame(width: size.width * 0.52, height: size.height * 0.68)
                Text(name)
                    .font(.custom(QuranFont.postScriptName, size: size.height * 0.38))
                    .foregroundStyle(Color(palette.ink))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: size.width * 0.46)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityAddTraits(.isHeader)
    }
}

/// An eight-petal rosette.
struct Rosette: View {
    let palette: MushafPalette

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            for index in 0..<8 {
                let angle = Double(index) * .pi / 4
                var petal = Path(ellipseIn: CGRect(x: -radius * 0.18, y: -radius * 0.95, width: radius * 0.36, height: radius * 0.62))
                petal = petal.applying(CGAffineTransform(rotationAngle: angle))
                    .applying(CGAffineTransform(translationX: center.x, y: center.y))
                context.fill(petal, with: .color(palette.rose.opacity(0.9)))
                context.stroke(petal, with: .color(palette.gold), lineWidth: 0.6)
            }
            let inner = Path(ellipseIn: CGRect(x: center.x - radius * 0.3, y: center.y - radius * 0.3,
                                               width: radius * 0.6, height: radius * 0.6))
            context.fill(inner, with: .color(palette.paper))
            context.stroke(inner, with: .color(palette.gold), lineWidth: 0.8)
        }
    }
}

/// The page number in a gold cartouche with leaves on both sides.
struct DrawnPageNumber: View {
    let number: Int
    let palette: MushafPalette

    var body: some View {
        HStack(spacing: 6) {
            leaf
            Text(QuranMushafNames.digits(number))
                .font(.custom(QuranFont.postScriptName, size: 17))
                .foregroundStyle(Color(palette.ink))
                .frame(minWidth: 56)
                .padding(.vertical, 2)
                .background(Capsule().fill(palette.paper))
                .overlay(Capsule().strokeBorder(palette.gold, lineWidth: 1.2))
                .overlay(Capsule().inset(by: 3).strokeBorder(palette.gold.opacity(0.5), lineWidth: 0.6))
            leaf.scaleEffect(x: -1, y: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("الصفحة \(number)")
    }

    private var leaf: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addQuadCurve(to: CGPoint(x: size.width, y: size.height / 2), control: CGPoint(x: size.width / 2, y: 0))
            path.addQuadCurve(to: CGPoint(x: 0, y: size.height / 2), control: CGPoint(x: size.width / 2, y: size.height))
            context.fill(path, with: .color(palette.green.opacity(0.8)))
            context.stroke(path, with: .color(palette.gold), lineWidth: 0.7)
        }
        .frame(width: 26, height: 14)
    }
}

/// Picks a page number.
private struct MushafGoToPage: View {
    let count: Int
    let go: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var page: Int? {
        let western = String(text.map { ch -> Character in
            if let value = ch.wholeNumberValue { return Character(String(value)) }
            return ch
        })
        guard let number = Int(western), (1...count).contains(number) else { return nil }
        return number
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("رقم الصفحة (1 إلى \(count))", text: $text)
                    .keyboardType(.numberPad)
                    .accessibilityLabel("رقم الصفحة")
                if !text.isEmpty && page == nil {
                    Text("أدخل رقماً من 1 إلى \(count).").foregroundStyle(.red)
                }
            }
            .navigationTitle("الانتقال إلى صفحة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("انتقال") {
                        if let page { go(page); dismiss() }
                    }
                    .disabled(page == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}
