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

enum NotionTransportFileError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case unsupportedEncoding
    case invalidArchive
    case fileTooLarge
}

enum NotionTransportFile {
    static let maximumArchiveByteCount = 1_124 * 1_024 * 1_024
    static let maximumFileByteCount = 1_500 * 1_024 * 1_024

    private struct Payload: Codable {
        let schemaVersion: Int
        let encoding: String
        let archive: String
    }

    static func encode(_ archive: Data) throws -> Data {
        guard !archive.isEmpty, archive.count <= maximumArchiveByteCount else {
            throw NotionTransportFileError.fileTooLarge
        }
        let payload = Payload(
            schemaVersion: 1,
            encoding: "base64",
            archive: archive.base64EncodedString()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(payload)
        guard data.count <= maximumFileByteCount else {
            throw NotionTransportFileError.fileTooLarge
        }
        return data
    }

    static func decode(
        _ data: Data,
        maximumByteCount: Int = maximumFileByteCount
    ) throws -> Data {
        guard maximumByteCount > 0, data.count <= maximumByteCount else {
            throw NotionTransportFileError.fileTooLarge
        }
        if data.starts(with: Data("NNARCH01".utf8)) {
            guard data.count <= maximumArchiveByteCount else {
                throw NotionTransportFileError.fileTooLarge
            }
            return data
        }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw NotionTransportFileError.invalidArchive
        }
        guard payload.schemaVersion == 1 else {
            throw NotionTransportFileError.unsupportedSchema(payload.schemaVersion)
        }
        guard payload.encoding == "base64" else {
            throw NotionTransportFileError.unsupportedEncoding
        }
        guard let archive = Data(base64Encoded: payload.archive),
              !archive.isEmpty,
              archive.count <= maximumArchiveByteCount,
              archive.base64EncodedString() == payload.archive else {
            throw NotionTransportFileError.invalidArchive
        }
        return archive
    }
}
