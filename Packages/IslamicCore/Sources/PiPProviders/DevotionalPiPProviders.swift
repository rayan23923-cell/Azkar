import AdhkarReading
import Combine
import Foundation
import IslamicCore
import PiPCore

/// Adhkar and duas in PiP, on the reader the screen uses (`DevotionalReaderController`): its
/// position, counter and saved place are the screen's, and favorites are untouched. Previous /
/// next are the reader's own and stop at the ends of the collection. PiP never counts.
/// No recordings ship for these sections, so there is no playback.
@MainActor
public class DevotionalPiPProvider: PiPContentProvider {
    public let controller: DevotionalReaderController

    init(wrapping controller: DevotionalReaderController) {
        self.controller = controller
    }

    /// The provider for the collection's kind.
    public static func make(controller: DevotionalReaderController) -> DevotionalPiPProvider {
        switch controller.collection.kind {
        case .adhkar: return AdhkarPiPProvider(controller: controller)!
        case .dua: return DuaPiPProvider(controller: controller)!
        }
    }

    public var contentType: PiPContentType { controller.collection.kind == .adhkar ? .dhikr : .dua }

    public var current: PiPContent? {
        guard !controller.isComplete else { return nil }
        let item = controller.current
        let number = controller.index + 1
        return PiPContent(contentType: contentType, contentID: item.ref.string,
                          containerID: controller.collection.ref.string, title: controller.collection.title,
                          subtitle: contentType == .dhikr ? "الذكر \(number)" : "الدعاء \(number)",
                          text: item.text, textStyle: item.reviewStatus == .quranVerbatimTanzil ? .quran : .standard,
                          index: controller.index, total: controller.count, detail: detail)
    }

    /// «التكرار n من m» for a dhikr said more than once.
    var detail: String? {
        let required = controller.cursor.requiredRepetitions
        guard required > 1 else { return nil }
        return "التكرار \(min(controller.cursor.completedRepetitions + 1, required)) من \(required)"
    }

    public func goToPrevious() { controller.previous() }
    public func goToNext() { controller.next() }

    public var playback: PiPPlaybackController? { nil }

    public var changes: AnyPublisher<Void, Never> {
        controller.objectWillChange.map { _ in () }.eraseToAnyPublisher()
    }

    public func persist() {
        controller.persist()
    }
}

/// A dhikr collection (morning, evening…) in PiP.
@MainActor
public final class AdhkarPiPProvider: DevotionalPiPProvider {
    /// Nil for a dua collection.
    public init?(controller: DevotionalReaderController) {
        guard controller.collection.kind == .adhkar else { return nil }
        super.init(wrapping: controller)
    }
}

/// A dua category in PiP. Duas are said once: no counter.
@MainActor
public final class DuaPiPProvider: DevotionalPiPProvider {
    /// Nil for a dhikr collection.
    public init?(controller: DevotionalReaderController) {
        guard controller.collection.kind == .dua else { return nil }
        super.init(wrapping: controller)
    }
}
