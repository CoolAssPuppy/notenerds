import XCTest
@testable import NoteNerds

final class EditingBehaviorTests: XCTestCase {
    func testSelectionTransformPreservesLayerMembershipAndUndoRestoresExactObjects() throws {
        var notebook = DomainFixtures.notebook()
        let canvas = notebook.canvases[0]
        let original = canvas.layers[0].objects[0]
        let operation = try DocumentOperation.transformObjects(
            in: notebook,
            canvasID: canvas.id,
            objectIDs: [original.id],
            transform: SelectionTransform(
                scaleX: 2,
                scaleY: 2,
                rotation: .pi / 4,
                translation: CanvasPoint(x: 30, y: 20)
            ),
            center: CanvasPoint(x: 20, y: 30)
        )

        try operation.apply(to: &notebook)
        let transformed = notebook.canvases[0].layers[0].objects[0]
        XCTAssertEqual(transformed.layerID, original.layerID)
        XCTAssertNotEqual(transformed, original)

        try operation.undo(on: &notebook)
        XCTAssertEqual(notebook.canvases[0].layers[0].objects[0], original)
    }

    func testClipboardPasteCreatesFreshEditableObjectsWithOneOffset() throws {
        let notebook = DomainFixtures.notebook()
        let canvas = notebook.canvases[0]
        let source = canvas.layers[0].objects
        let payload = SelectionClipboardPayload(objects: source)

        let pasted = payload.pasted(offset: CanvasPoint(x: 24, y: 32))

        XCTAssertEqual(pasted.count, source.count)
        XCTAssertNotEqual(pasted[0].id, source[0].id)
        XCTAssertEqual(pasted[0].layerID, source[0].layerID)
        XCTAssertEqual(pasted[0].bounds.minX, source[0].bounds.minX + 24, accuracy: 0.001)
        XCTAssertEqual(pasted[0].bounds.minY, source[0].bounds.minY + 32, accuracy: 0.001)
    }

    func testClipboardPastePreservesTheSelectedFont() throws {
        let layerID = LayerID()
        let source = CanvasObject.text(TextBlock(
            id: ObjectID(),
            layerID: layerID,
            text: "Set in Avenir",
            frame: CanvasRect(x: 0, y: 0, width: 240, height: 44),
            fontSize: 22,
            alignment: .left,
            fontName: "AvenirNext-Regular"
        ))

        let pasted = try XCTUnwrap(SelectionClipboardPayload(objects: [source]).pasted(offset: .zero).first)
        guard case let .text(textBlock) = pasted else {
            return XCTFail("Expected pasted text")
        }

        XCTAssertEqual(textBlock.fontName, "AvenirNext-Regular")
    }

    func testPrecisionEraserSplitsVectorStrokeAndKeepsSampleData() {
        let layerID = LayerID()
        var stroke = DomainFixtures.stroke(layerID: layerID)
        stroke.samples = (0...10).map { index in
            StrokeSample(
                point: CanvasPoint(x: Double(index * 10), y: 20),
                pressure: Double(index) / 10,
                altitude: 0.7,
                azimuth: 1.1,
                roll: 0.2,
                timeOffset: Double(index) * 0.01
            )
        }

        let fragments = VectorEraser().erase(
            stroke,
            along: [CanvasPoint(x: 50, y: 20)],
            radius: 12
        )

        XCTAssertEqual(fragments.count, 2)
        XCTAssertEqual(fragments.flatMap(\.samples).map(\.pressure), [0, 0.1, 0.2, 0.3, 0.7, 0.8, 0.9, 1])
        XCTAssertTrue(fragments.allSatisfy { $0.layerID == layerID && $0.style == stroke.style })
    }

    func testHandwritingConversionLayoutPreservesReadingOrderAndLineBreaks() {
        let first = recognition(text: "Hello", x: 10, y: 20)
        let second = recognition(text: "world", x: 100, y: 22)
        let nextLine = recognition(text: "Again", x: 10, y: 80)

        let block = HandwritingTextLayout().textBlock(
            from: [nextLine, second, first],
            layerID: LayerID()
        )

        XCTAssertEqual(block.text, "Hello world\nAgain")
        XCTAssertEqual(block.frame, CanvasRect(x: 10, y: 20, width: 150, height: 90))
    }

    func testConvertingSelectedStrokesKeepsOtherSelectedObjectTypesUnchanged() throws {
        var notebook = DomainFixtures.notebook()
        let canvas = notebook.canvases[0]
        let layer = canvas.layers[0]
        let stroke = try XCTUnwrap(layer.objects.compactMap(\.strokeValue).first)
        let existingText = TextBlock(
            id: ObjectID(),
            layerID: layer.id,
            text: "Keep me",
            frame: CanvasRect(x: 200, y: 200, width: 100, height: 40),
            fontSize: 17,
            alignment: .left
        )
        notebook.canvases[0].layers[0].objects.append(.text(existingText))
        let replacement = TextBlock(
            id: ObjectID(),
            layerID: layer.id,
            text: "Converted",
            frame: stroke.bounds,
            fontSize: 17,
            alignment: .left
        )
        let operation = try DocumentOperation.convertStrokesToText(
            in: notebook,
            canvasID: canvas.id,
            strokeIDs: [stroke.id],
            textBlock: replacement
        )

        try operation.apply(to: &notebook)

        let objects = notebook.canvases[0].layers[0].objects
        XCTAssertTrue(objects.contains(.text(existingText)))
        XCTAssertTrue(objects.contains(.text(replacement)))
        XCTAssertFalse(objects.contains(.stroke(stroke)))
    }

    func testShapeSnapUndoRestoresOriginalFreehandStroke() throws {
        var notebook = DomainFixtures.notebook()
        let canvas = notebook.canvases[0]
        let stroke = try XCTUnwrap(canvas.layers[0].objects[0].strokeValue)
        let shape = RecognizedShape(
            id: ObjectID(), layerID: stroke.layerID, kind: .line,
            points: [CanvasPoint(x: 10, y: 20), CanvasPoint(x: 30, y: 40)],
            style: stroke.style, originalStroke: stroke
        )
        let operation = try DocumentOperation.snapStrokeToShape(
            canvasID: canvas.id,
            strokeID: stroke.id,
            shape: shape,
            in: notebook
        )

        try operation.apply(to: &notebook)
        XCTAssertEqual(notebook.canvases[0].layers[0].objects[0], .shape(shape))
        try operation.undo(on: &notebook)
        XCTAssertEqual(notebook.canvases[0].layers[0].objects[0], .stroke(stroke))
    }

    func testEraserRemembersStrokeAndPrecisionModes() {
        var palette = ToolPaletteState()
        palette.select(.eraser)
        palette.setEraserMode(.precision)
        palette.select(.ballpoint)

        palette.select(.eraser)

        XCTAssertEqual(palette.current.eraserMode, .precision)
    }

    private func recognition(text: String, x: Double, y: Double) -> HandwritingRecognitionResult {
        HandwritingRecognitionResult(
            text: text,
            confidence: 0.9,
            bounds: CanvasRect(x: x, y: y, width: 60, height: 30),
            sourceStrokeIDs: [],
            recognizerVersion: "test"
        )
    }
}
