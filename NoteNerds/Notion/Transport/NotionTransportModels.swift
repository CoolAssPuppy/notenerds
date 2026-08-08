import Foundation

struct NotionTransportLimits: Equatable, Sendable {
    let maximumEntryCount: Int
    let maximumIndexByteCount: Int
    let maximumMetadataByteCount: Int
    let maximumAssetByteCount: Int

    init(
        maximumEntryCount: Int = 10_000,
        maximumIndexByteCount: Int = 4 * 1_024 * 1_024,
        maximumMetadataByteCount: Int = 100 * 1_024 * 1_024,
        maximumAssetByteCount: Int = 1_024 * 1_024 * 1_024
    ) {
        self.maximumEntryCount = maximumEntryCount
        self.maximumIndexByteCount = maximumIndexByteCount
        self.maximumMetadataByteCount = maximumMetadataByteCount
        self.maximumAssetByteCount = maximumAssetByteCount
    }
}

enum NotionTransportArchiveError: Error, Equatable, Sendable {
    case invalidHeader
    case invalidLength
    case unsupportedSchema(Int)
    case tooManyEntries
    case indexTooLarge
    case metadataTooLarge
    case assetsTooLarge
    case unsafePath
    case duplicatePath
    case missingRequiredEntry(String)
    case checksumMismatch(String)
    case invalidManifest
    case notebookMismatch
}

struct NotionTransportIndex: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let notebookID: String
    let exportedAt: Date
    let uncompressedByteCount: Int
    let assetCount: Int
    let entries: [NotionTransportEntry]
}

struct NotionTransportEntry: Codable, Equatable, Sendable {
    let path: String
    let offset: Int
    let byteCount: Int
    let sha256: String
}

struct NotionTransportAssetManifest: Codable, Equatable, Sendable {
    let assets: [NotionTransportAssetEntry]
}

struct NotionTransportAssetEntry: Codable, Equatable, Sendable {
    let id: AssetID
    let contentType: String
    let filename: String
}
