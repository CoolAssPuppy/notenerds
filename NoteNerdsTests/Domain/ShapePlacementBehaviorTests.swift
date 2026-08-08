import XCTest
@testable import NoteNerds

final class ShapePlacementBehaviorTests: XCTestCase {
    func testEveryClassicShapeUsesTheChosenCenterLayerAndInkStyle() {
        let center = CanvasPoint(x: 400, y: 300)
        let layerID = LayerID()
        let style = StrokeStyle(
            instrument: .fineliner,
            width: 6,
            color: InkColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        )

        for kind in RecognizedShapeKind.allCases {
            let shape = ShapeFactory.make(kind, centeredAt: center, layerID: layerID, style: style)

            XCTAssertEqual(shape.kind, kind)
            XCTAssertEqual(shape.layerID, layerID)
            XCTAssertEqual(shape.style, style)
            XCTAssertNil(shape.originalStroke)
            XCTAssertGreaterThanOrEqual(shape.points.count, 2)
            XCTAssertGreaterThan(CanvasRect.enclosing(shape.points).size.width, 0)
        }
    }

    func testSquareAndCircleKeepEqualDimensionsWhileRectangleAndEllipseAreWide() {
        let layerID = LayerID()
        let style = DomainFixtures.stroke(layerID: layerID).style
        let center = CanvasPoint(x: 200, y: 180)

        let square = ShapeFactory.make(.square, centeredAt: center, layerID: layerID, style: style)
        let circle = ShapeFactory.make(.circle, centeredAt: center, layerID: layerID, style: style)
        let rectangle = ShapeFactory.make(.rectangle, centeredAt: center, layerID: layerID, style: style)
        let ellipse = ShapeFactory.make(.ellipse, centeredAt: center, layerID: layerID, style: style)

        XCTAssertEqual(square.bounds.size.width, square.bounds.size.height, accuracy: 0.001)
        XCTAssertEqual(circle.bounds.size.width, circle.bounds.size.height, accuracy: 0.001)
        XCTAssertGreaterThan(rectangle.bounds.size.width, rectangle.bounds.size.height)
        XCTAssertGreaterThan(ellipse.bounds.size.width, ellipse.bounds.size.height)
    }
}
