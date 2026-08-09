import Foundation

struct DocumentSchemaVersion: RawRepresentable, Codable, Hashable, Sendable {
    static let current = DocumentSchemaVersion(rawValue: 5)

    let rawValue: Int
}

struct NativeNotebookPackage: Codable, Equatable, Sendable {
    var schemaVersion: DocumentSchemaVersion
    var notebook: Notebook
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
