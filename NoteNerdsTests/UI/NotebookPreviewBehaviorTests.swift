import XCTest
@testable import NoteNerds

final class NotebookPreviewBehaviorTests: XCTestCase {
    func testRelativeEditTimeUsesFullPastUnits() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)

        XCTAssertEqual(
            NotebookModifiedTime.label(for: now.addingTimeInterval(-3_600), relativeTo: now),
            "1 hour ago"
        )
        XCTAssertEqual(
            NotebookModifiedTime.label(for: now.addingTimeInterval(-172_800), relativeTo: now),
            "2 days ago"
        )
    }

    func testCanvasPreviewSwipeMovesOnePageAndStopsAtEitherEnd() {
        XCTAssertEqual(NotebookCanvasPreviewPaging.destination(from: 0, translation: -80, canvasCount: 3), 1)
        XCTAssertEqual(NotebookCanvasPreviewPaging.destination(from: 1, translation: 80, canvasCount: 3), 0)
        XCTAssertEqual(NotebookCanvasPreviewPaging.destination(from: 0, translation: 80, canvasCount: 3), 0)
        XCTAssertEqual(NotebookCanvasPreviewPaging.destination(from: 2, translation: -80, canvasCount: 3), 2)
        XCTAssertEqual(NotebookCanvasPreviewPaging.destination(from: 1, translation: -12, canvasCount: 3), 1)
    }
}
