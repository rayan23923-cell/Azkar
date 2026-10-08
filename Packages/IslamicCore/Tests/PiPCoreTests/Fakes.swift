import Combine
import Foundation
@testable import PiPCore

/// Records what the engine asks of the platform controller; tests drive its events.
@MainActor
final class FakePiPController: PiPController {
    var isSupported = true
    var isPossible = true
    var onEvent: ((PiPControllerEvent) -> Void)?
    var frameSource: (() -> PiPFrame?)?
    weak var commands: PiPCommandHandling?
    var calls: [String] = []
    var heartbeat = false
    var refreshes = 0

    func start() { calls.append("start") }
    func stop() { calls.append("stop") }
    func refresh() { refreshes += 1 }
    func setHeartbeat(_ running: Bool) { heartbeat = running }

    func send(_ event: PiPControllerEvent) { onEvent?(event) }

    func systemStarts() {
        send(.willStart)
        send(.didStart)
    }

    func systemStops() {
        send(.willStop)
        send(.didStop)
    }

    var frame: PiPFrame? { frameSource?() }
}

/// A recording the test controls.
@MainActor
final class FakePlayback: PiPPlaybackController {
    var isAvailable = true
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval? = 30
    var calls: [String] = []

    func play() { isPlaying = true; calls.append("play") }
    func pause() { isPlaying = false; calls.append("pause") }
    func seek(to time: TimeInterval) { currentTime = time; calls.append("seek") }
}

/// A list of items with their own position, like a section's reader.
@MainActor
final class FakeProvider: PiPContentProvider {
    let contentType: PiPContentType
    var texts: [String]
    var index: Int
    var completed = false
    var playback: PiPPlaybackController?
    let subject = PassthroughSubject<Void, Never>()
    var persists = 0
    var navigations: [String] = []

    init(_ type: PiPContentType = .dhikr, texts: [String] = ["أ", "ب", "ج", "د"], index: Int = 0) {
        contentType = type
        self.texts = texts
        self.index = index
    }

    var current: PiPContent? {
        guard !completed else { return nil }
        return PiPContent(contentType: contentType, contentID: "\(contentType.rawValue):\(index)",
                          containerID: "\(contentType.rawValue):list", title: "العنوان",
                          subtitle: "العنصر \(index + 1)", text: texts[index], index: index, total: texts.count)
    }

    func goToPrevious() { navigations.append("previous"); index = max(0, index - 1); subject.send() }
    func goToNext() { navigations.append("next"); index = min(texts.count - 1, index + 1); subject.send() }
    var changes: AnyPublisher<Void, Never> { subject.eraseToAnyPublisher() }
    func persist() { persists += 1 }
}

/// Pages of `wordsPerPage` words; the font size is fixed.
struct FakePaginator: PiPPaginating {
    var wordsPerPage = 3

    func paginate(_ text: String, style: PiPTextStyle) -> PiPPagination {
        let pages = PiPTextPaginator.pages(text) { slice in
            slice.split(whereSeparator: \.isWhitespace).count <= wordsPerPage
        }
        return PiPPagination(fontSize: 54, pages: pages)
    }
}

/// A clock the test moves.
final class TestClock {
    var date = Date(timeIntervalSince1970: 1_700_000_000)
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

/// Lets main-queue observation run.
@MainActor
func settle() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}
