extension NotebookEditorView {
    func toggleLayer(_ layer: Layer) {
        model.setLayerVisibility(
            layer.id,
            isVisible: !layer.isVisible,
            canvasID: currentCanvas.id,
            notebookID: notebook.id
        )
    }

    func deleteLayer(_ layer: Layer) {
        model.deleteLayer(layer.id, from: currentCanvas.id, in: notebook.id)
    }

    func renameLayer(_ layer: Layer, to name: String) {
        model.renameLayer(layer.id, to: name, canvasID: currentCanvas.id, notebookID: notebook.id)
    }

    func moveLayer(_ layer: Layer, by offset: Int) {
        guard let source = currentCanvas.layers.firstIndex(where: { $0.id == layer.id }) else { return }
        model.moveLayer(
            from: source,
            to: source + offset,
            canvasID: currentCanvas.id,
            notebookID: notebook.id
        )
    }
}
