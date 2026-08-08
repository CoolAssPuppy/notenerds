import XCTest
@testable import NoteNerds

final class DocumentModelBehaviorTests: XCTestCase {
    func testPaperCatalogContainsEverySupportedPaperTypeInGalleryOrder() {
        XCTAssertEqual(
            CanvasTemplate.allCases.map(\.rawValue),
            [
                "blankWhite", "blankCream", "gridLarge", "gridSmall",
                "dotLarge", "dotSmall", "yellowLegalPad", "whiteLegalPad"
            ]
        )
    }

    func testCanvasStoresTheSelectedPaperType() throws {
        let paperType = try XCTUnwrap(CanvasTemplate(rawValue: "gridSmall"))

        let canvas = Canvas(title: "Plans", template: paperType)

        XCTAssertEqual(canvas.template, paperType)
    }

    func testStrokeRetainsEveryInputCharacteristic() {
        let stroke = DomainFixtures.stroke()

        XCTAssertEqual(stroke.samples.count, 2)
        XCTAssertEqual(stroke.samples[1].pressure, 0.75)
        XCTAssertEqual(stroke.samples[1].altitude, 0.6)
        XCTAssertEqual(stroke.samples[1].azimuth, 1.4)
        XCTAssertEqual(stroke.samples[1].roll, 0.3)
        XCTAssertEqual(stroke.samples[1].timeOffset, 0.02)
        XCTAssertEqual(stroke.bounds, CanvasRect(x: 10, y: 20, width: 20, height: 20))
    }

    func testCanvasAlwaysRetainsOneContentLayer() throws {
        var canvas = DomainFixtures.notebook().canvases[0]

        XCTAssertThrowsError(try canvas.deleteLayer(id: canvas.layers[0].id)) { error in
            XCTAssertEqual(error as? DocumentError, .canvasRequiresLayer)
        }
        XCTAssertEqual(canvas.layers.count, 1)
    }

    func testMovingObjectsBetweenLayersPreservesTheirIdentity() throws {
        var canvas = DomainFixtures.notebook().canvases[0]
        let stroke = try XCTUnwrap(canvas.layers[0].objects.first?.strokeValue)
        let destination = Layer(name: "Ideas")
        canvas.layers.append(destination)

        try canvas.moveObjects(ids: [stroke.objectID], to: destination.id)

        XCTAssertTrue(canvas.layers[0].objects.isEmpty)
        XCTAssertEqual(canvas.layers[1].objects.first?.id, stroke.objectID)
        XCTAssertEqual(canvas.layers[1].objects.first?.layerID, destination.id)
    }

    func testCanvasRejectsZoomOutsideDocumentBounds() {
        XCTAssertEqual(CanvasViewport.clampedZoom(0.01), 0.1)
        XCTAssertEqual(CanvasViewport.clampedZoom(2), 2)
        XCTAssertEqual(CanvasViewport.clampedZoom(12), 8)
    }

    func testViewportCoordinateRoundTripIsExact() {
        let viewport = CanvasViewport(origin: CanvasPoint(x: -120, y: 75), zoom: 2.5)
        let logicalPoint = CanvasPoint(x: 44, y: -18)

        let screenPoint = viewport.screenPoint(for: logicalPoint)

        XCTAssertEqual(viewport.canvasPoint(for: screenPoint), logicalPoint)
    }
}
