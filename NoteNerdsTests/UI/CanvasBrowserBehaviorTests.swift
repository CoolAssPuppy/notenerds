import XCTest
@testable import NoteNerds

final class CanvasBrowserBehaviorTests: XCTestCase {
    func testBothCanvasMenusUseTheSamePrimaryActionsInAppleOrder() {
        XCTAssertEqual(
            CanvasBrowserAction.allCases,
            [.rename, .duplicate, .changePaper]
        )
        XCTAssertEqual(
            CanvasBrowserAction.allCases.map(\.label),
            ["Rename canvas", "Duplicate canvas", "Change paper"]
        )
        XCTAssertEqual(
            CanvasBrowserAction.allCases.map(\.symbol),
            ["pencil", "plus.square.on.square", "doc.text.image"]
        )
    }

    func testCanvasRenameTrimsWhitespaceAndRejectsAnEmptyName() {
        XCTAssertEqual(CanvasName.normalized("  Project ideas\n"), "Project ideas")
        XCTAssertNil(CanvasName.normalized("  \n "))
    }
}
