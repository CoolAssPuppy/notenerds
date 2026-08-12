import Foundation

struct DocumentSchemaVersion: RawRepresentable, Codable, Hashable, Sendable {
    static let current = DocumentSchemaVersion(rawValue: 7)

    /// The first version whose strokes are guaranteed to drop their PencilKit
    /// archive whenever their samples or style change.
    ///
    /// Notes written before this could hold an archive describing ink the
    /// stroke no longer has, so they are repaired once as they load. Notes at
    /// or above it are trusted, which keeps that work off every launch.
    static let selfInvalidatingStrokeArchives = DocumentSchemaVersion(rawValue: 7)

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
        let decoded = try decoder.decode(NativeNotebookPackage.self, from: data)
        var package = try validatedPackage(decoded)
        package.repairStrokeArchivesIfWrittenBeforeSelfInvalidation(storedVersion: decoded.schemaVersion)
        return package
    }

    func validatedPackage(_ package: NativeNotebookPackage) throws -> NativeNotebookPackage {
        guard package.schemaVersion.rawValue <= DocumentSchemaVersion.current.rawValue else {
            throw NativeDocumentError.unsupportedNewerVersion(package.schemaVersion.rawValue)
        }
        var package = package
        package.schemaVersion = .current
        return package
    }
}

extension NativeNotebookPackage {
    /// Clears PencilKit archives that no longer match their stroke, for notes
    /// written before strokes invalidated their own archive.
    ///
    /// Rendering trusts a stored archive rather than re-deriving it, so older
    /// notes are repaired once. Gating on the stored version keeps this off the
    /// launch path for every note the app has already saved: a repaired note is
    /// written back at the current version and never re-checked.
    /// Returns whether the note needed repairing, so the caller can write the
    /// repaired copy back and stop it being checked again.
    @discardableResult
    mutating func repairStrokeArchivesIfWrittenBeforeSelfInvalidation(
        storedVersion: DocumentSchemaVersion
    ) -> Bool {
        guard storedVersion.rawValue < DocumentSchemaVersion.selfInvalidatingStrokeArchives.rawValue else {
            return false
        }
        let title = notebook.title
        CanvasDiagnostics.measure("repair archives \(title)") {
            notebook.performStrokeArchiveRepair()
        }
        return true
    }
}

extension Notebook {
    fileprivate mutating func performStrokeArchiveRepair() {
        for canvasIndex in canvases.indices {
            for layerIndex in canvases[canvasIndex].layers.indices {
                let objects = canvases[canvasIndex].layers[layerIndex].objects
                canvases[canvasIndex].layers[layerIndex].objects = objects.map { object in
                    guard case let .stroke(stroke) = object else { return object }
                    return .stroke(PencilKitStrokeArchiveCodec.validated(stroke))
                }
            }
        }
    }
}
