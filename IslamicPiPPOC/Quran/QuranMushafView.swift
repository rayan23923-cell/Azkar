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

/// One row's words and verse-end signs, each shaped once with Core Text.
struct ShapedRow {
    struct Piece {
        let line: CTLine
        let width: CGFloat
        let item: QuranMushafLine.Item
    }

    let pieces: [Piece]
    let ascent: CGFloat
    let descent: CGFloat
    var total: CGFloat { pieces.reduce(0) { $0 + $1.width } }

    init(items: [QuranMushafLine.Item], fontSize: CGFloat) {
        let font = MushafFont.font(size: fontSize) ?? CTFontCreateUIFontForLanguage(.system, fontSize, nil)!
        var pieces: [Piece] = []
        for item in items {
            let text: String
            switch item.kind {
            case .word(let word): text = MushafFont.display(word)
            case .verseEnd: text = QuranMushafNames.verseEnd(item.verse.ayah)
            }
            let string = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                // Colour is set when drawing.
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
            ])
            let line = CTLineCreateWithAttributedString(string)
            pieces.append(Piece(line: line, width: CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)), item: item))
        }
        self.pieces = pieces
        ascent = CTFontGetAscent(font)
        descent = CTFontGetDescent(font)
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
    private let footerHeight: CGFloat = 44

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
    private let headerHeight: CGFloat = 34
    private let footerHeight: CGFloat = 44
    /// The printed measure, in ems of the font.
    static let measure: CGFloat = 17

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - horizontalPadding * 2
            let available = geometry.size.height - headerHeight - footerHeight - 16
            let row = max(1, available / 15)
            let fontSize = max(10, min(width / Self.measure, row / 1.7)).rounded(.down)
            let measure = min(width, fontSize * Self.measure)
            let opening = page.number <= 2
            let shaped = source.shapedRows(page.number, fontSize: fontSize)
            VStack(spacing: 0) {
                MushafPageHeader(page: page, palette: palette)
                    .padding(.horizontal, horizontalPadding)
                    .frame(height: headerHeight)
                Spacer(minLength: 0)
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
                .frame(maxWidth: .infinity)
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
            let baseline = size.height / 2 + (row.ascent - row.descent) / 2
            context.withCGContext { cg in
                cg.textMatrix = .identity
                for piece in row.pieces {
                    let width = piece.width * scale
                    x -= width
                    cg.saveGState()
                    cg.setFillColor(color(for: piece.item).cgColor)
                    cg.translateBy(x: x, y: baseline)
                    cg.scaleBy(x: scale, y: -1)
                    cg.textPosition = .zero
                    CTLineDraw(piece.line, cg)
                    cg.restoreGState()
                    x -= gap
                }
            }
        }
        .frame(width: measure)
        .accessibilityHidden(true)
    }

    private func color(for item: QuranMushafLine.Item) -> UIColor {
        if item.verse == highlight { return palette.highlight }
        if item.kind == .verseEnd { return palette.verseEnd }
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

// MARK: - Ornaments (drawn here; no artwork from other apps or printed mushafs)

/// The surah title band: a green panel with a lattice, gold borders, rosettes at both ends and
/// the name in a cartouche.
struct SurahBanner: View {
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
struct PageNumberOrnament: View {
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
