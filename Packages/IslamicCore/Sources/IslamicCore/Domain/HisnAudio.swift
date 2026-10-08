import Foundation

/// The bundled Hisn audio pack: `Resources/Content/hisn_audio.json`. Audio is optional per
/// item; an item with no asset simply has no recording.
public struct HisnAudioManifest: Hashable, Codable, Sendable {
    public let formatVersion: Int
    /// Where the production pack stands, e.g. "PENDING_RIGHTS_AND_ASSETS". Metadata only.
    public let packStatus: String
    public let assets: [HisnAudioAsset]

    public init(formatVersion: Int, packStatus: String, assets: [HisnAudioAsset]) {
        self.formatVersion = formatVersion
        self.packStatus = packStatus
        self.assets = assets
    }
}

/// One recording of one Hisn item, mapped by the item's stable id (never by order or text).
public struct HisnAudioAsset: Identifiable, Hashable, Codable, Sendable {
    public enum Format: String, Codable, Sendable, CaseIterable {
        case m4a
        case mp3
        /// Used by the generated test fixtures.
        case wav
    }

    public enum Usage: String, Codable, Sendable {
        /// Ships in the app.
        case production = "PRODUCTION"
        /// Unit-test fixture; never accepted by the app's repository.
        case testOnly = "TEST_ONLY"
    }

    public let id: String
    /// `HisnItem.id`, e.g. "hisn-001-01".
    public let itemId: String
    public let usage: Usage
    /// File name inside the audio directory. A plain name: no folders, no URL.
    public let resourceName: String
    public let format: Format
    /// As measured when the asset was added; nil when not recorded.
    public let durationMilliseconds: Int?
    public let byteCount: Int
    /// SHA-256 of the file, lowercase hex.
    public let sha256: String
    public let source: HisnAudioSource

    public init(id: String, itemId: String, usage: Usage, resourceName: String, format: Format,
                durationMilliseconds: Int?, byteCount: Int, sha256: String, source: HisnAudioSource) {
        self.id = id
        self.itemId = itemId
        self.usage = usage
        self.resourceName = resourceName
        self.format = format
        self.durationMilliseconds = durationMilliseconds
        self.byteCount = byteCount
        self.sha256 = sha256
        self.source = source
    }
}

/// Provenance of a recording. Unknown values stay nil; nothing is filled in by guess.
public struct HisnAudioSource: Hashable, Codable, Sendable {
    public let sourceName: String
    /// Where the recording was obtained. Metadata only: never fetched by the app.
    public let sourceURL: String?
    public let reciter: String?
    public let narrationStyle: String?
    /// ISO date (YYYY-MM-DD) the file was obtained.
    public let retrievalDate: String?
    /// The licence or rights statement as published by the source, verbatim; nil when none.
    public let licenseOrRightsStatement: String?
    public let rightsStatus: ContentRightsStatus

    public init(sourceName: String, sourceURL: String?, reciter: String?, narrationStyle: String?,
                retrievalDate: String?, licenseOrRightsStatement: String?, rightsStatus: ContentRightsStatus) {
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.reciter = reciter
        self.narrationStyle = narrationStyle
        self.retrievalDate = retrievalDate
        self.licenseOrRightsStatement = licenseOrRightsStatement
        self.rightsStatus = rightsStatus
    }
}
