import PencilKit
import UIKit
@testable import NoteNerds

@MainActor
enum PencilStrokeTestFixture {
    static func coordinator(
        onStrokesCompleted: @escaping @MainActor ([Stroke]) -> Void,
        onDrawingChanged: @escaping @MainActor ([Stroke]) -> Void = { _ in }
    ) -> PencilCanvasView.Coordinator {
        PencilCanvasView.Coordinator(
            activeLayerID: LayerID(),
            onStrokesCompleted: onStrokesCompleted,
            onDrawingChanged: onDrawingChanged,
            onConvertStrokesToText: { _ in },
            onViewportChanged: { _ in },
            onPencilSqueeze: { _, _ in },
            onPencilDoubleTap: {},
            onPlannerRegionPageRequested: { _ in }
        )
    }

    static func capture(
        _ pencilStrokes: [PKStroke],
        configurations: [ToolConfiguration]
    ) -> [Stroke] {
        let canvasView = PKCanvasView()
        var completedStrokes: [Stroke] = []
        let coordinator = coordinator { completedStrokes.append(contentsOf: $0) }
        for (index, pencilStroke) in pencilStrokes.enumerated() {
            coordinator.configuration = configurations[index]
            coordinator.canvasViewDidBeginUsingTool(canvasView)
            canvasView.drawing = PKDrawing(
                strokes: Array(pencilStrokes.prefix(index)) + [pencilStroke]
            )
            coordinator.canvasViewDidEndUsingTool(canvasView)
        }
        return completedStrokes
    }

    static func markerHighlightMarkerSequence() -> (
        configurations: [ToolConfiguration],
        pencilStrokes: [PKStroke]
    ) {
        let purple = InkColor(red: 0.55, green: 0.16, blue: 0.82, alpha: 1)
        let yellow = InkColor(red: 0.95, green: 0.78, blue: 0.2, alpha: 0.45)
        return (
            configurations: [
                ToolConfiguration(tool: .marker, width: .medium, color: purple),
                ToolConfiguration(tool: .highlighter, width: .thick, color: yellow),
                ToolConfiguration(tool: .marker, width: .medium, color: .black)
            ],
            pencilStrokes: [
                transformedMarker(
                    color: purple,
                    size: CGSize(width: 5, height: 8),
                    opacity: 0.92,
                    seed: 11,
                    scale: 0.28
                ),
                transformedMarker(
                    color: yellow,
                    size: CGSize(width: 13, height: 7),
                    opacity: 0.38,
                    seed: 22,
                    scale: 0.42
                ),
                transformedMarker(
                    color: .black,
                    size: CGSize(width: 4, height: 6),
                    opacity: 0.86,
                    seed: 33,
                    scale: 0.31
                )
            ]
        )
    }

    static func pencilStroke(
        inkType: PKInk.InkType = .marker,
        color: InkColor,
        size: CGSize,
        opacity: CGFloat,
        randomSeed: UInt32,
        transform: CGAffineTransform = .identity
    ) -> PKStroke {
        let points = (0..<8).map { index in
            let scalar = CGFloat(index)
            return PKStrokePoint(
                location: CGPoint(x: 100 + scalar * 9, y: 200 + scalar * 5),
                timeOffset: Double(index) * 0.01,
                size: size,
                opacity: opacity,
                force: 0.35 + scalar * 0.05,
                azimuth: 1.1,
                altitude: 0.7,
                secondaryScale: 0.75 + scalar * 0.02
            )
        }
        var stroke = PKStroke(
            ink: PKInk(inkType, color: UIColor(color)),
            path: PKStrokePath(controlPoints: points, creationDate: DomainFixtures.fixedDate),
            randomSeed: randomSeed
        )
        stroke.transform = transform
        return stroke
    }

    static func roundTrippedStrokes(in notebook: Notebook) throws -> [Stroke] {
        let package = NativeNotebookPackage(schemaVersion: .current, notebook: notebook)
        let serializer = NativeDocumentSerializer()
        let reopened = try serializer.decode(serializer.encode(package))
        return reopened.notebook.canvases[0].layers[0].objects.compactMap(\.strokeValue)
    }

    private static func transformedMarker(
        color: InkColor,
        size: CGSize,
        opacity: CGFloat,
        seed: UInt32,
        scale: CGFloat
    ) -> PKStroke {
        pencilStroke(
            color: color,
            size: size,
            opacity: opacity,
            randomSeed: seed,
            transform: CGAffineTransform(
                a: scale,
                b: 0,
                c: 0,
                d: scale,
                tx: 200 - 100 * scale,
                ty: 300 - 200 * scale
            )
        )
    }
}
