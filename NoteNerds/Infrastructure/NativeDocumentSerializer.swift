import Foundation

struct DocumentSchemaVersion: RawRepresentable, Codable, Hashable, Sendable {
    static let current = DocumentSchemaVersion(rawValue: 6)

    let rawValue: Int
}

struct NativeNotebookPackage: Codable, Equatable, Sendable {
    var schemaVersion: DocumentSchemaVersion
    var notebook: Notebook
    var appliedRemoteChangeIDs: Set<ChangeID>

    init(
        schemaVersion: DocumentSchemaVersion,
        notebook: Notebook,
        appliedRemoteChangeIDs: Set<ChangeID> = []
    ) {
        self.schemaVersion = schemaVersion
        self.notebook = notebook
        self.appliedRemoteChangeIDs = appliedRemoteChangeIDs
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case notebook
        case appliedRemoteChangeIDs
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(DocumentSchemaVersion.self, forKey: .schemaVersion)
        notebook = try values.decode(Notebook.self, forKey: .notebook)
        let identifiers = try values.decodeIfPresent([UUID].self, forKey: .appliedRemoteChangeIDs) ?? []
        appliedRemoteChangeIDs = Set(identifiers.map(ChangeID.init(rawValue:)))
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(notebook, forKey: .notebook)
        try values.encode(
            appliedRemoteChangeIDs
                .map(\.rawValue)
                .sorted { $0.uuidString < $1.uuidString },
            forKey: .appliedRemoteChangeIDs
        )
    }
}

enum NativeDocumentError: Error, Equatable {
    case unsupportedNewerVersion(Int)
}

struct NativeDocumentSerializer: Sendable {
    private struct Header: Decodable {
        let schemaVersion: DocumentSchemaVersion
    }

    func encode(_ package: NativeNotebookPackage) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(package)
    }

    func decode(_ data: Data) throws -> NativeNotebookPackage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let header = try decoder.decode(Header.self, from: data)
        guard header.schemaVersion.rawValue <= DocumentSchemaVersion.current.rawValue else {
            throw NativeDocumentError.unsupportedNewerVersion(header.schemaVersion.rawValue)
        }
        var package = try decoder.decode(NativeNotebookPackage.self, from: data)
        package.schemaVersion = .current
        return package
    }
}
