import Foundation

struct NotionFolderManifestRecord: Codable, Equatable, Sendable {
    let id: FolderID
    let name: String
    let parentID: FolderID?
    let createdAt: Date
    let modifiedAt: Date
    let isFavorite: Bool
    let tags: [String]
    let trashedAt: Date?

    init(folder: Folder) {
        id = folder.id
        name = folder.name
        parentID = folder.parentID
        createdAt = folder.createdAt
        modifiedAt = folder.modifiedAt
        isFavorite = folder.isFavorite
        tags = folder.tags.sorted()
        trashedAt = folder.trashedAt
    }
}

struct NotionLibraryManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let databaseID: String
    let dataSourceID: String
    let generatedAt: Date
    let folders: [NotionFolderManifestRecord]

    init(
        library: LibraryState,
        databaseID: String,
        dataSourceID: String,
        generatedAt: Date
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.databaseID = databaseID
        self.dataSourceID = dataSourceID
        self.generatedAt = generatedAt
        folders = library.folders
            .sorted { $0.id.rawValue.uuidString < $1.id.rawValue.uuidString }
            .map(NotionFolderManifestRecord.init)
    }
}

enum NotionLibraryManifestError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case invalidDestination
    case duplicateFolder(FolderID)
}

enum NotionLibraryManifestCodec {
    static func encode(_ manifest: NotionLibraryManifest) throws -> Data {
        try encoder().encode(manifest)
    }

    static func contentHash(_ manifest: NotionLibraryManifest) throws -> String {
        let content = NotionLibraryManifestContent(manifest: manifest)
        return NotionContentHasher.sha256Hex(of: try encoder().encode(content))
    }

    static func decode(_ data: Data) throws -> NotionLibraryManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let manifest = try decoder.decode(NotionLibraryManifest.self, from: data)

        guard manifest.schemaVersion == NotionLibraryManifest.currentSchemaVersion else {
            throw NotionLibraryManifestError.unsupportedSchema(manifest.schemaVersion)
        }
        guard UUID(uuidString: manifest.databaseID) != nil,
              UUID(uuidString: manifest.dataSourceID) != nil else {
            throw NotionLibraryManifestError.invalidDestination
        }

        var folderIDs = Set<FolderID>()
        for folder in manifest.folders where !folderIDs.insert(folder.id).inserted {
            throw NotionLibraryManifestError.duplicateFolder(folder.id)
        }

        return manifest
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

private struct NotionLibraryManifestContent: Encodable {
    let schemaVersion: Int
    let databaseID: String
    let dataSourceID: String
    let folders: [NotionFolderManifestRecord]

    init(manifest: NotionLibraryManifest) {
        schemaVersion = manifest.schemaVersion
        databaseID = manifest.databaseID
        dataSourceID = manifest.dataSourceID
        folders = manifest.folders
    }
}
