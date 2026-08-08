import Foundation

extension AppModel {
    func scheduleRecognition(notebookID: NotebookID, canvasID: CanvasID) {
        recognitionTasks[canvasID]?.cancel()
        recognitionTasks[canvasID] = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(700))
            } catch {
                return
            }
            guard let self,
                  !Task.isCancelled,
                  var notebook = library.notebook(id: notebookID),
                  let canvas = notebook.canvases.first(where: { $0.id == canvasID }) else { return }
            let strokes = canvas.layers.filter(\.isVisible).flatMap(\.objects).compactMap(\.strokeValue)
            let groups = HandwritingGroupBuilder().groups(from: strokes)
            var records: [PersistedHandwritingRecognition] = []
            for group in groups where !Task.isCancelled {
                if let result = await recognitionCoordinator.recognizeSafely(strokes: group) {
                    records.append(PersistedHandwritingRecognition(result: result, sourceStrokes: group))
                }
            }
            guard !Task.isCancelled else { return }
            notebook.recognitionByCanvas[canvasID] = records
            library.updateNotebook(notebook)
            searchIndex.update(canvasID: canvasID, in: notebook)
            persistCheckpoint(notebook)
        }
    }
}
