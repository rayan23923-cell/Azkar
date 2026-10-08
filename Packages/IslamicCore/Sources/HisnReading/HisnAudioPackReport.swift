import Foundation
import IslamicCore

/// Where the Hisn audio pack stands for release: which items have a recording, and what still
/// blocks shipping it. Read-only; it never changes the pack or the content.
///
/// A recording ships only when the pack says `READY` and every production asset's rights are
/// decided. `PENDING_PRE_RELEASE_REVIEW` (the only rights status today) always blocks.
public struct HisnAudioPackReport: Equatable, Sendable {
    public static let readyStatus = "READY"

    public let packStatus: String
    public let assetCount: Int
    /// Display items with a recording, in book order.
    public let coveredItemIds: [String]
    /// Display items without one, in book order.
    public let missingItemIds: [String]
    /// Plain statements of what blocks release; empty when the pack may ship.
    public let releaseBlockers: [String]

    public var isReleaseReady: Bool { releaseBlockers.isEmpty }
    public var coverage: Double {
        let total = coveredItemIds.count + missingItemIds.count
        return total == 0 ? 0 : Double(coveredItemIds.count) / Double(total)
    }

    public init(manifest: HisnAudioManifest, book: HisnBook) {
        let byItem = Dictionary(manifest.assets.map { ($0.itemId, $0) }, uniquingKeysWith: { first, _ in first })
        let order = book.allItems.map(\.id)
        packStatus = manifest.packStatus
        assetCount = manifest.assets.count
        coveredItemIds = order.filter { byItem[$0] != nil }
        missingItemIds = order.filter { byItem[$0] == nil }

        var blockers: [String] = []
        if manifest.packStatus != Self.readyStatus {
            blockers.append("packStatus is \(manifest.packStatus), not \(Self.readyStatus)")
        }
        if manifest.assets.isEmpty {
            blockers.append("the pack has no recordings")
        }
        for asset in manifest.assets.sorted(by: { $0.id < $1.id }) {
            if asset.usage != .production {
                blockers.append("\(asset.id) is \(asset.usage.rawValue)")
            }
            if asset.source.rightsStatus == .pendingPreReleaseReview {
                blockers.append("\(asset.id) rights are \(asset.source.rightsStatus.rawValue)")
            }
            if asset.source.reciter == nil {
                blockers.append("\(asset.id) has no reciter")
            }
            if asset.durationMilliseconds == nil {
                blockers.append("\(asset.id) has no measured duration")
            }
        }
        releaseBlockers = blockers
    }
}
