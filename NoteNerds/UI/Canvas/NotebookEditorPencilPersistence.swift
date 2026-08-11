import UIKit

struct NotebookEditorPencilPersistenceCallbacks {
    let onStrokesCompleted: @MainActor ([CompletedPencilStroke]) -> Void
    let onDrawingChanged: @MainActor (CanvasStrokeEdit, [CompletedPencilStroke]) -> Void
}

private struct CompletedPencilStrokeGroup {
    let layerID: LayerID
    let shouldConvertToText: Bool
    var strokes: [Stroke]

    func matches(_ completed: CompletedPencilStroke) -> Bool {
        layerID == completed.stroke.layerID
            && shouldConvertToText == completed.shouldConvertToText
    }
}

extension NotebookEditorView {
    func pencilPersistenceCallbacks(
        for targetCanvasID: CanvasID
    ) -> NotebookEditorPencilPersistenceCallbacks {
        NotebookEditorPencilPersistenceCallbacks(
            onStrokesCompleted: { completedStrokes in
                var didSnapShape = false
                for group in completedStrokeGroups(completedStrokes, canvasID: targetCanvasID) {
                    didSnapShape = model.addStrokes(
                        group.strokes,
                        to: notebook.id,
                        canvasID: targetCanvasID,
                        layerID: group.layerID,
                        shouldConvertToText: group.shouldConvertToText
                    ) || didSnapShape
                }
                if didSnapShape { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            },
            onDrawingChanged: { edit, completedStrokes in
                model.applyVisibleStrokeEdit(
                    CanvasStrokeEdit(
                        before: edit.before,
                        after: constrainStrokesToPlannerRegions(
                            edit.after,
                            canvasID: targetCanvasID
                        )
                    ),
                    in: notebook.id,
                    canvasID: targetCanvasID
                )
                var didSnapShape = false
                for group in completedStrokeGroups(completedStrokes, canvasID: targetCanvasID) {
                    didSnapShape = model.processStoredStrokes(
                        group.strokes,
                        in: notebook.id,
                        canvasID: targetCanvasID,
                        layerID: group.layerID,
                        shouldConvertToText: group.shouldConvertToText
                    ) || didSnapShape
                }
                if didSnapShape { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            }
        )
    }
}

private extension NotebookEditorView {
    func completedStrokeGroups(
        _ completedStrokes: [CompletedPencilStroke],
        canvasID: CanvasID
    ) -> [CompletedPencilStrokeGroup] {
        var groups: [CompletedPencilStrokeGroup] = []
        for completed in completedStrokes {
            guard let stroke = constrainStrokesToPlannerRegions(
                [completed.stroke],
                canvasID: canvasID
            ).first else { continue }
            if groups.last?.matches(completed) == true {
                groups[groups.count - 1].strokes.append(stroke)
            } else {
                groups.append(CompletedPencilStrokeGroup(
                    layerID: stroke.layerID,
                    shouldConvertToText: completed.shouldConvertToText,
                    strokes: [stroke]
                ))
            }
        }
        return groups
    }
}
