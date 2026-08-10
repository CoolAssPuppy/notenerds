import Foundation

enum DocumentOperationError: Error, Equatable {
    case canvasNotFound
    case layerNotFound
    case objectNotFound
    case invalidIndex
}

struct ObjectPlacement: Codable, Hashable, Sendable {
    let layerID: LayerID
    let index: Int
    let object: CanvasObject
}

struct CanvasPlacement: Codable, Hashable, Sendable {
    let index: Int
    let canvas: Canvas
}

struct LayerPlacement: Codable, Hashable, Sendable {
    let canvasID: CanvasID
    let index: Int
    let layer: Layer
}

enum DocumentOperation: Codable, Hashable, Sendable {
    case addStroke(canvasID: CanvasID, layerID: LayerID, stroke: Stroke)
    case deleteObjects(canvasID: CanvasID, objects: [ObjectPlacement])
    case convertStrokesToText(canvasID: CanvasID, sourceObjects: [ObjectPlacement], textBlock: TextBlock)
    case replaceObjects(canvasID: CanvasID, before: [ObjectPlacement], after: [ObjectPlacement])
    case insertCanvas(canvas: Canvas, index: Int)
    case deleteCanvas(CanvasPlacement)
    case moveCanvas(sourceIndex: Int, destinationIndex: Int)
    case renameCanvas(canvasID: CanvasID, before: String, after: String)
    case insertLayer(canvasID: CanvasID, layer: Layer, index: Int)
    case deleteLayer(LayerPlacement)
    case moveLayer(canvasID: CanvasID, sourceIndex: Int, destinationIndex: Int)
    case updateLayer(canvasID: CanvasID, before: Layer, after: Layer)
    case changeTemplate(canvasID: CanvasID, before: CanvasTemplate, after: CanvasTemplate)

    static func transformObjects(
        in notebook: Notebook,
        canvasID: CanvasID,
        objectIDs: Set<ObjectID>,
        transform: SelectionTransform,
        center: CanvasPoint,
        strokeReplacements: [Stroke] = []
    ) throws -> DocumentOperation {
        let before = try notebook.placements(of: objectIDs, in: canvasID)
        let replacementByID = Dictionary(
            uniqueKeysWithValues: strokeReplacements.map { ($0.objectID, $0) }
        )
        let after = before.map { placement in
            let transformedObject: CanvasObject
            if let replacement = replacementByID[placement.object.id] {
                transformedObject = .stroke(replacement)
            } else {
                transformedObject = placement.object.applying(transform, around: center)
            }
            return ObjectPlacement(
                layerID: placement.layerID,
                index: placement.index,
                object: transformedObject
            )
        }
        return .replaceObjects(canvasID: canvasID, before: before, after: after)
    }

    static func replacingObjects(
        in notebook: Notebook,
        canvasID: CanvasID,
        objectIDs: Set<ObjectID>,
        with replacements: [CanvasObject]
    ) throws -> DocumentOperation {
        let before = try notebook.placements(of: objectIDs, in: canvasID)
        let placementByID = Dictionary(uniqueKeysWithValues: before.map { ($0.object.id, $0) })
        let after = replacements.map { object in
            let source = placementByID[object.id]
            return ObjectPlacement(
                layerID: object.layerID,
                index: source?.index ?? Int.max,
                object: object
            )
        }
        return .replaceObjects(canvasID: canvasID, before: before, after: after)
    }

    static func snapStrokeToShape(
        canvasID: CanvasID,
        strokeID: StrokeID,
        shape: RecognizedShape,
        in notebook: Notebook
    ) throws -> DocumentOperation {
        try replacingObjects(
            in: notebook,
            canvasID: canvasID,
            objectIDs: [ObjectID(rawValue: strokeID.rawValue)],
            with: [.shape(shape)]
        )
    }

    static func convertStrokesToText(
        in notebook: Notebook,
        canvasID: CanvasID,
        strokeIDs: Set<StrokeID>,
        textBlock: TextBlock
    ) throws -> DocumentOperation {
        let objectIDs = Set(strokeIDs.map { ObjectID(rawValue: $0.rawValue) })
        let sourceObjects = try notebook.placements(of: objectIDs, in: canvasID)
        return .convertStrokesToText(
            canvasID: canvasID,
            sourceObjects: sourceObjects,
            textBlock: textBlock
        )
    }

    static func deleteObjects(
        in notebook: Notebook,
        canvasID: CanvasID,
        objectIDs: Set<ObjectID>
    ) throws -> DocumentOperation {
        .deleteObjects(canvasID: canvasID, objects: try notebook.placements(of: objectIDs, in: canvasID))
    }

    func apply(to notebook: inout Notebook) throws {
        switch self {
        case let .addStroke(canvasID, layerID, stroke):
            let location = try notebook.location(of: layerID, in: canvasID)
            notebook.canvases[location.canvas].layers[location.layer].objects.append(.stroke(stroke))
        case let .deleteObjects(canvasID, objects):
            try notebook.remove(objects: objects, from: canvasID)
        case let .convertStrokesToText(canvasID, sourceObjects, textBlock):
            try notebook.remove(objects: sourceObjects, from: canvasID)
            let location = try notebook.location(of: textBlock.layerID, in: canvasID)
            notebook.canvases[location.canvas].layers[location.layer].objects.append(.text(textBlock))
        case let .replaceObjects(canvasID, before, after):
            try notebook.remove(objects: before, from: canvasID)
            try notebook.restore(objects: after, to: canvasID)
        default:
            try applyStructure(to: &notebook)
        }
        clearHandwritingRecognition(in: &notebook)
    }

    private func applyStructure(to notebook: inout Notebook) throws {
        switch self {
        case let .insertCanvas(canvas, index):
            guard index >= 0, index <= notebook.canvases.count else { throw DocumentOperationError.invalidIndex }
            notebook.canvases.insert(canvas, at: index)
        case let .deleteCanvas(placement):
            guard notebook.canvases.count > 1,
                  let index = notebook.canvases.firstIndex(where: { $0.id == placement.canvas.id }) else {
                throw DocumentOperationError.canvasNotFound
            }
            notebook.canvases.remove(at: index)
        case let .moveCanvas(source, destination):
            try notebook.moveCanvas(from: source, to: destination)
        case let .renameCanvas(canvasID, before, after):
            try notebook.renameCanvas(canvasID, expectedName: before, to: after)
        default:
            try applyLayerStructure(to: &notebook)
        }
    }

    private func applyLayerStructure(to notebook: inout Notebook) throws {
        switch self {
        case let .insertLayer(canvasID, layer, index):
            let canvasIndex = try notebook.canvasIndex(for: canvasID)
            guard index >= 0, index <= notebook.canvases[canvasIndex].layers.count else {
                throw DocumentOperationError.invalidIndex
            }
            notebook.canvases[canvasIndex].layers.insert(layer, at: index)
        case let .deleteLayer(placement):
            let canvasIndex = try notebook.canvasIndex(for: placement.canvasID)
            try notebook.canvases[canvasIndex].deleteLayer(id: placement.layer.id)
        case let .moveLayer(canvasID, source, destination):
            let canvasIndex = try notebook.canvasIndex(for: canvasID)
            try notebook.canvases[canvasIndex].moveLayer(from: source, to: destination)
        case let .updateLayer(canvasID, before, after):
            try notebook.replaceLayer(before, with: after, in: canvasID)
        case let .changeTemplate(canvasID, _, after):
            let canvasIndex = try notebook.canvasIndex(for: canvasID)
            notebook.canvases[canvasIndex].template = after
        default:
            return
        }
    }

    func undo(on notebook: inout Notebook) throws {
        switch self {
        case let .addStroke(canvasID, layerID, stroke):
            let location = try notebook.location(of: layerID, in: canvasID)
            let objects = notebook.canvases[location.canvas].layers[location.layer].objects
            guard let index = objects.firstIndex(where: { $0.id == stroke.objectID }) else {
                throw DocumentOperationError.objectNotFound
            }
            notebook.canvases[location.canvas].layers[location.layer].objects.remove(at: index)
        case let .deleteObjects(canvasID, objects):
            try notebook.restore(objects: objects, to: canvasID)
        case let .convertStrokesToText(canvasID, sourceObjects, textBlock):
            let location = try notebook.location(of: textBlock.layerID, in: canvasID)
            let objects = notebook.canvases[location.canvas].layers[location.layer].objects
            guard let index = objects.firstIndex(where: { $0.id == textBlock.id }) else {
                throw DocumentOperationError.objectNotFound
            }
            notebook.canvases[location.canvas].layers[location.layer].objects.remove(at: index)
            try notebook.restore(objects: sourceObjects, to: canvasID)
        case let .replaceObjects(canvasID, before, after):
            try notebook.remove(objects: after, from: canvasID)
            try notebook.restore(objects: before, to: canvasID)
        default:
            try undoStructure(on: &notebook)
        }
        clearHandwritingRecognition(in: &notebook)
    }

    private func clearHandwritingRecognition(in notebook: inout Notebook) {
        guard changesHandwritingRecognition,
              let canvasID = handwritingRecognitionCanvasID else { return }
        notebook.recognitionByCanvas[canvasID] = nil
    }

    private func undoStructure(on notebook: inout Notebook) throws {
        switch self {
        case let .insertCanvas(canvas, _):
            guard let index = notebook.canvases.firstIndex(where: { $0.id == canvas.id }),
                  notebook.canvases.count > 1 else { throw DocumentOperationError.canvasNotFound }
            notebook.canvases.remove(at: index)
        case let .deleteCanvas(placement):
            guard placement.index >= 0, placement.index <= notebook.canvases.count else {
                throw DocumentOperationError.invalidIndex
            }
            notebook.canvases.insert(placement.canvas, at: placement.index)
        case let .moveCanvas(source, destination):
            try notebook.moveCanvas(from: destination, to: source)
        case let .renameCanvas(canvasID, before, after):
            try notebook.renameCanvas(canvasID, expectedName: after, to: before)
        default:
            try undoLayerStructure(on: &notebook)
        }
    }

    private func undoLayerStructure(on notebook: inout Notebook) throws {
        switch self {
        case let .insertLayer(canvasID, layer, _):
            let canvasIndex = try notebook.canvasIndex(for: canvasID)
            try notebook.canvases[canvasIndex].deleteLayer(id: layer.id)
        case let .deleteLayer(placement):
            let canvasIndex = try notebook.canvasIndex(for: placement.canvasID)
            guard placement.index >= 0, placement.index <= notebook.canvases[canvasIndex].layers.count else {
                throw DocumentOperationError.invalidIndex
            }
            notebook.canvases[canvasIndex].layers.insert(placement.layer, at: placement.index)
        case let .moveLayer(canvasID, source, destination):
            let canvasIndex = try notebook.canvasIndex(for: canvasID)
            try notebook.canvases[canvasIndex].moveLayer(from: destination, to: source)
        case let .updateLayer(canvasID, before, after):
            try notebook.replaceLayer(after, with: before, in: canvasID)
        case let .changeTemplate(canvasID, before, _):
            let canvasIndex = try notebook.canvasIndex(for: canvasID)
            notebook.canvases[canvasIndex].template = before
        default:
            return
        }
    }
}

extension DocumentOperation {
    var requiresSearchIndexUpdate: Bool {
        switch self {
        case .addStroke, .moveCanvas, .renameCanvas, .moveLayer, .updateLayer, .changeTemplate:
            false
        case let .deleteObjects(_, objects): objects.contains { $0.object.searchText != nil }
        case .convertStrokesToText: true
        case let .replaceObjects(_, before, after):
            (before + after).contains { $0.object.searchText != nil }
        case let .insertCanvas(canvas, _): canvas.containsSearchableContent
        case let .deleteCanvas(placement): placement.canvas.containsSearchableContent
        case let .insertLayer(_, layer, _): layer.objects.contains { $0.searchText != nil }
        case let .deleteLayer(placement): placement.layer.objects.contains { $0.searchText != nil }
        }
    }

    var searchCanvasID: CanvasID? {
        switch self {
        case let .addStroke(canvasID, _, _),
             let .deleteObjects(canvasID, _),
             let .convertStrokesToText(canvasID, _, _),
             let .replaceObjects(canvasID, _, _),
             let .insertLayer(canvasID, _, _),
             let .moveLayer(canvasID, _, _),
             let .updateLayer(canvasID, _, _),
             let .changeTemplate(canvasID, _, _):
            canvasID
        case let .deleteLayer(placement): placement.canvasID
        case .insertCanvas, .deleteCanvas, .moveCanvas, .renameCanvas: nil
        }
    }
}

private extension CanvasObject {
    var searchText: String? {
        switch self {
        case let .text(text): text.text
        case let .pdf(pdf): pdf.embeddedText
        case .stroke, .shape, .image: nil
        }
    }
}

private extension Canvas {
    var containsSearchableContent: Bool {
        layers.flatMap(\.objects).contains { $0.searchText != nil }
    }
}

private extension Notebook {
    mutating func renameCanvas(_ canvasID: CanvasID, expectedName: String, to name: String) throws {
        let index = try canvasIndex(for: canvasID)
        guard canvases[index].title == expectedName else { throw DocumentOperationError.canvasNotFound }
        canvases[index].title = name
    }

    mutating func replaceLayer(_ expected: Layer, with replacement: Layer, in canvasID: CanvasID) throws {
        let canvasIndex = try canvasIndex(for: canvasID)
        guard expected.id == replacement.id,
              let layerIndex = canvases[canvasIndex].layers.firstIndex(where: { $0.id == expected.id }) else {
            throw DocumentOperationError.layerNotFound
        }
        canvases[canvasIndex].layers[layerIndex] = replacement
    }

    func canvasIndex(for canvasID: CanvasID) throws -> Int {
        guard let index = canvases.firstIndex(where: { $0.id == canvasID }) else {
            throw DocumentOperationError.canvasNotFound
        }
        return index
    }

    func placements(of objectIDs: Set<ObjectID>, in canvasID: CanvasID) throws -> [ObjectPlacement] {
        guard let canvas = canvases.first(where: { $0.id == canvasID }) else {
            throw DocumentOperationError.canvasNotFound
        }
        return canvas.layers.flatMap { layer in
            layer.objects.enumerated().compactMap { index, object in
                objectIDs.contains(object.id)
                    ? ObjectPlacement(layerID: layer.id, index: index, object: object)
                    : nil
            }
        }
    }

    func location(of layerID: LayerID, in canvasID: CanvasID) throws -> (canvas: Int, layer: Int) {
        guard let canvasIndex = canvases.firstIndex(where: { $0.id == canvasID }) else {
            throw DocumentOperationError.canvasNotFound
        }
        guard let layerIndex = canvases[canvasIndex].layers.firstIndex(where: { $0.id == layerID }) else {
            throw DocumentOperationError.layerNotFound
        }
        return (canvasIndex, layerIndex)
    }

    mutating func remove(objects placements: [ObjectPlacement], from canvasID: CanvasID) throws {
        for placement in placements {
            let location = try location(of: placement.layerID, in: canvasID)
            let objectID = placement.object.id
            guard let index = canvases[location.canvas].layers[location.layer].objects.firstIndex(where: {
                $0.id == objectID
            }) else {
                throw DocumentOperationError.objectNotFound
            }
            canvases[location.canvas].layers[location.layer].objects.remove(at: index)
        }
    }

    mutating func restore(objects placements: [ObjectPlacement], to canvasID: CanvasID) throws {
        let orderedPlacements = placements.sorted { first, second in
            first.layerID == second.layerID ? first.index < second.index : first.index < second.index
        }
        for placement in orderedPlacements {
            let location = try location(of: placement.layerID, in: canvasID)
            let count = canvases[location.canvas].layers[location.layer].objects.count
            canvases[location.canvas].layers[location.layer].objects.insert(
                placement.object,
                at: min(placement.index, count)
            )
        }
    }
}
