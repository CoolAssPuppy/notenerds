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

/// What a change turned out to be once its JSON was read.
enum SyncChangePayload: Hashable, Sendable {
    case document(SyncedDocumentAction)
    case library(LibrarySyncMutation)

    var documentAction: SyncedDocumentAction? {
        guard case let .document(action) = self else { return nil }
        return action
    }

    var libraryMutation: LibrarySyncMutation? {
        guard case let .library(mutation) = self else { return nil }
        return mutation
    }
}

struct SyncChangeEncoder: Sendable {
    static let maximumLibraryMutationPayloadByteCount = 1_024 * 1_024
    static let maximumChangePayloadByteCount = 512 * 1_024 * 1_024
    static let maximumEnvelopePrefixByteCount = 512

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
        return DocumentChange(
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

    /// Reads a change's JSON once and reports what it holds.
    ///
    /// A stroke payload carries every sample of a gesture, so a single decode
    /// can run into megabytes. Callers that need to know both what kind of
    /// change this is and what it says must go through here rather than
    /// decoding the same bytes again for each question.
    static func decodePayload(_ change: DocumentChange) throws -> SyncChangePayload {
        try enforcePayloadSizeLimit(for: change)
        guard let payload = try? makeDecoder().decode(Payload.self, from: change.payload) else {
            let operation = try makeDecoder().decode(DocumentOperation.self, from: change.payload)
            return .document(SyncedDocumentAction(operation: operation, direction: .apply))
        }
        switch payload {
        case let .document(action):
            return .document(action)
        case let .library(mutation):
            try validate(mutation, against: change)
            return .library(mutation)
        }
    }

    static func decode(_ change: DocumentChange) throws -> DocumentOperation {
        try decodeDocumentAction(change).operation
    }

    static func decodeDocumentAction(_ change: DocumentChange) throws -> SyncedDocumentAction {
        guard let action = try decodePayload(change).documentAction else {
            throw CocoaError(.coderInvalidValue)
        }
        return action
    }

    func change(
        for mutation: LibrarySyncMutation,
        notebookID: NotebookID,
        sequence: Int,
        timestamp: Date = Date()
    ) throws -> DocumentChange {
        let payload = try Self.makeEncoder().encode(Payload.library(mutation))
        if mutation.objectKey.hasPrefix("folder:"),
           payload.count > Self.maximumLibraryMutationPayloadByteCount {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        return DocumentChange(
            id: ChangeID(),
            notebookID: notebookID,
            objectKey: mutation.objectKey,
            kind: mutation.isPermanentDeletion ? .delete : .upsert,
            payload: payload,
            timestamp: timestamp,
            deviceID: deviceID,
            sequence: sequence
        )
    }

    static func decodeLibraryMutation(_ change: DocumentChange) throws -> LibrarySyncMutation {
        guard let mutation = try decodePayload(change).libraryMutation else {
            throw CocoaError(.coderInvalidValue)
        }
        return mutation
    }

    /// Rejects an oversized payload before anything decodes it.
    ///
    /// Reading the envelope's first few keys costs a few hundred bytes and
    /// tells us which limit applies, which is what stops a runaway folder
    /// mutation from being parsed at all.
    private static func enforcePayloadSizeLimit(for change: DocumentChange) throws {
        var preflight = SyncPayloadEnvelopePreflight(
            prefix: Data(change.payload.prefix(maximumEnvelopePrefixByteCount))
        )
        guard let kind = try? preflight.payloadKind() else { return }
        let maximumByteCount = switch kind {
        case .folderMutation: maximumLibraryMutationPayloadByteCount
        case .general: maximumChangePayloadByteCount
        }
        guard change.payload.count <= maximumByteCount else {
            throw CocoaError(.fileReadTooLarge)
        }
    }

    private static func validate(
        _ mutation: LibrarySyncMutation,
        against change: DocumentChange
    ) throws {
        guard !mutation.objectKey.hasPrefix("folder:")
                || change.payload.count <= maximumLibraryMutationPayloadByteCount else {
            throw CocoaError(.fileReadTooLarge)
        }
        guard mutation.objectKey == change.objectKey else {
            throw CocoaError(.coderInvalidValue)
        }
    }

    static func maximumPayloadByteCount(forEnvelopePrefix prefix: Data) -> Int {
        var preflight = SyncPayloadEnvelopePreflight(prefix: prefix)
        guard let kind = try? preflight.payloadKind() else {
            return maximumLibraryMutationPayloadByteCount
        }
        switch kind {
        case .folderMutation: return maximumLibraryMutationPayloadByteCount
        case .general: return maximumChangePayloadByteCount
        }
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

private struct SyncPayloadEnvelopePreflight {
    private static let folderMutationNames: Set<String> = [
        "createFolder", "updateFolder", "trashFolder", "restoreFolder", "deleteFolder"
    ]
    private static let notebookMutationNames: Set<String> = [
        "createNotebook", "updateNotebookMetadata", "restoreNotebook", "deleteNotebook"
    ]
    private static let legacyDocumentNames: Set<String> = [
        "addStroke", "deleteObjects", "convertStrokesToText", "replaceObjects",
        "insertCanvas", "deleteCanvas", "moveCanvas", "renameCanvas",
        "insertLayer", "deleteLayer", "moveLayer", "updateLayer", "changeTemplate"
    ]

    private let bytes: [UInt8]
    private var index = 0

    init(prefix: Data) {
        bytes = Array(prefix)
    }

    mutating func payloadKind() throws -> SyncPayloadEnvelopeKind {
        try consume(0x7B)
        let payloadName = try readString()
        try consume(0x3A)
        if payloadName == "document" || Self.legacyDocumentNames.contains(payloadName) {
            return .general
        }
        guard payloadName == "library" else { throw CocoaError(.coderInvalidValue) }
        try consume(0x7B)
        guard try readString() == "_0" else { throw CocoaError(.coderInvalidValue) }
        try consume(0x3A)
        try consume(0x7B)
        let mutationName = try readString()
        if Self.folderMutationNames.contains(mutationName) { return .folderMutation }
        guard Self.notebookMutationNames.contains(mutationName) else {
            throw CocoaError(.coderInvalidValue)
        }
        return .general
    }

    private mutating func consume(_ expected: UInt8) throws {
        skipWhitespace()
        guard index < bytes.count, bytes[index] == expected else {
            throw CocoaError(.coderInvalidValue)
        }
        index += 1
    }

    private mutating func readString() throws -> String {
        skipWhitespace()
        guard index < bytes.count, bytes[index] == 0x22 else {
            throw CocoaError(.coderInvalidValue)
        }
        let start = index
        index += 1
        var isEscaped = false
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x22, !isEscaped {
                let encoded = Data(bytes[start...index])
                index += 1
                return try JSONDecoder().decode(String.self, from: encoded)
            }
            if isEscaped {
                isEscaped = false
            } else if byte == 0x5C {
                isEscaped = true
            }
            index += 1
        }
        throw CocoaError(.coderInvalidValue)
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, [0x09, 0x0A, 0x0D, 0x20].contains(bytes[index]) {
            index += 1
        }
    }
}

private enum SyncPayloadEnvelopeKind {
    case folderMutation
    case general
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
        case let .renameCanvas(canvasID, _, _): canvasID.rawValue.uuidString
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
        case .insertCanvas, .deleteCanvas, .renameCanvas: "canvas:\(affectedObjectIdentifier)"
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
