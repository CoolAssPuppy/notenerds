import Foundation
import UIKit

extension NotebookEditorView {
    var toolbarOrientation: CanvasToolbarOrientation {
        CanvasToolbarOrientation(rawValue: toolbarOrientationRawValue) ?? .vertical
    }

    var selectedDrawingTool: CanvasTool {
        configuration.tool.instrument == nil ? previousDrawingTool : configuration.tool
    }

    var currentCanvas: Canvas {
        notebook.canvases[min(canvasIndex, notebook.canvases.count - 1)]
    }

    var activeLayer: Layer {
        let selectedID = LayerStackPresentation(
            layers: currentCanvas.layers,
            selectedLayerID: selectedLayerIDs[currentCanvas.id]
        ).activeLayerID
        return currentCanvas.layers.first(where: { $0.id == selectedID })
            ?? currentCanvas.layers.last
            ?? Layer(name: "Layer 1")
    }

    var currentStrokes: [Stroke] {
        currentCanvas.layers.filter(\.isVisible).flatMap(\.objects).compactMap(\.strokeValue)
    }

    var currentNonStrokeObjects: [CanvasObject] {
        currentCanvas.layers.filter(\.isVisible).flatMap(\.objects).filter { $0.strokeValue == nil }
    }

    var currentAssets: [AssetID: Data] {
        let assetIDs = Set(currentNonStrokeObjects.compactMap { object -> AssetID? in
            switch object {
            case let .image(image): image.assetID
            case let .pdf(pdf): pdf.assetID
            case .stroke, .shape, .text: nil
            }
        })
        return assetIDs.reduce(into: [:]) { assets, id in
            assets[id] = model.asset(id)?.data
        }
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
        let presentation = LayerStackPresentation(
            layers: currentCanvas.layers,
            selectedLayerID: activeLayer.id
        )
        guard let layerID = model.addLayer(
            to: currentCanvas.id,
            in: notebook.id,
            at: presentation.newLayerInsertionIndex
        ) else { return }
        selectedLayerIDs[currentCanvas.id] = layerID
        UISelectionFeedbackGenerator().selectionChanged()
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
