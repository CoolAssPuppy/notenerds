import Foundation

extension AppModel {
    func scheduleRecognition(notebookID: NotebookID, canvasID: CanvasID) {
        pendingRecognitionBackfill[notebookID]?.remove(canvasID)
        if pendingRecognitionBackfill[notebookID]?.isEmpty == true {
            pendingRecognitionBackfill[notebookID] = nil
        }
        recognitionTasks[canvasID]?.cancel()
        recognitionTasks[canvasID] = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(700))
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  await recognizeHandwriting(notebookID: notebookID, canvasID: canvasID),
                  let notebook = library.notebook(id: notebookID) else { return }
            persistCheckpoint(notebook)
        }
    }

    private func recognizeHandwriting(notebookID: NotebookID, canvasID: CanvasID) async -> Bool {
        guard let sourceNotebook = library.notebook(id: notebookID),
              sourceNotebook.trashedAt == nil,
              let sourceCanvas = sourceNotebook.canvases.first(where: { $0.id == canvasID }) else { return false }
        let sourceStrokes = sourceCanvas.visibleHandwritingStrokes
        let groups = HandwritingGroupBuilder().groups(from: sourceStrokes)
        var records: [PersistedHandwritingRecognition] = []
        for group in groups where !Task.isCancelled {
            if let result = await recognitionCoordinator.recognizeSafely(strokes: group) {
                records.append(PersistedHandwritingRecognition(result: result, sourceStrokes: group))
            }
        }
        guard !Task.isCancelled,
              var latestNotebook = library.notebook(id: notebookID),
              latestNotebook.trashedAt == nil,
              let latestCanvas = latestNotebook.canvases.first(where: { $0.id == canvasID }),
              latestCanvas.visibleHandwritingStrokes == sourceStrokes else { return false }
        latestNotebook.recognitionByCanvas[canvasID] = records
        library.updateNotebook(latestNotebook)
        searchIndex.updateHandwriting(canvasID: canvasID, in: latestNotebook)
        return true
    }

    func cancelHandwritingRecognition(after operation: DocumentOperation) -> CanvasID? {
        guard operation.changesHandwritingRecognition,
              let canvasID = operation.handwritingRecognitionCanvasID else { return nil }
        recognitionTasks[canvasID]?.cancel()
        return canvasID
    }

    func finishHandwritingChange(
        after operation: DocumentOperation,
        canvasID: CanvasID,
        in notebook: Notebook
    ) {
        if operation.requiresSearchIndexUpdate {
            updateSearchIndex(after: operation, in: notebook)
        } else {
            searchIndex.removeHandwriting(canvasID: canvasID, notebookID: notebook.id)
        }
        guard let canvas = notebook.canvases.first(where: { $0.id == canvasID }),
              canvas.hasVisibleHandwriting else { return }
        scheduleRecognition(notebookID: notebook.id, canvasID: canvasID)
    }

    func restoreHandwritingSearch() {
        for notebook in library.notebooks where notebook.trashedAt == nil {
            refreshHandwritingSearch(in: notebook.id)
        }
    }

    func refreshHandwritingSearch(in notebookID: NotebookID) {
        guard let storedNotebook = library.notebook(id: notebookID),
              storedNotebook.trashedAt == nil else { return }
        var notebook = storedNotebook
        let canvasIDs = Set(notebook.canvases.map(\.id))
        for orphanedID in notebook.recognitionByCanvas.keys where !canvasIDs.contains(orphanedID) {
            notebook.recognitionByCanvas[orphanedID] = nil
        }
        for canvas in notebook.canvases {
            removeStaleRecognition(
                from: canvas,
                recognizerVersion: recognitionCoordinator.recognizerVersion,
                in: &notebook
            )
        }
        if notebook != storedNotebook {
            library.updateNotebook(notebook)
        }
        searchIndex.update(notebook)
        scheduleMissingHandwritingRecognition(in: notebook)
    }

    func scheduleMissingHandwritingRecognition(in notebook: Notebook) {
        guard notebook.trashedAt == nil else { return }
        let missingCanvasIDs = notebook.canvases.compactMap { canvas -> CanvasID? in
            guard notebook.recognitionByCanvas[canvas.id] == nil,
                  !canvas.visibleHandwritingStrokes.isEmpty else { return nil }
            return canvas.id
        }
        guard !missingCanvasIDs.isEmpty else { return }
        pendingRecognitionBackfill[notebook.id, default: []].formUnion(missingCanvasIDs)
        startRecognitionBackfillIfNeeded()
    }

    private func startRecognitionBackfillIfNeeded() {
        guard recognitionBackfillTask == nil else { return }
        recognitionBackfillTask = Task { [weak self] in
            await self?.runRecognitionBackfill()
        }
    }

    private func runRecognitionBackfill() async {
        while let notebookID = pendingRecognitionBackfill.keys.first,
              let canvasIDs = pendingRecognitionBackfill.removeValue(forKey: notebookID) {
            var didRecognizeNotebook = false
            for canvasID in canvasIDs.sorted(by: { $0.rawValue.uuidString < $1.rawValue.uuidString }) {
                let didRecognize = await recognizeHandwriting(notebookID: notebookID, canvasID: canvasID)
                didRecognizeNotebook = didRecognize || didRecognizeNotebook
            }
            if didRecognizeNotebook, let notebook = library.notebook(id: notebookID) {
                persistCheckpoint(notebook)
            }
        }
        recognitionBackfillTask = nil
    }

    private func removeStaleRecognition(
        from canvas: Canvas,
        recognizerVersion: String,
        in notebook: inout Notebook
    ) {
        guard let records = notebook.recognitionByCanvas[canvas.id] else { return }
        let visibleStrokes = canvas.visibleHandwritingStrokes
        let visibleStrokesByID = Dictionary(
            grouping: visibleStrokes,
            by: \.id
        )
        let recognizedStrokeIDs = records.reduce(into: Set<StrokeID>()) { identifiers, record in
            identifiers.formUnion(record.sourceStrokeIDs)
        }
        let isStale = records.isEmpty
            || recognizedStrokeIDs != Set(visibleStrokes.map(\.id))
            || records.contains(where: { record in
                  let sourceIDs = record.sourceStrokeIDs
                  let sourceStrokes = sourceIDs.flatMap { visibleStrokesByID[$0] ?? [] }
                  return sourceStrokes.count != sourceIDs.count
                      || record.isStale(
                          sourceStrokes: sourceStrokes,
                          recognizerVersion: recognizerVersion
                      )
              })
        guard isStale else { return }
        notebook.recognitionByCanvas[canvas.id] = nil
    }
}

extension DocumentOperation {
    var changesHandwritingRecognition: Bool {
        switch self {
        case .addStroke, .convertStrokesToText, .deleteCanvas:
            true
        case let .deleteObjects(_, objects):
            objects.contains(where: \.object.isStroke)
        case let .replaceObjects(_, before, after):
            (before + after).contains(where: \.object.isStroke)
        case let .insertCanvas(canvas, _):
            canvas.layers.contains(where: \.containsStroke)
        case let .insertLayer(_, layer, _):
            layer.containsStroke
        case let .deleteLayer(placement):
            placement.layer.containsStroke
        case let .updateLayer(_, before, after):
            before.containsStroke || after.containsStroke
        case .moveCanvas, .renameCanvas, .changeTemplate:
            false
        case .moveLayer:
            true
        }
    }

    var handwritingRecognitionCanvasID: CanvasID? {
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
        case let .insertCanvas(canvas, _): canvas.id
        case let .deleteCanvas(placement): placement.canvas.id
        case let .deleteLayer(placement): placement.canvasID
        case .moveCanvas, .renameCanvas: nil
        }
    }
}

private extension Canvas {
    var hasVisibleHandwriting: Bool {
        layers.lazy.filter(\.isVisible).contains { layer in
            layer.objects.contains { object in
                guard let stroke = object.strokeValue else { return false }
                return stroke.isHandwritingRecognitionCandidate
            }
        }
    }

    var visibleHandwritingStrokes: [Stroke] {
        layers
            .filter(\.isVisible)
            .flatMap(\.objects)
            .compactMap(\.strokeValue)
            .filter(\.isHandwritingRecognitionCandidate)
    }
}

private extension Layer {
    var containsStroke: Bool { objects.contains(where: \.isStroke) }
}

private extension CanvasObject {
    var isStroke: Bool {
        if case .stroke = self { return true }
        return false
    }
}
