import UIKit

extension NotebookEditorView {
    func switchToPreviousTool() {
        isTextToolActive = false
        selectedShapeKind = nil
        let currentTool = configuration.tool
        palette.select(previousCanvasTool)
        previousCanvasTool = currentTool
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func switchDrawingToolAndEraser() {
        isTextToolActive = false
        selectedShapeKind = nil
        if configuration.tool == .eraser {
            palette.select(previousDrawingTool)
        } else {
            if configuration.tool != .lasso { previousDrawingTool = configuration.tool }
            palette.select(.eraser)
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
