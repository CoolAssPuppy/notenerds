import Foundation

enum SyncedDocumentDirection: String, Codable, Sendable {
    case apply
    case undo
}

struct SyncedDocumentAction: Codable, Hashable, Sendable {
    let operation: DocumentOperation
    let direction: SyncedDocumentDirection

    func perform(on notebook: inout Notebook) throws {
        switch direction {
        case .apply: try operation.apply(to: &notebook)
        case .undo: try operation.undo(on: &notebook)
        }
    }
}

struct SyncChangeEncoder: Sendable {
    private enum Payload: Codable {
        case document(SyncedDocumentAction)
        case library(LibrarySyncMutation)
    }

    let deviceID: String

    func change(
        for operation: DocumentOperation,
        notebookID: NotebookID,
        sequence: Int,
        timestamp: Date = Date()
    ) throws -> DocumentChange {
        try change(
            for: SyncedDocumentAction(operation: operation, direction: .apply),
            notebookID: notebookID,
            sequence: sequence,
            timestamp: timestamp
        )
    }

    func change(
        for action: SyncedDocumentAction,
        notebookID: NotebookID,
        sequence: Int,
        timestamp: Date = Date()
    ) throws -> DocumentChange {
        DocumentChange(
            id: ChangeID(),
            notebookID: notebookID,
            objectKey: action.operation.syncObjectKey,
            kind: action.direction == .apply && action.operation.isDeletion ? .delete : .upsert,
            payload: try Self.makeEncoder().encode(Payload.document(action)),
            timestamp: timestamp,
            deviceID: deviceID,
            sequence: sequence
        )
    }

    static func decode(_ change: DocumentChange) throws -> DocumentOperation {
        if let payload = try? makeDecoder().decode(Payload.self, from: change.payload),
           case let .document(action) = payload {
            return action.operation
        }
        return try makeDecoder().decode(DocumentOperation.self, from: change.payload)
    }

    static func decodeDocumentAction(_ change: DocumentChange) throws -> SyncedDocumentAction {
        if let payload = try? makeDecoder().decode(Payload.self, from: change.payload),
           case let .document(action) = payload {
            return action
        }
        return SyncedDocumentAction(operation: try decode(change), direction: .apply)
    }

    func change(
        for mutation: LibrarySyncMutation,
        notebookID: NotebookID,
        sequence: Int,
        timestamp: Date = Date()
    ) throws -> DocumentChange {
        DocumentChange(
            id: ChangeID(),
            notebookID: notebookID,
            objectKey: mutation.objectKey,
            kind: mutation.isPermanentDeletion ? .delete : .upsert,
            payload: try Self.makeEncoder().encode(Payload.library(mutation)),
            timestamp: timestamp,
            deviceID: deviceID,
            sequence: sequence
        )
    }

    static func decodeLibraryMutation(_ change: DocumentChange) throws -> LibrarySyncMutation {
        let payload = try makeDecoder().decode(Payload.self, from: change.payload)
        guard case let .library(mutation) = payload else {
            throw CocoaError(.coderInvalidValue)
        }
        return mutation
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

extension DocumentOperation {
    var affectedObjectIdentifier: String {
        switch self {
        case let .addStroke(_, _, stroke): stroke.id.rawValue.uuidString
        case let .deleteObjects(_, objects):
            objects.map(\.object.id.rawValue.uuidString).sorted().joined(separator: ",")
        case let .convertStrokesToText(_, _, text): text.id.rawValue.uuidString
        case let .replaceObjects(_, before, after):
            (after.first ?? before.first)?.object.id.rawValue.uuidString ?? "objects"
        case let .insertCanvas(canvas, _): canvas.id.rawValue.uuidString
        case let .deleteCanvas(placement): placement.canvas.id.rawValue.uuidString
        case let .moveCanvas(source, destination): "\(source)-\(destination)"
        case let .insertLayer(_, layer, _): layer.id.rawValue.uuidString
        case let .deleteLayer(placement): placement.layer.id.rawValue.uuidString
        case let .moveLayer(canvasID, _, _): canvasID.rawValue.uuidString
        case let .updateLayer(_, _, after): after.id.rawValue.uuidString
        case let .changeTemplate(canvasID, _, _): canvasID.rawValue.uuidString
        }
    }

    var syncObjectKey: String {
        switch self {
        case .addStroke: "stroke:\(affectedObjectIdentifier)"
        case .deleteObjects, .replaceObjects, .convertStrokesToText: "object:\(affectedObjectIdentifier)"
        case .insertCanvas, .deleteCanvas: "canvas:\(affectedObjectIdentifier)"
        case .moveCanvas: "canvas-order"
        case .insertLayer, .deleteLayer, .updateLayer: "layer:\(affectedObjectIdentifier)"
        case .moveLayer: "layer-order:\(affectedObjectIdentifier)"
        case .changeTemplate: "template:\(affectedObjectIdentifier)"
        }
    }

    var isDeletion: Bool {
        switch self {
        case .deleteObjects, .deleteCanvas, .deleteLayer: true
        default: false
        }
    }
}
