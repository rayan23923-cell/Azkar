import Foundation
import IslamicCore

/// One line of a printed mushaf page: a surah title band, the basmala, or a run of words.
public struct QuranMushafLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case surahTitle(QuranSurah)
        case basmala(String)
        case text([Item])
    }

    /// A word of a verse (with any pause marks that follow it), or a verse's end sign.
    public struct Item: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case word(String)
            case verseEnd
        }

        public let kind: Kind
        public let verse: QuranVerseRef
    }

    public let kind: Kind
}

/// Where each line of the Madina mushaf (King Fahd Complex, 1421H print: 15 lines, 604 pages)
/// starts, from `MushafLines-Madina1421.txt` (see `MushafLines-NOTICE.txt`). The words are cut
/// from the bundled Tanzil text: joined back with spaces they give each verse unchanged.
/// Its page breaks are the 1421H print's; on 25 pages they differ by a few verses from the
/// Tanzil page metadata (an earlier print), so pages in this layout are numbered by it.
public struct QuranMushafLayout: Sendable {
    enum Entry: Equatable, Sendable {
        case title(Int)
        case basmala
        case line(QuranVerseRef, word: Int)
    }

    let pages: [[Entry]]
    /// The first verse of each page (every printed page starts with a verse's first word).
    public let pageStarts: [QuranVerseRef]

    public var pageCount: Int { pages.count }

    /// The page (1...604) carrying a verse.
    public func page(of ref: QuranVerseRef) -> Int {
        QuranLibrary.index(of: ref, in: pageStarts) + 1
    }

    public func pageStart(_ page: Int) -> QuranVerseRef? {
        pageStarts.indices.contains(page - 1) ? pageStarts[page - 1] : nil
    }

    /// The bundled Madina layout; nil if the resource is missing or unreadable.
    public static let madina1421: QuranMushafLayout? = {
        guard let url = Bundle.module.url(forResource: "MushafLines-Madina1421", withExtension: "txt")
                ?? Bundle.module.url(forResource: "MushafLines-Madina1421", withExtension: "txt", subdirectory: "Resources"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return QuranMushafLayout(text: text)
    }()

    /// The notice for the line data (its source and MIT licence).
    public static var noticeURL: URL? {
        Bundle.module.url(forResource: "MushafLines-NOTICE", withExtension: "txt")
            ?? Bundle.module.url(forResource: "MushafLines-NOTICE", withExtension: "txt", subdirectory: "Resources")
    }

    init?(text: String) {
        var pages: [[Entry]] = []
        for row in text.split(separator: "\n") {
            var entries: [Entry] = []
            for field in row.split(separator: " ") {
                if field == "B" {
                    entries.append(.basmala)
                } else if field.hasPrefix("H"), let surah = Int(field.dropFirst()) {
                    entries.append(.title(surah))
                } else {
                    let parts = field.split(separator: ":").compactMap { Int($0) }
                    guard parts.count == 3 else { return nil }
                    entries.append(.line(QuranVerseRef(surah: parts[0], ayah: parts[1]), word: parts[2]))
                }
            }
            pages.append(entries)
        }
        guard pages.count == QuranMetadata.pageStarts.count else { return nil }
        var starts: [QuranVerseRef] = []
        for page in pages {
            guard let first = page.lazy.compactMap({ entry -> (QuranVerseRef, Int)? in
                if case .line(let ref, let word) = entry { return (ref, word) } else { return nil }
            }).first, first.1 == 0 else { return nil }
            starts.append(first.0)
        }
        self.pages = pages
        self.pageStarts = starts
    }

    /// A verse's words: space-separated pieces, a piece without letters (a pause mark, the hizb
    /// sign) joined to the word before it, or to the next word when it comes first.
    static func words(of text: String) -> [String] {
        var words: [String] = []
        var leading = ""
        for piece in text.split(separator: " ").map(String.init) {
            let hasLetter = piece.unicodeScalars.contains { $0.properties.generalCategory == .otherLetter }
            if hasLetter {
                words.append(leading + piece)
                leading = ""
            } else if let last = words.popLast() {
                words.append(last + " " + piece)
            } else {
                leading += piece + " "
            }
        }
        return words
    }
}

public extension QuranLibrary {
    /// The lines of a printed page, or nil outside 1...604, without the layout, or if the layout
    /// and the text disagree.
    func mushafLines(_ page: Int, layout: QuranMushafLayout? = .madina1421) -> [QuranMushafLine]? {
        guard let layout, layout.pages.indices.contains(page - 1) else { return nil }
        let entries = layout.pages[page - 1]
        // Where the page's last line ends: the next text line in the layout.
        let next = layout.pages.dropFirst(page).lazy.flatMap { $0 }.first { if case .line = $0 { return true } else { return false } }
        var end: (QuranVerseRef, Int)?
        if case .line(let ref, let word)? = next { end = (ref, word) }

        var lines: [QuranMushafLine] = []
        for (index, entry) in entries.enumerated() {
            switch entry {
            case .title(let id):
                guard let titled = self.surah(id) else { return nil }
                lines.append(QuranMushafLine(kind: .surahTitle(titled)))
            case .basmala:
                guard let text = entries[..<index].reversed().lazy.compactMap({ entry -> String? in
                    if case .title(let id) = entry { return self.surah(id)?.bismillah } else { return nil }
                }).first ?? previousTitleBasmala(page: page, layout: layout) else { return nil }
                lines.append(QuranMushafLine(kind: .basmala(text)))
            case .line(let ref, let word):
                let stop = entries[(index + 1)...].lazy.compactMap { entry -> (QuranVerseRef, Int)? in
                    if case .line(let r, let w) = entry { return (r, w) } else { return nil }
                }.first ?? end
                guard let run = lineItems(from: ref, word: word, to: stop) else { return nil }
                lines.append(QuranMushafLine(kind: .text(run)))
            }
        }
        return lines
    }

    /// A basmala that opens a page belongs to the title that ended the page before.
    private func previousTitleBasmala(page: Int, layout: QuranMushafLayout) -> String? {
        guard page >= 2, case .title(let id) = layout.pages[page - 2].last else { return nil }
        return surah(id)?.bismillah
    }

    /// Words and verse-end signs from word `word` of `ref` up to `stop` (exclusive; the end of
    /// the Quran when nil). A verse's end sign follows its last word.
    private func lineItems(from ref: QuranVerseRef, word: Int, to stop: (QuranVerseRef, Int)?) -> [QuranMushafLine.Item]? {
        var items: [QuranMushafLine.Item] = []
        var current = ref
        var index = word
        while true {
            guard let found = self.verse(current) else { return nil }
            let words = QuranMushafLayout.words(of: found.arabicText)
            guard index <= words.count else { return nil }
            while index < words.count {
                if let stop, stop.0 == current, stop.1 == index { return items }
                items.append(.init(kind: .word(words[index]), verse: current))
                index += 1
            }
            if let stop, stop.0 == current, stop.1 == index { return items }
            items.append(.init(kind: .verseEnd, verse: current))
            guard let next = self.verse(after: current) else { return items }
            current = next
            index = 0
            if let stop, stop.0 == current, stop.1 == 0 { return items }
        }
    }
}
