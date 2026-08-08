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
                .lasso, .text, .undo, .redo,
                .zoomToContent, .minimap, .changePaper, .importContent, .layers, .home
            ]
        )
    }

    func testExpandedVerticalToolbarUsesTwoColumnsToStayWithinTheCanvas() {
        XCTAssertEqual(CanvasToolbarPresentation.verticalColumnCount(isExpanded: false), 1)
        XCTAssertEqual(CanvasToolbarPresentation.verticalColumnCount(isExpanded: true), 2)
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
