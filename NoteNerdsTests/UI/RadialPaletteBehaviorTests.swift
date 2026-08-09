import UIKit
import XCTest
@testable import NoteNerds

final class RadialPaletteBehaviorTests: XCTestCase {
    func testRootOpensChoicePagesInsteadOfCyclingInspectorValues() {
        let items = RadialPalettePresentation.items(for: .root)

        XCTAssertEqual(
            items.map(\.label),
            ["Writing tools", "Width", "Color", "Eraser", "Lasso", "Undo", "Redo"]
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
        XCTAssertEqual(RadialPalettePresentation.ringCount(for: items.count), 1)
    }

    func testColorPageContainsAllPresetsAndCustomColorAcrossTwoRings() {
        let items = RadialPalettePresentation.items(for: .colors)

        XCTAssertEqual(
            items.map(\.label),
            CanvasInkChoice.allCases.map(\.label) + ["Custom color"]
        )
        XCTAssertEqual(RadialPalettePresentation.ringCount(for: items.count), 2)
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

    func testRootActionsUseOneCompleteRing() {
        let items = RadialPalettePresentation.items(for: .root)

        XCTAssertEqual(RadialPalettePresentation.ringCount(for: items.count), 1)
        XCTAssertEqual(Set(items.indices.map {
            RadialPalettePresentation.placement(for: $0, itemCount: items.count).radius
        }).count, 1)
    }

    func testRingCountGrowsAtTenItemBoundariesAndStopsAtThree() {
        XCTAssertEqual(RadialPalettePresentation.ringCount(for: 0), 0)
        XCTAssertEqual(RadialPalettePresentation.ringCount(for: 10), 1)
        XCTAssertEqual(RadialPalettePresentation.ringCount(for: 11), 2)
        XCTAssertEqual(RadialPalettePresentation.ringCount(for: 20), 2)
        XCTAssertEqual(RadialPalettePresentation.ringCount(for: 21), 3)
        XCTAssertEqual(RadialPalettePresentation.ringCount(for: 30), 3)
    }

    func testEveryRingUsesEqualAngularSpacing() {
        for itemCount in [7, 9, 15, 24] {
            let placements = (0..<itemCount).map {
                RadialPalettePresentation.placement(for: $0, itemCount: itemCount)
            }
            for ringIndex in 0..<RadialPalettePresentation.ringCount(for: itemCount) {
                let ring = placements.filter { $0.ringIndex == ringIndex }
                let expectedStep = 360 / Double(ring.count)
                let angles = ring.map(\.angleDegrees).sorted()
                let wrapped = angles + [angles[0] + 360]
                for index in 0..<angles.count {
                    XCTAssertEqual(wrapped[index + 1] - wrapped[index], expectedStep, accuracy: 0.001)
                }
            }
        }
    }

    func testConcentricRingsUseDifferentAngularPhases() {
        let placements = (0..<15).map {
            RadialPalettePresentation.placement(for: $0, itemCount: 15)
        }
        let firstAngles = Set(placements.filter { $0.ringIndex == 0 }.map(\.angleDegrees))
        let secondAngles = Set(placements.filter { $0.ringIndex == 1 }.map(\.angleDegrees))

        XCTAssertTrue(firstAngles.isDisjoint(with: secondAngles))
    }

    func testEveryRadialItemUsesAnAvailableSystemSymbol() {
        for page in [
            RadialPalettePage.root,
            .drawingTools,
            .widths,
            .eraserModes,
            .precisionEraserWidths
        ] {
            for item in RadialPalettePresentation.items(for: page) where item.action != .customColor {
                XCTAssertNotNil(UIImage(systemName: item.symbol), "Missing symbol for \(item.label)")
            }
        }
    }

    private func item(
        named label: String,
        in items: [RadialPaletteItem]
    ) -> RadialPaletteItem? {
        items.first { $0.label == label }
    }
}
