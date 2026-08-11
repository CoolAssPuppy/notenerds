import Foundation

struct TextBlockInsertion {
    let text: String
    let fontSize: Double
    let alignment: TextAlignment
    let fontName: String?
    let frame: CanvasRect
    let layerID: LayerID
    let canvasID: CanvasID
}

struct ShapeInsertion {
    let kind: RecognizedShapeKind
    let point: CanvasPoint
    let style: StrokeStyle
    let layerID: LayerID
    let canvasID: CanvasID
}

struct CanvasObjectTransformRequest {
    let objectIDs: Set<ObjectID>
    let transform: SelectionTransform
    let center: CanvasPoint
    let strokeReplacements: [Stroke]
}

extension AppModel {
    func addStroke(_ stroke: Stroke, to notebookID: NotebookID, canvasID: CanvasID, layerID: LayerID) {
        guard var notebook = library.notebook(id: notebookID) else { return }
        var history = histories[notebookID, default: DocumentHistory()]
        let operation = DocumentOperation.addStroke(canvasID: canvasID, layerID: layerID, stroke: stroke)
        do {
            try history.execute(operation, on: &notebook)
            let handwritingCanvasID = cancelHandwritingRecognition(after: operation)
            notebook.modifiedAt = Date()
            histories[notebookID] = history
            library.updateNotebook(notebook)
            if let handwritingCanvasID {
                finishHandwritingChange(after: operation, canvasID: handwritingCanvasID, in: notebook)
            }
            persistCheckpoint(notebook)
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func addStrokes(
        _ strokes: [Stroke],
        to notebookID: NotebookID,
        canvasID: CanvasID,
        layerID: LayerID,
        shouldConvertToText: Bool = false
    ) -> Bool {
        guard !strokes.isEmpty else { return false }
        let placements = strokes.map { stroke in
            var storedStroke = stroke
            storedStroke.layerID = layerID
            return ObjectPlacement(layerID: layerID, index: Int.max, object: .stroke(storedStroke))
        }
        execute(.replaceObjects(canvasID: canvasID, before: [], after: placements), on: notebookID)
        return processStoredStrokes(
            strokes,
            in: notebookID,
            canvasID: canvasID,
            layerID: layerID,
            shouldConvertToText: shouldConvertToText
        )
    }

    func processStoredStrokes(
        _ strokes: [Stroke],
        in notebookID: NotebookID,
        canvasID: CanvasID,
        layerID: LayerID,
        shouldConvertToText: Bool
    ) -> Bool {
        guard !strokes.isEmpty else { return false }
        let didSnapShape = snapShapeIfNeeded(
            strokes: strokes,
            layerID: layerID,
            notebookID: notebookID,
            canvasID: canvasID
        )
        if shouldConvertToText {
            scheduleWritingGroupConversion(
                Set(strokes.map(\.id)),
                notebookID: notebookID,
                canvasID: canvasID
            )
        }
        return didSnapShape
    }

    func convertStrokesToText(
        _ strokeIDs: Set<StrokeID>,
        in notebookID: NotebookID,
        canvasID: CanvasID
    ) {
        guard !strokeIDs.isEmpty,
              let notebook = library.notebook(id: notebookID),
              let canvas = notebook.canvases.first(where: { $0.id == canvasID }) else { return }
        let strokes = canvas.layers.flatMap(\.objects).compactMap(\.strokeValue).filter { strokeIDs.contains($0.id) }
        guard !strokes.isEmpty else { return }
        Task { [weak self] in
            guard let self,
                  let result = await recognitionCoordinator.recognizeSafely(strokes: strokes),
                  let currentNotebook = library.notebook(id: notebookID),
                  let currentCanvas = currentNotebook.canvases.first(where: { $0.id == canvasID }) else { return }
            let currentStrokes = currentCanvas.layers
                .flatMap(\.objects)
                .compactMap(\.strokeValue)
                .filter { strokeIDs.contains($0.id) }
            guard currentStrokes == strokes else { return }
            let textBlock = HandwritingTextLayout().textBlock(from: [result], layerID: strokes[0].layerID)
            do {
                let operation = try DocumentOperation.convertStrokesToText(
                    in: currentNotebook,
                    canvasID: canvasID,
                    strokeIDs: strokeIDs,
                    textBlock: textBlock
                )
                execute(operation, on: notebookID)
            } catch {
                presentedError = error.localizedDescription
            }
        }
    }

    private func scheduleWritingGroupConversion(
        _ strokeIDs: Set<StrokeID>,
        notebookID: NotebookID,
        canvasID: CanvasID
    ) {
        pendingConversionStrokeIDs[canvasID, default: []].formUnion(strokeIDs)
        conversionTasks[canvasID]?.cancel()
        conversionTasks[canvasID] = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: conversionDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            let pendingIDs = pendingConversionStrokeIDs.removeValue(forKey: canvasID) ?? []
            convertStrokesToText(pendingIDs, in: notebookID, canvasID: canvasID)
        }
    }

    func transformObjects(
        _ request: CanvasObjectTransformRequest,
        notebookID: NotebookID,
        canvasID: CanvasID
    ) {
        guard let notebook = library.notebook(id: notebookID),
              let operation = try? DocumentOperation.transformObjects(
                  in: notebook,
                  canvasID: canvasID,
                  objectIDs: request.objectIDs,
                  transform: request.transform,
                  center: request.center,
                  strokeReplacements: request.strokeReplacements
              ) else { return }
        execute(operation, on: notebookID)
    }

    func deleteObjects(_ objectIDs: Set<ObjectID>, notebookID: NotebookID, canvasID: CanvasID) {
        guard let notebook = library.notebook(id: notebookID),
              let operation = try? DocumentOperation.deleteObjects(
                  in: notebook,
                  canvasID: canvasID,
                  objectIDs: objectIDs
              ) else { return }
        execute(operation, on: notebookID)
    }

    func pasteObjects(
        _ objects: [CanvasObject],
        notebookID: NotebookID,
        canvasID: CanvasID,
        layerID: LayerID
    ) {
        let placements = objects.map { object in
            ObjectPlacement(layerID: layerID, index: Int.max, object: object.moved(to: layerID))
        }
        execute(.replaceObjects(canvasID: canvasID, before: [], after: placements), on: notebookID)
    }

    func moveObjects(
        _ objectIDs: Set<ObjectID>,
        to layerID: LayerID,
        notebookID: NotebookID,
        canvasID: CanvasID
    ) {
        guard let notebook = library.notebook(id: notebookID),
              let canvas = notebook.canvases.first(where: { $0.id == canvasID }) else { return }
        let replacements = canvas.layers.flatMap(\.objects)
            .filter { objectIDs.contains($0.id) }
            .map { $0.moved(to: layerID) }
        guard let operation = try? DocumentOperation.replacingObjects(
            in: notebook,
            canvasID: canvasID,
            objectIDs: objectIDs,
            with: replacements
        ) else { return }
        execute(operation, on: notebookID)
    }

    func replaceVisibleStrokes(
        _ strokes: [Stroke],
        in notebookID: NotebookID,
        canvasID: CanvasID,
        layerID: LayerID
    ) {
        guard let notebook = library.notebook(id: notebookID),
              let canvas = notebook.canvases.first(where: { $0.id == canvasID }),
              let activeLayer = canvas.layers.first(where: { $0.id == layerID }) else { return }
        let activeStrokeIDs = Set(activeLayer.objects.compactMap(\.strokeValue).map(\.objectID))
        let activeStrokes = strokes.filter { $0.layerID == layerID }
        guard activeLayer.objects.compactMap(\.strokeValue) != activeStrokes else { return }
        guard let operation = try? DocumentOperation.replacingObjects(
            in: notebook,
            canvasID: canvasID,
            objectIDs: activeStrokeIDs,
            with: activeStrokes.map(CanvasObject.stroke)
        ) else { return }
        execute(operation, on: notebookID)
    }

    func applyVisibleStrokeEdit(
        _ edit: CanvasStrokeEdit,
        in notebookID: NotebookID,
        canvasID: CanvasID
    ) {
        guard let notebook = library.notebook(id: notebookID),
              let canvas = notebook.canvases.first(where: { $0.id == canvasID }) else { return }
        let visibleLayers = canvas.layers.filter(\.isVisible)
        let currentStrokes = visibleLayers.flatMap(\.objects).compactMap(\.strokeValue)
        let editedStrokes = edit.applying(to: currentStrokes)
        guard currentStrokes != editedStrokes else { return }
        let replacement = VisibleStrokeReplacement(
            visibleLayers: visibleLayers,
            currentStrokes: currentStrokes,
            editedStrokes: editedStrokes
        )
        guard !replacement.before.isEmpty || !replacement.after.isEmpty else { return }
        execute(
            .replaceObjects(canvasID: canvasID, before: replacement.before, after: replacement.after),
            on: notebookID
        )
    }

    func addTextBlock(_ insertion: TextBlockInsertion, notebookID: NotebookID) {
        let textBlock = TextBlock(
            id: ObjectID(),
            layerID: insertion.layerID,
            text: insertion.text,
            frame: insertion.frame,
            fontSize: insertion.fontSize,
            alignment: insertion.alignment,
            fontName: insertion.fontName
        )
        let placement = ObjectPlacement(
            layerID: insertion.layerID,
            index: Int.max,
            object: .text(textBlock)
        )
        execute(
            .replaceObjects(canvasID: insertion.canvasID, before: [], after: [placement]),
            on: notebookID
        )
    }

    func addShape(_ insertion: ShapeInsertion, notebookID: NotebookID) {
        let shape = ShapeFactory.make(
            insertion.kind,
            centeredAt: insertion.point,
            layerID: insertion.layerID,
            style: insertion.style
        )
        let placement = ObjectPlacement(
            layerID: insertion.layerID,
            index: Int.max,
            object: .shape(shape)
        )
        execute(
            .replaceObjects(canvasID: insertion.canvasID, before: [], after: [placement]),
            on: notebookID
        )
    }

    func updateTextBlock(_ textBlock: TextBlock, canvasID: CanvasID, notebookID: NotebookID) {
        guard let notebook = library.notebook(id: notebookID),
              let operation = try? DocumentOperation.replacingObjects(
                  in: notebook,
                  canvasID: canvasID,
                  objectIDs: [textBlock.id],
                  with: [.text(textBlock)]
              ) else { return }
        execute(operation, on: notebookID)
    }

    func undo(_ notebookID: NotebookID) {
        guard var notebook = library.notebook(id: notebookID), var history = histories[notebookID] else { return }
        do {
            let operation = try history.undo(on: &notebook)
            let handwritingCanvasID = cancelHandwritingRecognition(after: operation)
            notebook.modifiedAt = Date()
            histories[notebookID] = history
            library.updateNotebook(notebook)
            if let handwritingCanvasID {
                finishHandwritingChange(after: operation, canvasID: handwritingCanvasID, in: notebook)
            } else {
                updateSearchIndex(after: operation, in: notebook)
            }
            persistCheckpoint(notebook)
            enqueueForSync(SyncedDocumentAction(operation: operation, direction: .undo), notebookID: notebookID)
        } catch DocumentHistoryError.nothingToUndo {
            return
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func redo(_ notebookID: NotebookID) {
        guard var notebook = library.notebook(id: notebookID), var history = histories[notebookID] else { return }
        do {
            let operation = try history.redo(on: &notebook)
            let handwritingCanvasID = cancelHandwritingRecognition(after: operation)
            notebook.modifiedAt = Date()
            histories[notebookID] = history
            library.updateNotebook(notebook)
            if let handwritingCanvasID {
                finishHandwritingChange(after: operation, canvasID: handwritingCanvasID, in: notebook)
            } else {
                updateSearchIndex(after: operation, in: notebook)
            }
            persistCheckpoint(notebook)
            enqueueForSync(SyncedDocumentAction(operation: operation, direction: .apply), notebookID: notebookID)
        } catch DocumentHistoryError.nothingToRedo {
            return
        } catch {
            presentedError = error.localizedDescription
        }
    }

    private func snapShapeIfNeeded(
        strokes: [Stroke],
        layerID: LayerID,
        notebookID: NotebookID,
        canvasID: CanvasID
    ) -> Bool {
        guard strokes.count == 1, var stroke = strokes.first else { return false }
        stroke.layerID = layerID
        guard let shape = ShapeRecognizer().recognize(stroke, holdDuration: stroke.terminalHoldDuration),
              let notebook = library.notebook(id: notebookID),
              let operation = try? DocumentOperation.snapStrokeToShape(
                  canvasID: canvasID,
                  strokeID: stroke.id,
                  shape: shape,
                  in: notebook
              ) else { return false }
        execute(operation, on: notebookID)
        return true
    }
}

private struct VisibleStrokeReplacement {
    let before: [ObjectPlacement]
    let after: [ObjectPlacement]

    init(visibleLayers: [Layer], currentStrokes: [Stroke], editedStrokes: [Stroke]) {
        let currentGroups = Self.groups(currentStrokes)
        let editedGroups = Self.groups(editedStrokes)
        let allGroupIDs = Set(currentGroups.keys).union(editedGroups.keys)
        let changedGroupIDs = Set(allGroupIDs.filter { currentGroups[$0] != editedGroups[$0] })
        before = visibleLayers.flatMap { layer in
            layer.objects.enumerated().compactMap { index, object in
                guard let stroke = object.strokeValue,
                      changedGroupIDs.contains(StrokeGroupID(stroke)) else { return nil }
                return ObjectPlacement(layerID: layer.id, index: index, object: object)
            }
        }
        after = visibleLayers.flatMap { layer in
            Self.afterPlacements(
                in: layer,
                editedStrokes: editedStrokes.filter { $0.layerID == layer.id },
                changedGroupIDs: changedGroupIDs
            )
        }
    }

    private static func groups(_ strokes: [Stroke]) -> [StrokeGroupID: [Stroke]] {
        Dictionary(grouping: strokes, by: StrokeGroupID.init)
    }

    private static func afterPlacements(
        in layer: Layer,
        editedStrokes: [Stroke],
        changedGroupIDs: Set<StrokeGroupID>
    ) -> [ObjectPlacement] {
        let currentEntries = StrokeOccurrenceMatcher.indexed(layer.objects.compactMap(\.strokeValue))
        let editedEntries = StrokeOccurrenceMatcher.indexed(editedStrokes, matching: currentEntries)
        var currentEntryIndex = 0
        var layout = layer.objects.map { object -> StrokeLayoutItem in
            guard object.strokeValue != nil else { return .object(object, nil) }
            let entry = currentEntries[currentEntryIndex]
            currentEntryIndex += 1
            return changedGroupIDs.contains(StrokeGroupID(entry.stroke))
                ? .placeholder(entry.occurrence)
                : .object(object, entry.occurrence)
        }
        for (index, entry) in editedEntries.enumerated()
            where changedGroupIDs.contains(StrokeGroupID(entry.stroke)) {
            let item = StrokeLayoutItem.object(.stroke(entry.stroke), entry.occurrence)
            if let placeholderIndex = layout.firstIndex(where: { $0.placeholderKey == entry.occurrence }) {
                layout[placeholderIndex] = item
            } else {
                insert(item, from: editedEntries, at: index, into: &layout)
            }
        }
        layout.removeAll { $0.placeholderKey != nil }
        return layout.enumerated().compactMap { index, item in
            guard let object = item.object,
                  let stroke = object.strokeValue,
                  changedGroupIDs.contains(StrokeGroupID(stroke)) else { return nil }
            return ObjectPlacement(layerID: layer.id, index: index, object: object)
        }
    }

    private static func insert(
        _ item: StrokeLayoutItem,
        from editedEntries: [OccurrenceIndexedStroke],
        at editedIndex: Int,
        into layout: inout [StrokeLayoutItem]
    ) {
        let precedingKeys = Array(editedEntries[..<editedIndex].map(\.occurrence).reversed())
        if let anchorIndex = anchorIndex(for: precedingKeys, in: layout) {
            layout.insert(item, at: anchorIndex + 1)
            return
        }
        let followingKeys = Array(editedEntries[editedEntries.index(after: editedIndex)...].map(\.occurrence))
        if let anchorIndex = anchorIndex(for: followingKeys, in: layout) {
            layout.insert(item, at: anchorIndex)
            return
        }
        layout.append(item)
    }

    private static func anchorIndex(
        for candidates: [StrokeOccurrence],
        in layout: [StrokeLayoutItem]
    ) -> Int? {
        for candidate in candidates {
            if let index = layout.firstIndex(where: { $0.strokeKey == candidate }) { return index }
        }
        return nil
    }
}

private struct StrokeGroupID: Hashable {
    let strokeID: StrokeID
    let layerID: LayerID

    init(_ stroke: Stroke) {
        strokeID = stroke.id
        layerID = stroke.layerID
    }
}

private enum StrokeLayoutItem {
    case object(CanvasObject, StrokeOccurrence?)
    case placeholder(StrokeOccurrence)

    var object: CanvasObject? {
        guard case let .object(object, _) = self else { return nil }
        return object
    }

    var strokeKey: StrokeOccurrence? {
        guard case let .object(_, key) = self else { return nil }
        return key
    }

    var placeholderKey: StrokeOccurrence? {
        guard case let .placeholder(key) = self else { return nil }
        return key
    }
}
