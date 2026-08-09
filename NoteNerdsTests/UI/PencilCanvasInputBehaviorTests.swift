import PencilKit
import UIKit
import XCTest
@testable import NoteNerds

@MainActor
final class PencilCanvasInputBehaviorTests: XCTestCase {
    func testModelRefreshWaitsUntilPencilLift() {
        let current = stroke(sampleCount: 4, xOffset: 0)
        let incoming = stroke(sampleCount: 4, xOffset: 200)

        XCTAssertFalse(
            PencilCanvasModelReconciliation.requiresRedraw(
                current: [current],
                incoming: [incoming],
                isUsingTool: true
            )
        )
        XCTAssertTrue(
            PencilCanvasModelReconciliation.requiresRedraw(
                current: [current],
                incoming: [incoming],
                isUsingTool: false
            )
        )
    }

    func testRepeatedPartialUpdatesPublishOneCompleteStrokeAfterPencilLift() {
        let completeStroke = stroke(sampleCount: 12, xOffset: 0)
        let canvasView = PKCanvasView()
        var publishedStrokes: [[Stroke]] = []
        let coordinator = makeCoordinator { publishedStrokes.append($0) }

        coordinator.canvasViewDidBeginUsingTool(canvasView)
        for sampleCount in 1...completeStroke.samples.count {
            var partialStroke = completeStroke
            partialStroke.samples = Array(completeStroke.samples.prefix(sampleCount))
            canvasView.drawing = PencilCanvasRenderer.drawing(from: [partialStroke])
            coordinator.canvasViewDrawingDidChange(canvasView)
        }

        XCTAssertTrue(publishedStrokes.isEmpty)

        coordinator.canvasViewDidEndUsingTool(canvasView)

        XCTAssertEqual(publishedStrokes.count, 1)
        XCTAssertEqual(publishedStrokes[0].count, 1)
        XCTAssertEqual(publishedStrokes[0][0].samples.count, completeStroke.samples.count)
        XCTAssertEqual(publishedStrokes[0][0].samples.map(\.point), completeStroke.samples.map(\.point))
    }

    func testRapidConsecutiveStrokesEachPublishOnceWithCompleteSamples() {
        let firstStroke = stroke(sampleCount: 8, xOffset: 0)
        let secondStroke = stroke(sampleCount: 10, xOffset: 100)
        let canvasView = PKCanvasView()
        var publishedStrokes: [[Stroke]] = []
        let coordinator = makeCoordinator { publishedStrokes.append($0) }

        draw(firstStroke, withExisting: [], on: canvasView, coordinator: coordinator)
        draw(secondStroke, withExisting: [firstStroke], on: canvasView, coordinator: coordinator)

        XCTAssertEqual(publishedStrokes.map(\.count), [1, 1])
        XCTAssertEqual(publishedStrokes[0][0].samples.map(\.point), firstStroke.samples.map(\.point))
        XCTAssertEqual(publishedStrokes[1][0].samples.map(\.point), secondStroke.samples.map(\.point))
        let storedStrokes = publishedStrokes.flatMap { $0 }
        XCTAssertEqual(coordinator.canonicalStrokes, storedStrokes)
        XCTAssertFalse(PencilCanvasModelReconciliation.requiresRedraw(
            current: coordinator.canonicalStrokes,
            incoming: storedStrokes
        ))
    }

    func testMarkerHighlightMarkerRetainsPencilKitRenderingAfterReopen() throws {
        let purple = InkColor(red: 0.55, green: 0.16, blue: 0.82, alpha: 1)
        let yellow = InkColor(red: 0.95, green: 0.78, blue: 0.2, alpha: 0.45)
        let configurations = [
            ToolConfiguration(tool: .marker, width: .medium, color: purple),
            ToolConfiguration(tool: .highlighter, width: .thick, color: yellow),
            ToolConfiguration(tool: .marker, width: .medium, color: .black)
        ]
        let originalStrokes = [
            pencilStroke(color: purple, size: CGSize(width: 5, height: 8), opacity: 0.92),
            pencilStroke(color: yellow, size: CGSize(width: 13, height: 7), opacity: 0.38),
            pencilStroke(color: .black, size: CGSize(width: 4, height: 6), opacity: 0.86)
        ]
        let canvasView = PKCanvasView()
        var completedStrokes: [Stroke] = []
        let coordinator = makeCoordinator { completedStrokes.append(contentsOf: $0) }

        for (index, pencilStroke) in originalStrokes.enumerated() {
            coordinator.configuration = configurations[index]
            coordinator.canvasViewDidBeginUsingTool(canvasView)
            canvasView.drawing = PKDrawing(strokes: Array(originalStrokes.prefix(index)) + [pencilStroke])
            coordinator.canvasViewDidEndUsingTool(canvasView)
        }
        var notebook = DomainFixtures.notebook()
        notebook.canvases[0].layers[0].objects = completedStrokes.map(CanvasObject.stroke)
        let package = NativeNotebookPackage(schemaVersion: .current, notebook: notebook)

        let reopened = try NativeDocumentSerializer().decode(
            NativeDocumentSerializer().encode(package)
        )
        let reopenedStrokes = reopened.notebook.canvases[0].layers[0].objects.compactMap(\.strokeValue)
        let rendered = PencilCanvasRenderer.drawing(from: reopenedStrokes).strokes

        XCTAssertEqual(rendered.count, originalStrokes.count)
        for (original, restored) in zip(originalStrokes, rendered) {
            XCTAssertEqual(restored.path.map(\.size), original.path.map(\.size))
            XCTAssertEqual(restored.path.map(\.opacity), original.path.map(\.opacity))
            XCTAssertEqual(restored.path.map(\.secondaryScale), original.path.map(\.secondaryScale))
            XCTAssertEqual(restored.path.map(\.threshold), original.path.map(\.threshold))
            XCTAssertEqual(restored.renderBounds, original.renderBounds)
        }
    }

    func testExistingStrokeGeometryPublishesOnlyAfterToolUseEnds() {
        let original = stroke(sampleCount: 6, xOffset: 0)
        let moved = stroke(sampleCount: 6, xOffset: 300)
        let canvasView = PKCanvasView()
        canvasView.drawing = PencilCanvasRenderer.drawing(from: [moved])
        var changedStrokes: [[Stroke]] = []
        let coordinator = makeCoordinator(
            onStrokesCompleted: { _ in },
            onDrawingChanged: { changedStrokes.append($0) }
        )
        coordinator.knownStrokeCount = 1
        coordinator.canonicalStrokes = [original]

        coordinator.canvasViewDidBeginUsingTool(canvasView)
        coordinator.canvasViewDrawingDidChange(canvasView)

        XCTAssertTrue(changedStrokes.isEmpty)

        coordinator.canvasViewDidEndUsingTool(canvasView)

        XCTAssertEqual(changedStrokes.count, 1)
        XCTAssertEqual(changedStrokes[0][0].id, original.id)
        XCTAssertEqual(changedStrokes[0][0].samples.map(\.point), moved.samples.map(\.point))
    }

    func testPencilAccessoriesTrackHoverWithoutAddingAVisualTarget() {
        let canvasView = PKCanvasView()
        let existingSubviews = Set(canvasView.subviews.map(ObjectIdentifier.init))
        let coordinator = makeCoordinator { _ in }

        PencilCanvasInputAccessories.install(on: canvasView, coordinator: coordinator)

        let addedSubviews = canvasView.subviews.filter {
            !existingSubviews.contains(ObjectIdentifier($0))
        }
        XCTAssertTrue(addedSubviews.isEmpty)
        XCTAssertTrue(canvasView.interactions.contains { $0 is UIPencilInteraction })
        XCTAssertTrue(canvasView.gestureRecognizers?.contains { $0 is UIHoverGestureRecognizer } == true)
    }

    func testInfiniteCanvasSelectionAndLassoUseVisibleVectorPaths() {
        let parent = CALayer()
        let outlines = CanvasSelectionOutlineLayers()
        outlines.add(to: parent)

        outlines.update(
            selectionBounds: CGRect(x: 9_000, y: 9_000, width: 600, height: 400),
            handlePoints: [CGPoint(x: 9_000, y: 9_000)],
            lassoPoints: [CGPoint(x: 9_100, y: 9_100), CGPoint(x: 9_500, y: 9_400)]
        )

        XCTAssertEqual(parent.sublayers?.count, 3)
        XCTAssertTrue(outlines.isSelectionVisible)
        XCTAssertTrue(outlines.isLassoVisible)
        XCTAssertTrue(outlines.isSelectionAnimating)
        XCTAssertEqual(outlines.selectionPathBounds, CGRect(x: 8_994, y: 8_994, width: 612, height: 412))
        XCTAssertEqual(outlines.lassoPathBounds, CGRect(x: 9_100, y: 9_100, width: 400, height: 300))
    }

    func testLassoMovePreservesExactPencilKitPathsForSelectedAndNearbyWriting() {
        let selected = uniquelyIdentified(stroke(sampleCount: 8, xOffset: 0))
        let nearby = uniquelyIdentified(stroke(sampleCount: 10, xOffset: 100))
        let drawing = PencilCanvasRenderer.drawing(from: [selected, nearby])
        let originalSelected = drawing.strokes[0]
        let originalNearby = drawing.strokes[1]
        let transform = SelectionTransform(
            scaleX: 1,
            scaleY: 1,
            rotation: 0,
            translation: CanvasPoint(x: 40, y: 25)
        )

        let result = PencilCanvasSelectionTransform.applying(
            objectIDs: [selected.objectID],
            transform: transform,
            center: CanvasPoint(x: 20, y: 20),
            to: drawing,
            canonicalStrokes: [selected, nearby]
        )

        XCTAssertEqual(result.drawing.strokes[0].path.map(\.location), originalSelected.path.map(\.location))
        XCTAssertEqual(result.drawing.strokes[1].path.map(\.location), originalNearby.path.map(\.location))
        XCTAssertEqual(result.drawing.strokes[1].transform, originalNearby.transform)
        XCTAssertEqual(
            result.drawing.strokes[0].renderBounds,
            originalSelected.renderBounds.offsetBy(dx: 40, dy: 25)
        )
        XCTAssertEqual(result.canonicalStrokes[1], nearby)
        XCTAssertEqual(result.canonicalStrokes[0].samples[0].point, CanvasPoint(x: 40, y: 25))
    }

    func testLassoOutlineUsesAnimatedMarchingAnts() {
        let outline = CanvasLassoOutlineLayer()

        XCTAssertEqual(outline.lineDashPattern, [6, 4])
        XCTAssertNotNil(outline.animation(forKey: "marchingAnts"))
    }

    private func draw(
        _ stroke: Stroke,
        withExisting existing: [Stroke],
        on canvasView: PKCanvasView,
        coordinator: PencilCanvasView.Coordinator
    ) {
        coordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PencilCanvasRenderer.drawing(from: existing + [stroke])
        coordinator.canvasViewDrawingDidChange(canvasView)
        coordinator.canvasViewDidEndUsingTool(canvasView)
    }

    private func stroke(sampleCount: Int, xOffset: Double) -> Stroke {
        var result = DomainFixtures.stroke()
        result.samples = (0..<sampleCount).map { index in
            StrokeSample(
                point: CanvasPoint(x: xOffset + Double(index * 7), y: Double(index * 5)),
                pressure: 0.5,
                altitude: 0.7,
                azimuth: 1.1,
                roll: 0.2,
                timeOffset: Double(index) * 0.01
            )
        }
        return result
    }

    private func uniquelyIdentified(_ stroke: Stroke) -> Stroke {
        Stroke(
            id: StrokeID(),
            layerID: stroke.layerID,
            samples: stroke.samples,
            style: stroke.style,
            createdAt: stroke.createdAt
        )
    }

    private func pencilStroke(color: InkColor, size: CGSize, opacity: CGFloat) -> PKStroke {
        var points: [PKStrokePoint] = []
        for index in 0..<8 {
            let scalar = CGFloat(index)
            let location = CGPoint(x: 100 + scalar * 9, y: 200 + scalar * 5)
            let point = PKStrokePoint(
                location: location,
                timeOffset: Double(index) * 0.01,
                size: size,
                opacity: opacity,
                force: 0.35 + scalar * 0.05,
                azimuth: 1.1,
                altitude: 0.7,
                secondaryScale: 0.75 + scalar * 0.02
            )
            points.append(point)
        }
        return PKStroke(
            ink: PKInk(.marker, color: UIColor(color)),
            path: PKStrokePath(controlPoints: points, creationDate: DomainFixtures.fixedDate)
        )
    }

    private func makeCoordinator(
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
}
