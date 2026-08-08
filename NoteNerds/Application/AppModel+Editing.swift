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

extension AppModel {
    func addStroke(_ stroke: Stroke, to notebookID: NotebookID, canvasID: CanvasID, layerID: LayerID) {
        guard var notebook = library.notebook(id: notebookID) else { return }
        var history = histories[notebookID, default: DocumentHistory()]
        do {
            try history.execute(.addStroke(canvasID: canvasID, layerID: layerID, stroke: stroke), on: &notebook)
            notebook.modifiedAt = Date()
            histories[notebookID] = history
            library.updateNotebook(notebook)
            persistCheckpoint(notebook)
            scheduleRecognition(notebookID: notebookID, canvasID: canvasID)
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
        scheduleRecognition(notebookID: notebookID, canvasID: canvasID)
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
                  let currentNotebook = library.notebook(id: notebookID) else { return }
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
        _ objectIDs: Set<ObjectID>,
        transform: SelectionTransform,
        center: CanvasPoint,
        notebookID: NotebookID,
        canvasID: CanvasID
    ) {
        guard let notebook = library.notebook(id: notebookID),
              let operation = try? DocumentOperation.transformObjects(
                  in: notebook,
                  canvasID: canvasID,
                  objectIDs: objectIDs,
                  transform: transform,
                  center: center
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

    func pasteObjects(_ objects: [CanvasObject], notebookID: NotebookID, canvasID: CanvasID) {
        let placements = objects.map {
            ObjectPlacement(layerID: $0.layerID, index: Int.max, object: $0)
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

    func replaceVisibleStrokes(_ strokes: [Stroke], in notebookID: NotebookID, canvasID: CanvasID) {
        guard let notebook = library.notebook(id: notebookID),
              let canvas = notebook.canvases.first(where: { $0.id == canvasID }) else { return }
        let visibleStrokeIDs = Set(
            canvas.layers.filter(\.isVisible).flatMap(\.objects).compactMap(\.strokeValue).map(\.objectID)
        )
        guard let operation = try? DocumentOperation.replacingObjects(
            in: notebook,
            canvasID: canvasID,
            objectIDs: visibleStrokeIDs,
            with: strokes.map(CanvasObject.stroke)
        ) else { return }
        execute(operation, on: notebookID)
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
            notebook.modifiedAt = Date()
            histories[notebookID] = history
            library.updateNotebook(notebook)
            updateSearchIndex(after: operation, in: notebook)
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
            notebook.modifiedAt = Date()
            histories[notebookID] = history
            library.updateNotebook(notebook)
            updateSearchIndex(after: operation, in: notebook)
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
