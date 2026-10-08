import XCTest
@testable import IslamicCore
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Proves the bundled Quran text is the Tanzil text, unchanged.
final class TanzilFidelityTests: XCTestCase {
    static let upstreamDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Upstream/tanzil")

    /// SHA-256 of the files as downloaded from tanzil.net on 2026-10-08.
    static let expectedSHA256 = [
        "quran-uthmani.xml": "c5052534d63d3856ce25413ff464d0b609f90169a202a1615aa8707efec81244",
        "quran-data.xml": "8867c1d88191472adec9db694b3cd9f135b1a2ef580574d32cf888dcb22c5c7a",
        "quran-uthmani.txt": "7f30c647331a61100ebf24a80507dc0fcdd9f2df97f1312b5b2dfcb982a7f326",
    ]

    func testUpstreamFilesAreUnchanged() throws {
        #if canImport(CryptoKit)
        for (name, expected) in Self.expectedSHA256 {
            let data = try Data(contentsOf: Self.upstreamDirectory.appendingPathComponent(name))
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, expected, name)
        }
        #else
        throw XCTSkip("CryptoKit unavailable")
        #endif
    }

    func testEveryBundledVerseEqualsUpstream() async throws {
        let upstream = try UpstreamQuran(url: Self.upstreamDirectory.appendingPathComponent("quran-uthmani.xml"))
        XCTAssertEqual(upstream.surahs.count, 114)
        let repository = BundledQuranRepository()
        let surahs = try await repository.loadSurahs()
        for surah in surahs {
            let expected = upstream.surahs[surah.id - 1]
            XCTAssertEqual(surah.nameArabic, expected.name)
            XCTAssertEqual(surah.bismillah, expected.bismillah)
            let verses = try await repository.loadVerses(surahId: surah.id)
            XCTAssertEqual(verses.map(\.arabicText), expected.verses, "surah \(surah.id)")
        }
    }
}

/// Minimal reader for Tanzil's quran-uthmani.xml.
private final class UpstreamQuran: NSObject, XMLParserDelegate {
    struct Surah { var name: String; var bismillah: String?; var verses: [String] }
    private(set) var surahs: [Surah] = []

    init(url: URL) throws {
        super.init()
        let parser = try XCTUnwrap(XMLParser(contentsOf: url))
        parser.delegate = self
        XCTAssertTrue(parser.parse(), parser.parserError.map(String.init(describing:)) ?? "parse failed")
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String] = [:]) {
        switch elementName {
        case "sura":
            surahs.append(Surah(name: attributes["name"] ?? "", bismillah: nil, verses: []))
        case "aya":
            if surahs[surahs.count - 1].verses.isEmpty {
                surahs[surahs.count - 1].bismillah = attributes["bismillah"]
            }
            surahs[surahs.count - 1].verses.append(attributes["text"] ?? "")
        default:
            break
        }
    }
}
