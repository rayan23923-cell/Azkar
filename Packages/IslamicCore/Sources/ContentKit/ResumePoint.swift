import Foundation

/// Where reading stopped in one section, for «أكمل من حيث توقفت».
public struct ResumePoint: Equatable, Sendable {
    /// In the order a tie is broken (two places saved at the same instant).
    public enum Section: Int, CaseIterable, Comparable, Sendable {
        case quran
        case hisn
        case adhkar
        case dua

        public static func < (lhs: Section, rhs: Section) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let section: Section
    /// The verse or item to open.
    public let target: ContentRef
    /// The chapter or collection holding it; nil for the Quran.
    public let container: ContentRef?
    public let savedAt: Date

    public init(section: Section, target: ContentRef, container: ContentRef?, savedAt: Date) {
        self.section = section
        self.target = target
        self.container = container
        self.savedAt = savedAt
    }

    /// The place saved last. Ties go to the section first in `Section` order, then to the
    /// smaller target reference, so the same saved state always gives the same answer.
    /// A place saved after `now` (a clock set back) is still a candidate: it was the user's.
    public static func mostRecent(_ points: [ResumePoint]) -> ResumePoint? {
        points.min { lhs, rhs in
            if lhs.savedAt != rhs.savedAt { return lhs.savedAt > rhs.savedAt }
            if lhs.section != rhs.section { return lhs.section < rhs.section }
            return lhs.target < rhs.target
        }
    }
}
