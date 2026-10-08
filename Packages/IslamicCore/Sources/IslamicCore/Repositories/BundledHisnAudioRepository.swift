import CryptoKit
import Foundation

/// Hisn recordings available on this device. Local only: no network, no downloads.
public protocol HisnAudioRepository: Sendable {
    /// The recording for an item, or nil when the item has none (a normal state).
    func audio(for itemId: String) async throws -> HisnAudioAsset?
    /// The file of a validated asset.
    func resourceURL(for asset: HisnAudioAsset) async throws -> URL
    func allAssets() async throws -> [HisnAudioAsset]
}

/// Reads `hisn_audio.json` and the files beside it. The whole manifest is validated on first
/// use; any problem fails the repository with `ContentError.invalidContent`, so a broken pack
/// never plays half-checked.
public actor BundledHisnAudioRepository: HisnAudioRepository {
    private let manifestSource: BundledContentSource
    private let audioDirectory: URL?
    private let knownItemIds: Set<String>
    private let allowedUsage: Set<HisnAudioAsset.Usage>
    private var cache: [String: HisnAudioAsset]?

    /// - Parameters:
    ///   - knownItemIds: every `HisnItem.id` of the bundled book; assets must map to one.
    ///   - manifest: the manifest JSON; the bundled `hisn_audio.json` by default.
    ///   - audioDirectory: where the files are; the bundled `Content/HisnAudio` by default.
    ///   - allowedUsage: the app allows production assets only; tests opt in to `TEST_ONLY`.
    public init(knownItemIds: Set<String>, manifest: BundledContentSource = .bundled,
                audioDirectory: URL? = nil, allowedUsage: Set<HisnAudioAsset.Usage> = [.production]) {
        self.knownItemIds = knownItemIds
        self.manifestSource = manifest
        self.audioDirectory = audioDirectory ?? Bundle.module.url(forResource: "Content", withExtension: nil)?
            .appendingPathComponent("HisnAudio", isDirectory: true)
        self.allowedUsage = allowedUsage
    }

    public func audio(for itemId: String) async throws -> HisnAudioAsset? {
        try assetsByItem()[itemId]
    }

    public func resourceURL(for asset: HisnAudioAsset) async throws -> URL {
        guard try assetsByItem()[asset.itemId] == asset else {
            throw ContentError.notFound(asset.id)
        }
        return try fileURL(asset.resourceName)
    }

    public func allAssets() async throws -> [HisnAudioAsset] {
        try assetsByItem().values.sorted { $0.id < $1.id }
    }

    /// The validated manifest (pack status and assets), for the release report.
    public func manifest() async throws -> HisnAudioManifest {
        _ = try assetsByItem()
        return try manifestSource.decode(HisnAudioManifest.self, resource: "hisn_audio")
    }

    private func assetsByItem() throws -> [String: HisnAudioAsset] {
        if let cache { return cache }
        let manifest = try manifestSource.decode(HisnAudioManifest.self, resource: "hisn_audio")
        let assets = try validateHisnAudio(manifest, knownItemIds: knownItemIds, allowedUsage: allowedUsage,
                                           fileURL: fileURL)
        cache = assets
        return assets
    }

    /// Resolves a plain file name inside the audio directory; anything else is refused.
    private func fileURL(_ resourceName: String) throws -> URL {
        guard isPlainFileName(resourceName) else {
            throw ContentError.invalidContent("hisn_audio: resource name \(resourceName) is not a plain file name")
        }
        guard let audioDirectory else { throw ContentError.resourceMissing("HisnAudio/\(resourceName)") }
        let directory = audioDirectory.standardizedFileURL
        let url = directory.appendingPathComponent(resourceName, isDirectory: false).standardizedFileURL
        guard url.isFileURL, url.deletingLastPathComponent().path == directory.path else {
            throw ContentError.invalidContent("hisn_audio: \(resourceName) points outside the audio directory")
        }
        return url
    }
}

func isPlainFileName(_ name: String) -> Bool {
    guard !name.isEmpty, !name.hasPrefix("."), name.count <= 128 else { return false }
    return name.unicodeScalars.allSatisfy { scalar in
        switch scalar.value {
        case 0x61...0x7A, 0x41...0x5A, 0x30...0x39, 0x2D, 0x5F, 0x2E: return true // a-z A-Z 0-9 - _ .
        default: return false
        }
    }
}

/// Every rule of the audio pack. Returns the assets keyed by item id.
func validateHisnAudio(_ manifest: HisnAudioManifest, knownItemIds: Set<String>,
                       allowedUsage: Set<HisnAudioAsset.Usage>,
                       fileURL: (String) throws -> URL) throws -> [String: HisnAudioAsset] {
    try requireContent(!manifest.packStatus.isEmpty, "hisn_audio: packStatus is empty")
    var ids = Set<String>()
    var byItem: [String: HisnAudioAsset] = [:]
    for asset in manifest.assets {
        let at = "hisn_audio \(asset.id)"
        try requireContent(!asset.id.isEmpty, "hisn_audio: empty asset id")
        try requireContent(ids.insert(asset.id).inserted, "\(at): duplicate asset id")
        try requireContent(knownItemIds.contains(asset.itemId), "\(at): unknown Hisn item \(asset.itemId)")
        try requireContent(byItem[asset.itemId] == nil, "\(at): \(asset.itemId) already has a recording")
        try requireContent(allowedUsage.contains(asset.usage), "\(at): \(asset.usage.rawValue) asset is not allowed here")
        try requireContent(isPlainFileName(asset.resourceName), "\(at): resource name must be a plain file name")
        try requireContent((asset.resourceName as NSString).pathExtension.lowercased() == asset.format.rawValue,
                           "\(at): file extension does not match format \(asset.format.rawValue)")
        try requireContent(asset.durationMilliseconds.map { $0 > 0 } ?? true, "\(at): duration must be positive")
        try requireContent(asset.byteCount > 0, "\(at): byteCount must be positive")
        try requireContent(asset.sha256.count == 64 && asset.sha256.allSatisfy { "0123456789abcdef".contains($0) },
                           "\(at): sha256 must be 64 lowercase hex digits")
        try validateSource(asset.source, at: at)

        let url = try fileURL(asset.resourceName)
        guard let data = try? Data(contentsOf: url) else {
            throw ContentError.resourceMissing("HisnAudio/\(asset.resourceName)")
        }
        try requireContent(!data.isEmpty, "\(at): file is empty")
        try requireContent(data.count == asset.byteCount, "\(at): byteCount \(asset.byteCount) != file size \(data.count)")
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try requireContent(digest == asset.sha256, "\(at): checksum mismatch")
        byItem[asset.itemId] = asset
    }
    return byItem
}

private func validateSource(_ source: HisnAudioSource, at: String) throws {
    try requireContent(!source.sourceName.trimmingCharacters(in: .whitespaces).isEmpty, "\(at): provenance needs a sourceName")
    for (field, value) in [("reciter", source.reciter), ("narrationStyle", source.narrationStyle),
                           ("licenseOrRightsStatement", source.licenseOrRightsStatement)] {
        try requireContent(value.map { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? true,
                           "\(at): \(field) is empty; use null when unknown")
    }
    if let url = source.sourceURL {
        // Recorded for audit only; the app never opens it.
        try requireContent(url.hasPrefix("https://") && URL(string: url) != nil, "\(at): sourceURL must be an https URL or null")
    }
    if let date = source.retrievalDate {
        try requireContent(date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
                           "\(at): retrievalDate must be YYYY-MM-DD or null")
    }
}
