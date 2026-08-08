import XCTest
@testable import NoteNerds

final class ToolInspectorBehaviorTests: XCTestCase {
    func testDrawingWidthsProvideFiveOrderedVisualChoices() {
        XCTAssertEqual(ToolWidth.allCases.map(\.points), [0.75, 1.5, 3, 6, 10])
        XCTAssertEqual(
            ToolWidth.allCases.map(\.label),
            ["Extra fine", "Fine", "Medium", "Bold", "Extra bold"]
        )
    }

    func testColorInspectorProvidesACompleteFamiliarSwatchSet() {
        XCTAssertGreaterThanOrEqual(CanvasInkChoice.allCases.count, 14)
        XCTAssertEqual(
            Set(CanvasInkChoice.allCases.map(\.label)),
            Set([
                "Black", "Gray", "White", "Brown", "Red", "Orange", "Yellow",
                "Green", "Mint", "Cyan", "Blue", "Indigo", "Purple", "Pink"
            ])
        )
    }
}
