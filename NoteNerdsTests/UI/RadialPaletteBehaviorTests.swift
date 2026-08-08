import XCTest
@testable import NoteNerds

final class RadialPaletteBehaviorTests: XCTestCase {
    func testRootOpensChoicePagesInsteadOfCyclingInspectorValues() {
        let items = RadialPalettePresentation.items(for: .root)

        XCTAssertEqual(
            items.map(\.label),
            ["Writing tools", "Eraser", "Lasso", "Undo", "Redo", "Width", "Color"]
        )
        XCTAssertEqual(item(named: "Writing tools", in: items)?.action.destination, .drawingTools)
        XCTAssertEqual(item(named: "Eraser", in: items)?.action.destination, .eraserModes)
        XCTAssertEqual(item(named: "Width", in: items)?.action.destination, .widths)
        XCTAssertEqual(item(named: "Color", in: items)?.action.destination, .colors)
    }

    func testEveryChoicePageReturnsToItsExpectedParent() {
        XCTAssertNil(RadialPalettePage.root.parent)
        XCTAssertEqual(RadialPalettePage.drawingTools.parent, .root)
        XCTAssertEqual(RadialPalettePage.colors.parent, .root)
        XCTAssertEqual(RadialPalettePage.widths.parent, .root)
        XCTAssertEqual(RadialPalettePage.eraserModes.parent, .root)
        XCTAssertEqual(RadialPalettePage.precisionEraserWidths.parent, .eraserModes)
    }

    func testWritingToolPageContainsEverySpecializedTool() {
        let items = RadialPalettePresentation.items(for: .drawingTools)

        XCTAssertEqual(
            items.map(\.label),
            [
                "Ballpoint", "Fineliner", "Mechanical pencil", "Pencil", "Marker",
                "Highlighter", "Brush", "Calligraphy pen", "Handwriting to text"
            ]
        )
        XCTAssertEqual(RadialPalettePresentation.ringCount(for: items.count), 2)
    }

    func testColorPageContainsAllPresetsAndCustomColorAcrossThreeRings() {
        let items = RadialPalettePresentation.items(for: .colors)

        XCTAssertEqual(
            items.map(\.label),
            CanvasInkChoice.allCases.map(\.label) + ["Custom color"]
        )
        XCTAssertEqual(RadialPalettePresentation.ringCount(for: items.count), 3)
    }

    func testWidthAndEraserPagesExposeTheirCompleteChoices() {
        XCTAssertEqual(
            RadialPalettePresentation.items(for: .widths).map(\.label),
            ToolWidth.allCases.map(\.label)
        )
        XCTAssertEqual(
            RadialPalettePresentation.items(for: .eraserModes).map(\.label),
            ["Object eraser", "Pixel eraser"]
        )
        XCTAssertEqual(
            RadialPalettePresentation.items(for: .precisionEraserWidths).map(\.label),
            ToolWidth.allCases.map(\.label)
        )
        XCTAssertEqual(
            RadialPaletteAction.eraserMode(.precision).destination,
            .precisionEraserWidths
        )
        XCTAssertNil(RadialPaletteAction.eraserMode(.stroke).destination)
    }

    func testRingCountGrowsAtSixItemBoundariesAndStopsAtThree() {
        XCTAssertEqual(RadialPalettePresentation.ringCount(for: 0), 0)
        XCTAssertEqual(RadialPalettePresentation.ringCount(for: 6), 1)
        XCTAssertEqual(RadialPalettePresentation.ringCount(for: 7), 2)
        XCTAssertEqual(RadialPalettePresentation.ringCount(for: 12), 2)
        XCTAssertEqual(RadialPalettePresentation.ringCount(for: 13), 3)
        XCTAssertEqual(RadialPalettePresentation.ringCount(for: 18), 3)
    }

    private func item(
        named label: String,
        in items: [RadialPaletteItem]
    ) -> RadialPaletteItem? {
        items.first { $0.label == label }
    }
}
