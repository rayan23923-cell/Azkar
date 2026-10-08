import XCTest
import IslamicCore
@testable import HisnReading

/// Phase 3B: reader → HisnSession → HisnAudioPlayer → audio repository, with the real bundled
/// book and the TEST_ONLY fixture repository; only the low-level engine is faked.
@MainActor
final class HisnReaderAudioTests: XCTestCase {
    private var engine: FakeAudioEngine!
    private var store: InMemoryHisnReadingPositionStore!

    private func makeController(_ chapterId: String, at index: Int = 0,
                            repository: HisnAudioRepository? = nil) async throws -> HisnReaderController {
        engine = FakeAudioEngine()
        store = InMemoryHisnReadingPositionStore()
        let library = try await HisnLibraryCache.library()
        let chapter = try XCTUnwrap(library.chapter(id: chapterId))
        let reader = try XCTUnwrap(HisnReader(chapter: chapter, itemIndex: index))
        var audioRepository: HisnAudioRepository
        if let repository {
            audioRepository = repository
        } else {
            audioRepository = try await Fixture.repository()
        }
        let audio = HisnAudioPlayer(repository: audioRepository, engine: engine, session: FakeAudioSession())
        let controller = HisnReaderController(reader: reader, store: store, audio: audio)
        await controller.audioSettled()
        return controller
    }

    func testOpeningAnItemLoadsItsRecordingWithoutPlaying() async throws {
        let controller = try await makeController("hisn-ch-001")
        let audio = try XCTUnwrap(controller.audio)
        XCTAssertEqual(controller.reader.currentItem.id, "hisn-001-01")
        XCTAssertEqual(audio.currentAudioItemId, "hisn-001-01")
        XCTAssertEqual(audio.availability, .available)
        XCTAssertEqual(audio.state, .ready)
        XCTAssertFalse(engine.isPlaying)
        XCTAssertTrue(engine.loadedURL?.lastPathComponent == "test-silence-1s.wav")
    }

    func testNextStopsAudioAndLoadsTheNextItem() async throws {
        let controller = try await makeController("hisn-ch-001")
        let audio = try XCTUnwrap(controller.audio)
        audio.play()
        XCTAssertEqual(audio.state, .playing)
        controller.next()
        XCTAssertFalse(engine.isPlaying, "next stops the recording")
        await controller.audioSettled()
        XCTAssertEqual(controller.reader.currentItem.id, "hisn-001-02")
        XCTAssertEqual(audio.currentAudioItemId, "hisn-001-02")
        XCTAssertEqual(audio.availability, .unavailable, "this item has no recording")
        XCTAssertEqual(audio.state, .idle)

        controller.previous()
        await controller.audioSettled()
        XCTAssertEqual(controller.reader.currentItem.id, "hisn-001-01")
        XCTAssertEqual(audio.availability, .available)
        XCTAssertEqual(audio.state, .ready, "no autoplay after navigation")
        XCTAssertFalse(engine.isPlaying)
    }

    func testAudioDoesNotMoveTheReader() async throws {
        let controller = try await makeController("hisn-ch-001")
        let audio = try XCTUnwrap(controller.audio)
        let before = controller.reader
        let savedBefore = store.position
        audio.play()
        audio.seek(to: 0.5)
        audio.pause()
        audio.resume()
        engine.finish()
        XCTAssertEqual(audio.state, .finished)
        XCTAssertEqual(controller.reader, before, "finishing a recording does not advance the reader")
        XCTAssertEqual(controller.recitations, 0)
        XCTAssertEqual(store.position?.itemId, savedBefore?.itemId)
        XCTAssertEqual(store.position?.completedRepetitions, savedBefore?.completedRepetitions)
    }

    func testAudioCompletionDoesNotCountARepetition() async throws {
        let library = try await HisnLibraryCache.library()
        let chapter = try XCTUnwrap(library.chapter(id: "hisn-ch-017"))
        XCTAssertEqual(chapter.items[0].repetition.count, 3)
        let repository = StubAudioRepository(assets: ["hisn-017-01": StubAudioRepository.asset(for: "hisn-017-01")])
        let controller = try await makeController("hisn-ch-017", repository: repository)
        let audio = try XCTUnwrap(controller.audio)
        audio.play()
        engine.finish()
        audio.play()
        engine.finish()
        XCTAssertEqual(controller.reader.completedRepetitions, 0, "two full plays, no repetition counted")
        XCTAssertEqual(controller.reader.repetition, .counted(completed: 0, total: 3))

        audio.play()
        controller.recite()
        XCTAssertEqual(controller.reader.completedRepetitions, 1, "only the user's tap counts")
        XCTAssertEqual(audio.state, .playing, "counting does not interrupt the recording")
        XCTAssertTrue(engine.isPlaying)
    }

    func testCompletingTheChapterStopsAudio() async throws {
        let controller = try await makeController("hisn-ch-001")
        let audio = try XCTUnwrap(controller.audio)
        while !controller.reader.isLastItem { controller.next() }
        await controller.audioSettled()
        controller.next()
        await controller.audioSettled()
        XCTAssertTrue(controller.reader.isCompleted)
        XCTAssertEqual(audio.state, .idle)
        XCTAssertNil(audio.currentAudioItemId)
        XCTAssertEqual(controller.reader.chapter.id, "hisn-ch-001")
    }

    func testCloseStopsPlayback() async throws {
        let controller = try await makeController("hisn-ch-001")
        let audio = try XCTUnwrap(controller.audio)
        audio.play()
        controller.close()
        XCTAssertEqual(audio.state, .ready)
        XCTAssertFalse(engine.isPlaying)
    }

    func testReaderWithoutAudioStillWorks() async throws {
        let library = try await HisnLibraryCache.library()
        let chapter = try XCTUnwrap(library.chapter(id: "hisn-ch-001"))
        let controller = HisnReaderController(reader: try XCTUnwrap(HisnReader(chapter: chapter)),
                                              store: InMemoryHisnReadingPositionStore())
        XCTAssertNil(controller.audio)
        controller.next()
        XCTAssertEqual(controller.reader.itemIndex, 1)
    }
}
