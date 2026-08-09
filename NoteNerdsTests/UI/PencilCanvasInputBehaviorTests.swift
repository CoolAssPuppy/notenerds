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
        XCTAssertEqual(outlines.selectionPathBounds, CGRect(x: 8_994, y: 8_994, width: 612, height: 412))
        XCTAssertEqual(outlines.lassoPathBounds, CGRect(x: 9_100, y: 9_100, width: 400, height: 300))
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

    private func makeCoordinator(
        onStrokesCompleted: @escaping @MainActor ([Stroke]) -> Void,
        onDrawingChanged: @escaping @MainActor ([Stroke]) -> Void = { _ in }
    ) -> PencilCanvasView.Coordinator {
        PencilCanvasView.Coordinator(
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
