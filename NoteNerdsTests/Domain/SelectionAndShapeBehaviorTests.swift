import XCTest
@testable import NoteNerds

final class SelectionAndShapeBehaviorTests: XCTestCase {
    func testLassoSelectsStrokeThatMeaningfullyIntersectsItsArea() {
        let layerID = LayerID()
        let crossingStroke = Stroke(
            id: StrokeID(),
            layerID: layerID,
            samples: [sample(x: -20, y: 50), sample(x: 120, y: 50)],
            style: StrokeStyle(instrument: .ballpoint, width: 2, color: .black),
            createdAt: DomainFixtures.fixedDate
        )
        let lasso = LassoPath(points: [
            CanvasPoint(x: 0, y: 0), CanvasPoint(x: 100, y: 0),
            CanvasPoint(x: 100, y: 100), CanvasPoint(x: 0, y: 100)
        ])

        XCTAssertTrue(lasso.selects(.stroke(crossingStroke)))
    }

    func testLassoDoesNotSelectNearbyTextWhenOnlyItsFrameEdgeCrossesThePath() {
        let layerID = LayerID()
        let nearbyText = TextBlock(
            id: ObjectID(),
            layerID: layerID,
            text: "Nearby text",
            frame: CanvasRect(x: 95, y: 20, width: 160, height: 44),
            fontSize: 18,
            alignment: .left,
            fontName: nil
        )
        var enclosedText = nearbyText
        enclosedText.frame = CanvasRect(x: 20, y: 20, width: 60, height: 44)
        let lasso = LassoPath(points: [
            CanvasPoint(x: 0, y: 0), CanvasPoint(x: 100, y: 0),
            CanvasPoint(x: 100, y: 100), CanvasPoint(x: 0, y: 100)
        ])

        XCTAssertFalse(lasso.selects(.text(nearbyText)))
        XCTAssertTrue(lasso.selects(.text(enclosedText)))
    }

    func testLassoDoesNotSelectNearbyInkThatOnlySharesItsBoundingBox() {
        let layerID = LayerID()
        let nearbyStroke = Stroke(
            id: StrokeID(),
            layerID: layerID,
            samples: [sample(x: 80, y: 80), sample(x: 90, y: 90)],
            style: StrokeStyle(instrument: .ballpoint, width: 2, color: .black),
            createdAt: DomainFixtures.fixedDate
        )
        let triangularLasso = LassoPath(points: [
            CanvasPoint(x: 0, y: 0),
            CanvasPoint(x: 100, y: 0),
            CanvasPoint(x: 0, y: 100)
        ])

        XCTAssertFalse(triangularLasso.selects(.stroke(nearbyStroke)))
    }

    func testProportionalInkResizeScalesGeometryAndWidth() {
        let stroke = DomainFixtures.stroke()
        let transform = SelectionTransform(scaleX: 2, scaleY: 2, rotation: 0, translation: .zero)

        let transformed = CanvasObject.stroke(stroke).applying(transform, around: CanvasPoint(x: 10, y: 20))
        let transformedStroke = transformed.strokeValue

        XCTAssertEqual(transformedStroke?.samples[1].point, CanvasPoint(x: 50, y: 60))
        XCTAssertEqual(transformedStroke?.style.width, 4)
        XCTAssertEqual(transformedStroke?.layerID, stroke.layerID)
    }

    func testHeldRoughLineRecognizesStraightLineAndKeepsOriginal() {
        let layerID = LayerID()
        let roughLine = Stroke(
            id: StrokeID(),
            layerID: layerID,
            samples: [sample(x: 0, y: 0), sample(x: 40, y: 2), sample(x: 100, y: 0)],
            style: StrokeStyle(instrument: .fineliner, width: 2, color: .black),
            createdAt: DomainFixtures.fixedDate
        )

        let shape = ShapeRecognizer().recognize(roughLine, holdDuration: 0.6)

        XCTAssertEqual(shape?.kind, .line)
        XCTAssertEqual(shape?.originalStroke, roughLine)
    }

    func testHeldHighlighterStrokeRemainsInkOverExistingWriting() {
        let layerID = LayerID()
        let highlight = Stroke(
            id: StrokeID(),
            layerID: layerID,
            samples: [sample(x: 0, y: 0), sample(x: 40, y: 2), sample(x: 100, y: 0)],
            style: StrokeStyle(
                instrument: .highlighter,
                width: 6,
                color: InkColor(red: 0.95, green: 0.78, blue: 0.2, alpha: 0.45)
            ),
            createdAt: DomainFixtures.fixedDate
        )

        XCTAssertNil(ShapeRecognizer().recognize(highlight, holdDuration: 0.6))
    }

    func testShortHoldDoesNotReplaceFreehandStroke() {
        XCTAssertNil(ShapeRecognizer().recognize(DomainFixtures.stroke(), holdDuration: 0.1))
    }

    func testHeldArrowRecognizesShaftAndArrowhead() {
        let layerID = LayerID()
        let arrow = Stroke(
            id: StrokeID(),
            layerID: layerID,
            samples: [
                sample(x: 0, y: 50), sample(x: 100, y: 50),
                sample(x: 78, y: 32), sample(x: 100, y: 50), sample(x: 78, y: 68)
            ],
            style: StrokeStyle(instrument: .ballpoint, width: 2, color: .black),
            createdAt: DomainFixtures.fixedDate
        )

        XCTAssertEqual(ShapeRecognizer().recognize(arrow, holdDuration: 0.6)?.kind, .arrow)
    }

    func testTerminalHoldDurationIgnoresTimeSpentDrawingTheShape() {
        let layerID = LayerID()
        let slowLine = Stroke(
            id: StrokeID(),
            layerID: layerID,
            samples: [
                timedSample(x: 0, y: 0, time: 0),
                timedSample(x: 100, y: 0, time: 1.2),
                timedSample(x: 101, y: 0, time: 1.3)
            ],
            style: StrokeStyle(instrument: .ballpoint, width: 2, color: .black),
            createdAt: DomainFixtures.fixedDate
        )

        XCTAssertEqual(slowLine.terminalHoldDuration, 0.1, accuracy: 0.001)
    }

    func testHeldClosedShapesRecognizeEverySpecifiedGeometry() {
        XCTAssertEqual(recognizedKind(points: [
            (0, 0), (120, 0), (120, 60), (0, 60), (0, 0)
        ]), .rectangle)
        XCTAssertEqual(recognizedKind(points: [
            (0, 0), (100, 0), (100, 100), (0, 100), (0, 0)
        ]), .square)
        XCTAssertEqual(recognizedKind(points: [
            (50, 0), (100, 100), (0, 100), (50, 0)
        ]), .triangle)
        XCTAssertEqual(recognizedKind(points: ellipsePoints(width: 100, height: 100)), .circle)
        XCTAssertEqual(recognizedKind(points: ellipsePoints(width: 160, height: 80)), .ellipse)
    }

    private func sample(x: Double, y: Double) -> StrokeSample {
        StrokeSample(
            point: CanvasPoint(x: x, y: y),
            pressure: 0.5,
            altitude: 1,
            azimuth: 0,
            roll: 0,
            timeOffset: 0
        )
    }

    private func timedSample(x: Double, y: Double, time: TimeInterval) -> StrokeSample {
        var result = sample(x: x, y: y)
        result.timeOffset = time
        return result
    }

    private func recognizedKind(points: [(Double, Double)]) -> RecognizedShapeKind? {
        let layerID = LayerID()
        let stroke = Stroke(
            id: StrokeID(),
            layerID: layerID,
            samples: points.map { sample(x: $0.0, y: $0.1) },
            style: StrokeStyle(instrument: .ballpoint, width: 2, color: .black),
            createdAt: DomainFixtures.fixedDate
        )
        return ShapeRecognizer().recognize(stroke, holdDuration: 0.6)?.kind
    }

    private func ellipsePoints(width: Double, height: Double) -> [(Double, Double)] {
        (0...24).map { index in
            let angle = Double(index) / 24 * .pi * 2
            return (width / 2 + cos(angle) * width / 2, height / 2 + sin(angle) * height / 2)
        }
    }
}
