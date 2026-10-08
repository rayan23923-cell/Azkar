import XCTest

/// Fails if text is empty, contains U+FFFD, does not survive a UTF-8 round trip,
/// or has no Arabic letters at all.
func assertArabicIntegrity(_ text: String, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertFalse(text.isEmpty, "\(label): empty", file: file, line: line)
    XCTAssertFalse(text.unicodeScalars.contains("\u{FFFD}"), "\(label): replacement character", file: file, line: line)
    XCTAssertEqual(String(decoding: Array(text.utf8), as: UTF8.self), text, "\(label): UTF-8 round trip", file: file, line: line)
    XCTAssertTrue(text.unicodeScalars.contains { (0x0621...0x064A).contains($0.value) },
                  "\(label): no Arabic letters", file: file, line: line)
}
