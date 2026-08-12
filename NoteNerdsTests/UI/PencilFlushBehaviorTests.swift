import PencilKit
import UIKit
import XCTest
@testable import NoteNerds

/// Guards the save that runs when the app leaves the foreground.
///
/// A flush captures the canvas and reconciles it. A second caller that only
/// waits for a flush already in progress can return before ink that arrived
/// after that flush captured the drawing has been saved, which is how the last
/// stroke goes missing on backgrounding.
@MainActor
final class PencilFlushBehaviorTests: XCTestCase {
    func testAFlushSavesInkThatArrivedWhileAnotherFlushWasRunning() async {
        let canvasView = PKCanvasView()
        var published: [Stroke] = []
        let coordinator = PencilStrokeTestFixture.coordinator(
            onStrokesCompleted: { published = $0 },
            onDrawingChanged: { published = $0 }
        )
        coordinator.attachSnapshotFlusher(PencilCanvasSnapshotFlusher(), canvasView: canvasView)

        coordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PKDrawing(strokes: [PencilStrokeTestFixture.blackPenStroke(randomSeed: 1)])
        coordinator.canvasViewDrawingDidChange(canvasView)
        coordinator.canvasViewDidEndUsingTool(canvasView)

        async let runningFlush: Void = coordinator.flushPendingDrawing()

        // Ink that lands after the running flush has captured the canvas.
        coordinator.canvasViewDidBeginUsingTool(canvasView)
        canvasView.drawing = PKDrawing(strokes: [
            PencilStrokeTestFixture.blackPenStroke(randomSeed: 1),
            PencilStrokeTestFixture.blackPenStroke(randomSeed: 2)
        ])
        coordinator.canvasViewDrawingDidChange(canvasView)
        coordinator.canvasViewDidEndUsingTool(canvasView)

        async let secondFlush: Void = coordinator.flushPendingDrawing()
        _ = await (runningFlush, secondFlush)

        XCTAssertEqual(
            published.count,
            2,
            "A flush returned before the ink that arrived during it had been saved"
        )
        XCTAssertFalse(coordinator.isDrawingCommitPending)
    }

    func testAFlushWithNothingPendingIsHarmless() async {
        let canvasView = PKCanvasView()
        let coordinator = PencilStrokeTestFixture.coordinator(onStrokesCompleted: { _ in })
        coordinator.attachSnapshotFlusher(PencilCanvasSnapshotFlusher(), canvasView: canvasView)

        await coordinator.flushPendingDrawing()
        await coordinator.flushPendingDrawing()

        XCTAssertFalse(coordinator.isDrawingCommitPending)
    }
}
