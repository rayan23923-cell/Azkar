import Foundation
import IslamicCore
import ContentKit

/// The shared audio pack for the Quran, adhkar and duas (`content_audio.json`, files in
/// `ContentAudio/`). Item ids are content references («quran:2:255», «adhkar:dhikr-morning-001»).
/// It is checked like the Hisn pack and is empty until licensed recordings are added.
public enum ContentAudioPack {
    public static let resource = "content_audio"
    public static let directoryName = "ContentAudio"

    /// The repository the players read; `knownRefs` are every reference the pack may cover.
    public static func repository(knownRefs: Set<ContentRef>,
                                  manifest: BundledContentSource = .bundled) -> BundledHisnAudioRepository {
        BundledHisnAudioRepository(knownItemIds: Set(knownRefs.map(\.string)), manifest: manifest,
                                   resource: resource, directoryName: directoryName)
    }

    /// Why the pack cannot ship as it is (empty when it can).
    public static func releaseBlockers(_ manifest: HisnAudioManifest) -> [String] {
        var blockers: [String] = []
        if manifest.packStatus != "READY" { blockers.append("packStatus is \(manifest.packStatus), not READY") }
        if manifest.assets.isEmpty { blockers.append("no recordings") }
        for asset in manifest.assets {
            if asset.usage != .production { blockers.append("\(asset.id): not a production asset") }
            if asset.source.rightsStatus == .pendingPreReleaseReview { blockers.append("\(asset.id): rights pending") }
            if asset.source.reciter == nil { blockers.append("\(asset.id): no reciter") }
        }
        return blockers
    }
}
