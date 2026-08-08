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

    var currentRecognizedText: [String] {
        notebook.recognitionByCanvas[currentCanvas.id, default: []].map(\.result.text)
    }
}
