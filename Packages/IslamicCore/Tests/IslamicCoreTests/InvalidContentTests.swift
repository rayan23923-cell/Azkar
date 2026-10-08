import XCTest
@testable import IslamicCore

final class InvalidContentTests: XCTestCase {
    private func data(_ json: String) -> BundledContentSource { .data(Data(json.utf8)) }

    func testGarbageIsInvalidContent() async {
        await assertError(.invalidContent) { _ = try await BundledQuranRepository(source: self.data("not json")).loadSurahs() }
    }

    func testUnsupportedFormatVersion() async {
        let repo = BundledDhikrRepository(source: data(#"{"formatVersion": 2, "groups": []}"#))
        await assertError(.unsupportedFormatVersion) { _ = try await repo.loadGroups() }
    }

    func testEmptyContentIsRejected() async {
        await assertError(.invalidContent) {
            _ = try await BundledQuranRepository(source: self.data(#"{"formatVersion": 1, "surahs": []}"#)).loadSurahs()
        }
        await assertError(.invalidContent) {
            _ = try await BundledDhikrRepository(source: self.data(#"{"formatVersion": 1, "groups": []}"#)).loadGroups()
        }
        await assertError(.invalidContent) {
            _ = try await BundledDuaRepository(source: self.data(#"{"formatVersion": 1, "categories": [{"id": "x", "titleArabic": "أ", "items": []}]}"#)).loadCategories()
        }
    }

    func testVerseCountMismatchIsRejected() async {
        let json = #"""
        {"formatVersion": 1, "surahs": [{"id": 1, "nameArabic": "الفاتحة", "nameTransliteration": "a", "nameEnglish": "b",
         "revelationType": "meccan", "revelationOrder": 5, "ayahCount": 2, "bismillah": null, "verses": ["بِسْمِ"]}]}
        """#
        await assertError(.invalidContent) { _ = try await BundledQuranRepository(source: self.data(json)).loadSurahs() }
    }

    func testWrongOrderAndZeroRepeatAreRejected() async {
        let item = #"{"id": "a", "group": "morning", "order": 2, "arabicText": "ذِكْر", "source": "s", "repeatCount": 1, "quranRef": null, "reviewStatus": "CONTENT_REVIEW_REQUIRED"}"#
        let wrongOrder = #"{"formatVersion": 1, "groups": [{"id": "morning", "titleArabic": "ص", "items": [\#(item)]}]}"#
        await assertError(.invalidContent) { _ = try await BundledDhikrRepository(source: self.data(wrongOrder)).loadGroups() }

        let zero = wrongOrder.replacingOccurrences(of: #""order": 2"#, with: #""order": 1"#)
            .replacingOccurrences(of: #""repeatCount": 1"#, with: #""repeatCount": 0"#)
        await assertError(.invalidContent) { _ = try await BundledDhikrRepository(source: self.data(zero)).loadGroups() }
    }

    private enum Kind { case invalidContent, unsupportedFormatVersion }

    private func assertError(_ kind: Kind, file: StaticString = #filePath, line: UInt = #line,
                             _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected \(kind)", file: file, line: line)
        } catch let error as ContentError {
            switch (kind, error) {
            case (.invalidContent, .invalidContent), (.unsupportedFormatVersion, .unsupportedFormatVersion): break
            default: XCTFail("got \(error)", file: file, line: line)
            }
        } catch {
            XCTFail("got \(error)", file: file, line: line)
        }
    }
}
