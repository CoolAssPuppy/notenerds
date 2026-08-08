import UIKit

extension NotebookEditorView {
    func selectLayer(_ layerID: LayerID) {
        guard currentCanvas.layers.contains(where: { $0.id == layerID }) else { return }
        selectedLayerIDs[currentCanvas.id] = layerID
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func toggleLayer(_ layer: Layer) {
        model.setLayerVisibility(
            layer.id,
            isVisible: !layer.isVisible,
            canvasID: currentCanvas.id,
            notebookID: notebook.id
        )
    }

    func deleteLayer(_ layer: Layer) {
        let nextLayerID = LayerStackPresentation(
            layers: currentCanvas.layers,
            selectedLayerID: activeLayer.id
        ).activeLayerID(afterDeleting: layer.id)
        model.deleteLayer(layer.id, from: currentCanvas.id, in: notebook.id)
        if selectedLayerIDs[currentCanvas.id] == layer.id || activeLayer.id == layer.id {
            selectedLayerIDs[currentCanvas.id] = nextLayerID
        }
    }

    func renameLayer(_ layer: Layer, to name: String) {
        model.renameLayer(layer.id, to: name, canvasID: currentCanvas.id, notebookID: notebook.id)
    }

    func moveLayer(_ move: LayerStackMove) {
        model.moveLayer(
            from: move.sourceIndex,
            to: move.destinationIndex,
            canvasID: currentCanvas.id,
            notebookID: notebook.id
        )
    }
}
