import Foundation

extension NotebookEditorView {
    var currentCanvas: Canvas {
        notebook.canvases[min(canvasIndex, notebook.canvases.count - 1)]
    }

    var activeLayer: Layer {
        currentCanvas.layers.last(where: \.isVisible) ?? currentCanvas.layers.last ?? Layer(name: "Layer 1")
    }

    var currentStrokes: [Stroke] {
        currentCanvas.layers.filter(\.isVisible).flatMap(\.objects).compactMap(\.strokeValue)
    }

    var currentNonStrokeObjects: [CanvasObject] {
        currentCanvas.layers.filter(\.isVisible).flatMap(\.objects).filter { $0.strokeValue == nil }
    }

    var currentAssets: [AssetID: Data] {
        let assetIDs = currentNonStrokeObjects.compactMap { object -> AssetID? in
            switch object {
            case let .image(image): image.assetID
            case let .pdf(pdf): pdf.assetID
            case .stroke, .shape, .text: nil
            }
        }
        return Dictionary(uniqueKeysWithValues: assetIDs.compactMap { id in
            model.asset(id).map { (id, $0.data) }
        })
    }

    var configuration: ToolConfiguration { palette.current }

    var shapeStyle: StrokeStyle {
        StrokeStyle(
            instrument: selectedDrawingTool.instrument ?? .ballpoint,
            width: configuration.width.points,
            color: configuration.color
        )
    }

    var currentRecognizedText: [String] {
        notebook.recognitionByCanvas[currentCanvas.id, default: []].map(\.result.text)
    }

    func changeTemplate(_ template: CanvasTemplate) {
        model.changeTemplate(template, notebookID: notebook.id, canvasID: currentCanvas.id)
    }

    func addLayer() {
        model.addLayer(to: currentCanvas.id, in: notebook.id)
    }

    func activateTextTool() {
        selectedShapeKind = nil
        isTextToolActive = true
    }

    func activateShapeTool(_ kind: RecognizedShapeKind) {
        isTextToolActive = false
        selectedShapeKind = kind
    }

    func placeShape(at point: CanvasPoint) {
        guard let selectedShapeKind else { return }
        model.addShape(
            ShapeInsertion(
                kind: selectedShapeKind,
                point: point,
                style: shapeStyle,
                layerID: activeLayer.id,
                canvasID: currentCanvas.id
            ),
            notebookID: notebook.id
        )
    }
}
