import PencilKit
import UIKit
import XCTest
@testable import NoteNerds

@MainActor
final class CanvasViewportBoundaryBehaviorTests: XCTestCase {
    func testCanvasOverlaysGrowWithTheInkWhenTheCanvasIsZoomed() {
        let canvasView = PKCanvasView()
        PencilCanvasView.configureViewport(canvasView)
        let overlay = UIView(frame: CGRect(origin: .zero, size: canvasView.contentSize))
        overlay.tag = CanvasOverlayGeometry.tags.lowerBound
        canvasView.addSubview(overlay)
        CanvasOverlayGeometry.pinToContentOrigin(overlay)

        canvasView.zoomScale = 2
        CanvasOverlayGeometry.synchronizeZoom(in: canvasView)

        XCTAssertEqual(overlay.transform.a, 2, accuracy: 0.001)
        XCTAssertEqual(overlay.transform.d, 2, accuracy: 0.001)
        XCTAssertEqual(overlay.frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(overlay.frame.minY, 0, accuracy: 0.5)
    }

    func testAPointOnAZoomedOverlayStillMeansTheSameSpotOnTheCanvas() {
        let canvasView = PKCanvasView()
        PencilCanvasView.configureViewport(canvasView)
        let overlay = UIView(frame: CGRect(origin: .zero, size: canvasView.contentSize))
        overlay.tag = CanvasOverlayGeometry.tags.lowerBound
        canvasView.addSubview(overlay)
        CanvasOverlayGeometry.pinToContentOrigin(overlay)
        canvasView.zoomScale = 2
        CanvasOverlayGeometry.synchronizeZoom(in: canvasView)

        let canvasPoint = overlay.convert(CGPoint(x: 600, y: 400), to: canvasView)

        XCTAssertEqual(canvasPoint.x, 1_200, accuracy: 0.5)
        XCTAssertEqual(canvasPoint.y, 800, accuracy: 0.5)
    }

    func testALockedCanvasCannotBeScrolledOrZoomedButCanStillBeDrawnOn() {
        let canvasView = PKCanvasView()
        PencilCanvasView.configureViewport(canvasView)

        PencilCanvasView.applyCanvasLock(true, to: canvasView)

        XCTAssertFalse(canvasView.isScrollEnabled)
        XCTAssertFalse(canvasView.pinchGestureRecognizer?.isEnabled ?? true)
        XCTAssertTrue(canvasView.drawingGestureRecognizer.isEnabled)
    }

    /// The lock only takes away the two touch gestures, so the app can still
    /// move and scale the page. That is what the double tap on the lock, the
    /// planner pager, and search navigation all depend on.
    func testALockedCanvasCanStillBeMovedAndScaledByTheApp() {
        let canvasView = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 820, height: 600))
        PencilCanvasView.configureViewport(canvasView)
        PencilCanvasView.applyCanvasLock(true, to: canvasView)

        canvasView.zoomScale = 2
        canvasView.contentOffset = CGPoint(x: 12_000, y: 11_000)

        XCTAssertEqual(canvasView.zoomScale, 2, accuracy: 0.001)
        XCTAssertEqual(canvasView.contentOffset.x, 12_000, accuracy: 0.5)
        XCTAssertEqual(canvasView.contentOffset.y, 11_000, accuracy: 0.5)
    }

    func testUnlockingTheCanvasRestoresScrollingAndZooming() {
        let canvasView = PKCanvasView()
        PencilCanvasView.configureViewport(canvasView)
        PencilCanvasView.applyCanvasLock(true, to: canvasView)

        PencilCanvasView.applyCanvasLock(false, to: canvasView)

        XCTAssertTrue(canvasView.isScrollEnabled)
        XCTAssertTrue(canvasView.pinchGestureRecognizer?.isEnabled ?? false)
    }
}
