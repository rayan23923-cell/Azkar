import XCTest
import IslamicCore
@testable import HisnReading

@MainActor
final class FakeHaptics: HisnHaptics {
    private(set) var events: [HisnHapticEvent] = []
    func play(_ event: HisnHapticEvent) { events.append(event) }
}

@MainActor
final class FakePasteboard: HisnTextPasteboard {
    /// When set, writes are lost (a clipboard that refuses).
    var refuses = false
    private var stored: String?
    var string: String? {
        get { stored }
        set { if !refuses { stored = newValue } }
    }
}

/// Phase 3E: copy and share payloads, haptic events, and the action accessibility text.
@MainActor
final class HisnItemActionsTests: XCTestCase {
    private static var cached: HisnLibrary?

    private func library() async throws -> HisnLibrary {
        if let cached = Self.cached { return cached }
        let library = HisnLibrary(book: try await BundledHisnRepository().loadBook())
        Self.cached = library
        return library
    }

    private func reader(at itemId: String) async throws -> HisnReader {
        let loaded = try await library()
        for chapter in loaded.book.chapters {
            if let index = chapter.items.firstIndex(where: { $0.id == itemId }) {
                return try XCTUnwrap(HisnReader(chapter: chapter, itemIndex: index))
            }
        }
        throw XCTSkip("missing \(itemId)")
    }

    /// Short, long (1864 characters, multi-line), parentheses, Quran citation, and the three
    /// items with classified non-recitation text.
    private let sample = ["hisn-087-01", "hisn-001-01", "hisn-001-04", "hisn-027-02", "hisn-001-03",
                          "hisn-021-01", "hisn-029-14", "hisn-133-01"]

    // MARK: Copy

    func testCopyPutsExactlyTheStoredTextOnTheClipboard() async throws {
        for id in sample {
            let reader = try await reader(at: id)
            let pasteboard = FakePasteboard()
            let haptics = FakeHaptics()
            let actions = HisnItemActions(pasteboard: pasteboard, haptics: haptics)
            XCTAssertTrue(actions.copy(reader.shareContent), id)
            let copied = try XCTUnwrap(pasteboard.string)
            XCTAssertEqual(copied, reader.currentItem.arabicText, "\(id): unchanged, nothing added or removed")
            XCTAssertEqual(copied.unicodeScalars.count, reader.currentItem.arabicText.unicodeScalars.count, id)
            XCTAssertEqual(haptics.events, [.copied], id)
        }
    }

    func testCopyCarriesNoInternalMetadata() async throws {
        for id in sample {
            let reader = try await reader(at: id)
            let item = reader.currentItem
            let pasteboard = FakePasteboard()
            HisnItemActions(pasteboard: pasteboard, haptics: nil).copy(reader.shareContent)
            let copied = try XCTUnwrap(pasteboard.string)
            for internal in [item.id, item.chapterId, "hisn-", "CONTENT_REVIEW", "PENDING", "{\"", "sha256"] {
                XCTAssertFalse(copied.contains(internal), "\(id) contains \(internal)")
            }
            for reference in item.references.map(\.originalText) where !reference.isEmpty {
                XCTAssertFalse(copied.hasSuffix(reference), "\(id): no reference appended")
            }
        }
    }

    func testNonRecitationPartsStayWhereTheSourcePutsThem() async throws {
        for id in ["hisn-001-03", "hisn-029-14", "hisn-133-01"] {
            let reader = try await reader(at: id)
            XCTAssertFalse(reader.currentItem.nonRecitationText.isEmpty, id)
            for part in reader.currentItem.nonRecitationText {
                XCTAssertTrue(reader.shareContent.text.contains(part.text), "\(id): classified text is not removed")
            }
        }
    }

    func testFailedCopyGivesNoFeedback() async throws {
        let reader = try await reader(at: "hisn-001-01")
        let pasteboard = FakePasteboard()
        pasteboard.refuses = true
        let haptics = FakeHaptics()
        XCTAssertFalse(HisnItemActions(pasteboard: pasteboard, haptics: haptics).copy(reader.shareContent))
        XCTAssertTrue(haptics.events.isEmpty)
    }

    // MARK: Share payload

    func testTextShareIsTheDhikrTextAlone() async throws {
        for id in sample {
            let reader = try await reader(at: id)
            let payload = HisnItemActions(pasteboard: FakePasteboard(), haptics: nil).textPayload(reader.shareContent)
            XCTAssertEqual(payload, reader.currentItem.arabicText, id)
        }
        let reader = try await reader(at: "hisn-001-01")
        XCTAssertEqual(reader.shareContent.chapterTitle, reader.chapter.titleArabic)
    }

    func testCardFeedbackOnlyOnSuccess() {
        let haptics = FakeHaptics()
        let actions = HisnItemActions(pasteboard: FakePasteboard(), haptics: haptics)
        actions.cardGenerated(false)
        XCTAssertTrue(haptics.events.isEmpty)
        actions.cardGenerated(true)
        XCTAssertEqual(haptics.events, [.cardReady])
    }

    // MARK: Repetition feedback

    private func controller(_ chapterId: String, haptics: FakeHaptics) async throws -> HisnReaderController {
        let loaded = try await library()
        let chapter = try XCTUnwrap(loaded.chapter(id: chapterId))
        let reader = try XCTUnwrap(HisnReader(chapter: chapter))
        return HisnReaderController(reader: reader, store: InMemoryHisnReadingPositionStore(), haptics: haptics)
    }

    func testFeedbackMarksCompletionNotEveryTap() async throws {
        let haptics = FakeHaptics()
        let controller = try await controller("hisn-ch-017", haptics: haptics)
        controller.recite()
        controller.recite()
        XCTAssertTrue(haptics.events.isEmpty, "counting taps are silent")
        XCTAssertEqual(controller.reader.repetition, .counted(completed: 2, total: 3))
        controller.recite()
        XCTAssertEqual(haptics.events, [.itemCompleted], "one success when the count is reached")
        controller.next()
        controller.previous()
        XCTAssertEqual(haptics.events, [.itemCompleted], "navigation is silent")
    }

    func testChapterCompletionFeedbackOnce() async throws {
        let haptics = FakeHaptics()
        let controller = try await controller("hisn-ch-001", haptics: haptics)
        for _ in 0..<100 where !controller.reader.isCompleted { controller.next() }
        XCTAssertEqual(haptics.events, [.chapterCompleted])
        controller.next()
        XCTAssertEqual(haptics.events, [.chapterCompleted], "nothing more once complete")

        let reciting = FakeHaptics()
        let other = try await self.controller("hisn-ch-001", haptics: reciting)
        for _ in 0..<100 where !other.reader.isCompleted { other.recite() }
        XCTAssertEqual(reciting.events, [.itemCompleted, .itemCompleted, .itemCompleted, .chapterCompleted])
    }

    func testNoHapticsStillWorks() async throws {
        let loaded = try await library()
        let chapter = try XCTUnwrap(loaded.chapter(id: "hisn-ch-017"))
        let controller = HisnReaderController(reader: try XCTUnwrap(HisnReader(chapter: chapter)),
                                              store: InMemoryHisnReadingPositionStore())
        for _ in 0..<3 { controller.recite() }
        XCTAssertEqual(controller.reader.itemNumber, 2)
    }

    // MARK: Accessibility

    func testActionLabelsAreArabic() {
        let labels = [HisnAccessibility.actionsMenu, HisnAccessibility.copyAction, HisnAccessibility.shareAction,
                      HisnAccessibility.shareImageAction, HisnAccessibility.copied, HisnAccessibility.cardFailed]
        XCTAssertEqual(Array(labels.prefix(4)), ["إجراءات الذكر", "نسخ الذكر", "مشاركة الذكر", "مشاركة الذكر كصورة"])
        let arabic = CharacterSet(charactersIn: "\u{0600}"..."\u{06FF}")
        for label in labels {
            XCTAssertFalse(label.isEmpty)
            XCTAssertNotNil(label.rangeOfCharacter(from: arabic), label)
            XCTAssertNil(label.rangeOfCharacter(from: .init(charactersIn: "abcdefghijklmnopqrstuvwxyz")), label)
        }
    }

    func testRepetitionProgressIsSpokenWithoutInventingATotal() async throws {
        var counted = try await reader(at: "hisn-017-01")
        counted.recite()
        counted.recite()
        XCTAssertEqual(HisnAccessibility.counterValue(counted), "التكرار 2 من 3")
        let unstated = try await library().book.allItems.first { $0.repetition.count == nil }
        if let unstated {
            let reader = try await reader(at: unstated.id)
            XCTAssertEqual(reader.repetition, .unstated)
            XCTAssertEqual(HisnAccessibility.counterValue(reader), "", "no fake total")
        }
    }
}
