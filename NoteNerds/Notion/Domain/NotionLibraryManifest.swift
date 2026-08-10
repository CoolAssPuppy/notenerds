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
    let icon: FolderIcon
    let iconColor: FolderIconColor?
    let appearanceModifiedAt: Date?
    let inheritedTrashDate: Date?

    init(folder: Folder) {
        id = folder.id
        name = folder.name
        parentID = folder.parentID
        createdAt = folder.createdAt
        modifiedAt = folder.modifiedAt
        isFavorite = folder.isFavorite
        tags = folder.tags.sorted()
        trashedAt = folder.trashedAt
        icon = folder.icon
        iconColor = folder.iconColor
        appearanceModifiedAt = folder.appearanceModifiedAt
        inheritedTrashDate = folder.inheritedTrashDate
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, parentID, createdAt, modifiedAt, isFavorite, tags, trashedAt
        case icon, iconColor, appearanceModifiedAt, inheritedTrashDate
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(FolderID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        parentID = try values.decodeIfPresent(FolderID.self, forKey: .parentID)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        modifiedAt = try values.decode(Date.self, forKey: .modifiedAt)
        isFavorite = try values.decode(Bool.self, forKey: .isFavorite)
        tags = try values.decode([String].self, forKey: .tags)
        trashedAt = try values.decodeIfPresent(Date.self, forKey: .trashedAt)
        icon = values.contains(.icon)
            ? try values.decode(FolderIcon.self, forKey: .icon)
            : .standard
        iconColor = try values.decodeIfPresent(FolderIconColor.self, forKey: .iconColor)
        appearanceModifiedAt = try values.decodeIfPresent(Date.self, forKey: .appearanceModifiedAt)
        inheritedTrashDate = try values.decodeIfPresent(Date.self, forKey: .inheritedTrashDate)
    }

    var folder: Folder {
        Folder(
            id: id,
            name: name,
            parentID: parentID,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            isFavorite: isFavorite,
            tags: Set(tags),
            trashedAt: trashedAt,
            icon: icon,
            iconColor: iconColor,
            appearanceModifiedAt: appearanceModifiedAt,
            inheritedTrashDate: inheritedTrashDate
        )
    }
}

struct NotionNotebookTrashProvenanceRecord: Codable, Equatable, Sendable {
    let notebookID: NotebookID
    let inheritedTrashDate: Date
}

struct NotionLibraryManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let databaseID: String
    let dataSourceID: String
    let generatedAt: Date
    let folders: [NotionFolderManifestRecord]
    let notebookTrashProvenance: [NotionNotebookTrashProvenanceRecord]

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
        notebookTrashProvenance = library.notebooks
            .compactMap { notebook -> NotionNotebookTrashProvenanceRecord? in
                guard let trashDate = library.inheritedTrashDate(forNotebook: notebook.id) else {
                    return nil
                }
                return NotionNotebookTrashProvenanceRecord(
                    notebookID: notebook.id,
                    inheritedTrashDate: trashDate
                )
            }
            .sorted {
                $0.notebookID.rawValue.uuidString < $1.notebookID.rawValue.uuidString
            }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, databaseID, dataSourceID, generatedAt, folders
        case notebookTrashProvenance
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        databaseID = try values.decode(String.self, forKey: .databaseID)
        dataSourceID = try values.decode(String.self, forKey: .dataSourceID)
        generatedAt = try values.decode(Date.self, forKey: .generatedAt)
        folders = try values.decode([NotionFolderManifestRecord].self, forKey: .folders)
        notebookTrashProvenance = try values.decodeIfPresent(
            [NotionNotebookTrashProvenanceRecord].self,
            forKey: .notebookTrashProvenance
        ) ?? []
    }
}

enum NotionLibraryManifestError: Error, Equatable, Sendable {
    case unsupportedSchema(Int)
    case invalidDestination
    case duplicateFolder(FolderID)
    case manifestTooLarge
}

enum NotionLibraryManifestCodec {
    static let maximumByteCount = 10 * 1_024 * 1_024

    static func encode(_ manifest: NotionLibraryManifest) throws -> Data {
        try encodeWithinLimit(manifest)
    }

    static func contentHash(_ manifest: NotionLibraryManifest) throws -> String {
        let content = NotionLibraryManifestContent(manifest: manifest)
        return NotionContentHasher.sha256Hex(of: try encodeWithinLimit(content))
    }

    static func decode(_ data: Data) throws -> NotionLibraryManifest {
        guard data.count <= maximumByteCount else {
            throw NotionLibraryManifestError.manifestTooLarge
        }
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

    private static func encodeWithinLimit<T: Encodable>(_ value: T) throws -> Data {
        let data = try encoder().encode(value)
        guard data.count <= maximumByteCount else {
            throw NotionLibraryManifestError.manifestTooLarge
        }
        return data
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
    let notebookTrashProvenance: [NotionNotebookTrashProvenanceRecord]

    init(manifest: NotionLibraryManifest) {
        schemaVersion = manifest.schemaVersion
        databaseID = manifest.databaseID
        dataSourceID = manifest.dataSourceID
        folders = manifest.folders
        notebookTrashProvenance = manifest.notebookTrashProvenance
    }
}
