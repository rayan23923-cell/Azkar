import XCTest
import IslamicCore
@testable import HisnReading

/// Phase 3D: index numbering, «الباب التالي», and the Arabic VoiceOver text.
final class HisnIndexAccessibilityTests: XCTestCase {
    private static var cached: HisnLibrary?

    private func library() async throws -> HisnLibrary {
        if let cached = Self.cached { return cached }
        let library = HisnLibrary(book: try await BundledHisnRepository().loadBook())
        Self.cached = library
        return library
    }

    func testChapter27HalvesShareTheCanonicalNumber() async throws {
        let library = try await library()
        let split = library.sections.filter { $0.timeOfDay != nil }
        XCTAssertEqual(split.map(\.bookChapterNumber), [27, 27], "two presentation sections of chapter 27")
        XCTAssertEqual(Set(library.sections.compactMap(\.bookChapterNumber)).count, 132)
        XCTAssertEqual(split.map(HisnAccessibility.sectionLabel).map { $0.hasPrefix("الباب 27، ") }, [true, true])
        XCTAssertTrue(HisnAccessibility.sectionLabel(split[0]).hasSuffix("قسم الصباح"))
        XCTAssertTrue(HisnAccessibility.sectionLabel(split[1]).hasSuffix("قسم المساء"))
    }

    func testNextSectionFollowsTheIndex() async throws {
        let library = try await library()
        XCTAssertEqual(library.section(after: "hisn-ch-001")?.id, "hisn-ch-002")
        XCTAssertEqual(library.section(after: "hisn-ch-027")?.id, "hisn-ch-028", "morning → evening")
        XCTAssertNil(library.section(after: library.sections.last!.id))
        XCTAssertNil(library.section(after: "hisn-ch-999"))
    }

    func testSectionValueMarksTheReadingPosition() async throws {
        let entry = try await library().sections[0]
        XCTAssertEqual(HisnAccessibility.sectionValue(entry, isCurrent: false), "عدد الأذكار \(entry.itemCount)")
        XCTAssertTrue(HisnAccessibility.sectionValue(entry, isCurrent: true).hasPrefix("موضع القراءة الحالي"))
    }

    func testCounterTextExplainsProgress() async throws {
        let library = try await library()
        var counted = try XCTUnwrap(HisnReader(chapter: try XCTUnwrap(library.chapter(id: "hisn-ch-017"))))
        XCTAssertEqual(HisnAccessibility.counterLabel(counted), "العدّ")
        XCTAssertEqual(HisnAccessibility.counterValue(counted), "التكرار 0 من 3")
        XCTAssertEqual(HisnAccessibility.counterHint(counted), "اضغط مرة بعد كل قراءة")
        counted.recite()
        counted.recite()
        XCTAssertEqual(HisnAccessibility.counterValue(counted), "التكرار 2 من 3")
        XCTAssertTrue(HisnAccessibility.counterHint(counted).hasPrefix("القراءة الأخيرة"))
        XCTAssertEqual(HisnAccessibility.itemPosition(counted), "الذكر 1 من \(counted.itemCount)")

        let once = try XCTUnwrap(HisnReader(chapter: try XCTUnwrap(library.chapter(id: "hisn-ch-001"))))
        XCTAssertEqual(HisnAccessibility.counterLabel(once), "تمّت القراءة")
        XCTAssertEqual(HisnAccessibility.counterValue(once), "", "no count is invented")
        XCTAssertEqual(HisnAccessibility.counterHint(once), "ينتقل إلى الذكر التالي")
    }

    func testAllAccessibilityTextIsArabic() async throws {
        let library = try await library()
        let latin = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        for entry in library.sections {
            for text in [HisnAccessibility.sectionLabel(entry), HisnAccessibility.sectionValue(entry, isCurrent: true)] {
                XCTAssertNil(text.rangeOfCharacter(from: latin), text)
            }
        }
    }
}
