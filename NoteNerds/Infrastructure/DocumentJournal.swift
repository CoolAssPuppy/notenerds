import Foundation

struct DocumentJournalEntry: Codable {
    let storageVersion: Int
    let sequence: UInt64
    let action: SyncedDocumentAction
    let sidecarCount: Int

    init(
        storageVersion: Int,
        sequence: UInt64,
        action: SyncedDocumentAction,
        sidecarCount: Int = 0
    ) {
        self.storageVersion = storageVersion
        self.sequence = sequence
        self.action = action
        self.sidecarCount = sidecarCount
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        storageVersion = try values.decode(Int.self, forKey: .storageVersion)
        sequence = try values.decode(UInt64.self, forKey: .sequence)
        sidecarCount = try values.decodeIfPresent(Int.self, forKey: .sidecarCount) ?? 0
        if let action = try values.decodeIfPresent(SyncedDocumentAction.self, forKey: .action) {
            self.action = action
        } else {
            action = SyncedDocumentAction(
                operation: try values.decode(DocumentOperation.self, forKey: .operation),
                direction: .apply
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(storageVersion, forKey: .storageVersion)
        try values.encode(sequence, forKey: .sequence)
        try values.encode(action, forKey: .action)
        if sidecarCount > 0 {
            try values.encode(sidecarCount, forKey: .sidecarCount)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case storageVersion
        case sequence
        case action
        case operation
        case sidecarCount
    }
}

struct DocumentJournalSidecarArchive: Codable, Equatable, Sendable {
    let index: Int
    let archive: PencilKitStrokeArchive
}

enum DocumentJournal {
    static let currentStorageVersion = 3

    struct PreparedAction {
        let action: SyncedDocumentAction
        let sidecar: [DocumentJournalSidecarArchive]
    }

    static func preparing(_ action: SyncedDocumentAction) -> PreparedAction {
        var sidecar: [DocumentJournalSidecarArchive] = []
        var index = 0
        let operation = mappingStrokes(in: action.operation) { stroke in
            defer { index += 1 }
            guard let archive = stroke.pencilKitArchive else { return stroke }
            sidecar.append(DocumentJournalSidecarArchive(index: index, archive: archive))
            return Stroke(
                id: stroke.id,
                layerID: stroke.layerID,
                samples: [],
                style: stroke.style,
                createdAt: stroke.createdAt
            )
        }
        return PreparedAction(
            action: SyncedDocumentAction(operation: operation, direction: action.direction),
            sidecar: sidecar
        )
    }

    static func restoring(
        _ action: SyncedDocumentAction,
        sidecar: [DocumentJournalSidecarArchive]
    ) -> SyncedDocumentAction {
        let archives = Dictionary(uniqueKeysWithValues: sidecar.map { ($0.index, $0.archive) })
        var index = 0
        let operation = mappingStrokes(in: action.operation) { stroke in
            defer { index += 1 }
            guard let archive = archives[index] else { return stroke }
            let restored = Stroke(
                id: stroke.id,
                layerID: stroke.layerID,
                samples: stroke.samples,
                style: stroke.style,
                createdAt: stroke.createdAt,
                pencilKitArchive: archive
            )
            guard restored.samples.isEmpty,
                  let pencilStroke = PencilKitStrokeArchiveCodec.stroke(for: restored) else {
                return restored
            }
            return Stroke(
                id: restored.id,
                layerID: restored.layerID,
                samples: PencilKitStrokeArchiveCodec.samples(from: pencilStroke),
                style: restored.style,
                createdAt: restored.createdAt,
                pencilKitArchive: archive
            )
        }
        return SyncedDocumentAction(operation: operation, direction: action.direction)
    }

    static func sidecarDirectoryURL(for notebookID: NotebookID, journalsURL: URL) -> URL {
        journalsURL.appending(
            path: "\(notebookID.rawValue.uuidString).sidecars",
            directoryHint: .isDirectory
        )
    }

    static func sidecarURL(for notebookID: NotebookID, sequence: UInt64, journalsURL: URL) -> URL {
        sidecarDirectoryURL(for: notebookID, journalsURL: journalsURL)
            .appending(path: "\(sequence).plist")
    }

    static func writeSidecar(
        _ sidecar: [DocumentJournalSidecarArchive],
        notebookID: NotebookID,
        sequence: UInt64,
        journalsURL: URL
    ) throws {
        let directory = sidecarDirectoryURL(for: notebookID, journalsURL: journalsURL)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(sidecar).write(
            to: sidecarURL(for: notebookID, sequence: sequence, journalsURL: journalsURL),
            options: [.atomic, .completeFileProtection]
        )
    }

    static func readSidecar(
        notebookID: NotebookID,
        sequence: UInt64,
        journalsURL: URL
    ) throws -> [DocumentJournalSidecarArchive]? {
        let url = sidecarURL(for: notebookID, sequence: sequence, journalsURL: journalsURL)
        guard let data = try BoundedFileReader(maximumByteCount: 16 * 1_024 * 1_024)
            .readIfPresent(from: url) else { return nil }
        return try? PropertyListDecoder().decode([DocumentJournalSidecarArchive].self, from: data)
    }

    static func removeSidecars(for notebookID: NotebookID, journalsURL: URL) throws {
        let directory = sidecarDirectoryURL(for: notebookID, journalsURL: journalsURL)
        if FileManager.default.fileExists(atPath: directory.path()) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}

extension DocumentJournal {
    fileprivate static func mappingStrokes(
        in operation: DocumentOperation,
        update: (Stroke) -> Stroke
    ) -> DocumentOperation {
        switch operation {
        case let .addStroke(canvasID, layerID, stroke):
            return .addStroke(canvasID: canvasID, layerID: layerID, stroke: update(stroke))
        case let .deleteObjects(canvasID, objects):
            return .deleteObjects(canvasID: canvasID, objects: objects.map { $0.mappingStroke(update) })
        case let .convertStrokesToText(canvasID, sourceObjects, textBlock):
            return .convertStrokesToText(
                canvasID: canvasID,
                sourceObjects: sourceObjects.map { $0.mappingStroke(update) },
                textBlock: textBlock
            )
        case let .replaceObjects(canvasID, before, after):
            return .replaceObjects(
                canvasID: canvasID,
                before: before.map { $0.mappingStroke(update) },
                after: after.map { $0.mappingStroke(update) }
            )
        case let .insertCanvas(canvas, index):
            return .insertCanvas(canvas: canvas.mappingStrokes(update), index: index)
        case let .deleteCanvas(placement):
            return .deleteCanvas(
                CanvasPlacement(index: placement.index, canvas: placement.canvas.mappingStrokes(update))
            )
        case let .insertLayer(canvasID, layer, index):
            return .insertLayer(canvasID: canvasID, layer: layer.mappingStrokes(update), index: index)
        case let .deleteLayer(placement):
            return .deleteLayer(
                LayerPlacement(
                    canvasID: placement.canvasID,
                    index: placement.index,
                    layer: placement.layer.mappingStrokes(update)
                )
            )
        case let .updateLayer(canvasID, before, after):
            return .updateLayer(
                canvasID: canvasID,
                before: before.mappingStrokes(update),
                after: after.mappingStrokes(update)
            )
        case .moveCanvas, .renameCanvas, .moveLayer, .changeTemplate:
            return operation
        }
    }
}

private extension ObjectPlacement {
    func mappingStroke(_ update: (Stroke) -> Stroke) -> ObjectPlacement {
        ObjectPlacement(layerID: layerID, index: index, object: object.mappingStroke(update))
    }
}

private extension CanvasObject {
    func mappingStroke(_ update: (Stroke) -> Stroke) -> CanvasObject {
        guard case let .stroke(stroke) = self else { return self }
        return .stroke(update(stroke))
    }
}

private extension Layer {
    func mappingStrokes(_ update: (Stroke) -> Stroke) -> Layer {
        Layer(id: id, name: name, isVisible: isVisible, objects: objects.map { $0.mappingStroke(update) })
    }
}

private extension Canvas {
    func mappingStrokes(_ update: (Stroke) -> Stroke) -> Canvas {
        Canvas(
            id: id,
            title: title,
            template: template,
            layers: layers.map { $0.mappingStrokes(update) },
            createdAt: createdAt,
            modifiedAt: modifiedAt
        )
    }
}
