import XCTest
@testable import NoteNerds

final class CanvasToolbarBehaviorTests: XCTestCase {
    func testCompactToolbarShowsOnlyEssentialDrawingControls() {
        XCTAssertEqual(
            CanvasToolbarPresentation.actions(isExpanded: false),
            [.drawing, .width, .color, .eraser]
        )
    }

    func testExpandedToolbarAddsEveryFormerOverflowActionInline() {
        XCTAssertEqual(
            CanvasToolbarPresentation.actions(isExpanded: true),
            [
                .drawing, .width, .color, .eraser,
                .lasso, .text, .shapes, .undo, .redo,
                .zoomToContent, .minimap, .changePaper, .importContent, .layers, .home
            ]
        )
    }

    func testExpandedToolbarUsesOneBoundedScrollerAlongItsDockAxis() {
        XCTAssertEqual(CanvasToolbarPresentation.verticalColumnCount(isExpanded: false), 1)
        XCTAssertEqual(CanvasToolbarPresentation.verticalColumnCount(isExpanded: true), 1)
        XCTAssertEqual(CanvasToolbarPresentation.scrollAxis(orientation: .vertical), .vertical)
        XCTAssertEqual(CanvasToolbarPresentation.scrollAxis(orientation: .horizontal), .horizontal)
        XCTAssertEqual(CanvasToolbarPresentation.maximumExpandedLength(orientation: .vertical), 280)
        XCTAssertEqual(CanvasToolbarPresentation.maximumExpandedLength(orientation: .horizontal), 500)
        XCTAssertTrue(CanvasToolbarPresentation.isChevronPinned)
    }

    func testChevronRotatesHalfATurnAndMatchesToolbarAxis() {
        XCTAssertEqual(CanvasToolbarPresentation.chevronSymbol(orientation: .vertical), "chevron.down")
        XCTAssertEqual(CanvasToolbarPresentation.chevronSymbol(orientation: .horizontal), "chevron.right")
        XCTAssertEqual(CanvasToolbarPresentation.chevronRotation(isExpanded: false), 0)
        XCTAssertEqual(CanvasToolbarPresentation.chevronRotation(isExpanded: true), 180)
    }

    func testDragReleaseSnapsToTopOrNearestVerticalEdge() {
        let size = CGSize(width: 1_024, height: 768)

        XCTAssertEqual(
            CanvasToolbarDocking.destination(for: CGPoint(x: 700, y: 90), in: size),
            .top
        )
        XCTAssertEqual(
            CanvasToolbarDocking.destination(for: CGPoint(x: 120, y: 420), in: size),
            .left
        )
        XCTAssertEqual(
            CanvasToolbarDocking.destination(for: CGPoint(x: 900, y: 420), in: size),
            .right
        )
    }
}
