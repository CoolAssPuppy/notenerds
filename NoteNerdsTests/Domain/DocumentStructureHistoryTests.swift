import XCTest
@testable import NoteNerds

final class DocumentStructureHistoryTests: XCTestCase {
    func testCanvasOperationsApplyUndoAndRedoExactly() throws {
        let original = DomainFixtures.notebook()
        let added = Canvas(title: "Added", createdAt: DomainFixtures.fixedDate, modifiedAt: DomainFixtures.fixedDate)
        try assertRoundTrip(.insertCanvas(canvas: added, index: 1), original: original)

        let placement = CanvasPlacement(index: 0, canvas: original.canvases[0])
        var twoCanvases = original
        twoCanvases.canvases.append(added)
        try assertRoundTrip(.deleteCanvas(placement), original: twoCanvases)
        try assertRoundTrip(.moveCanvas(sourceIndex: 0, destinationIndex: 1), original: twoCanvases)
    }

    func testLayerOperationsAndTemplateApplyUndoAndRedoExactly() throws {
        let original = DomainFixtures.notebook()
        let canvasID = original.canvases[0].id
        let layer = Layer(name: "Sketches")
        try assertRoundTrip(.insertLayer(canvasID: canvasID, layer: layer, index: 1), original: original)

        var twoLayers = original
        twoLayers.canvases[0].layers.append(layer)
        let placement = LayerPlacement(canvasID: canvasID, index: 1, layer: layer)
        try assertRoundTrip(.deleteLayer(placement), original: twoLayers)
        try assertRoundTrip(
            .moveLayer(canvasID: canvasID, sourceIndex: 0, destinationIndex: 1),
            original: twoLayers
        )
        var renamedLayer = original.canvases[0].layers[0]
        renamedLayer.name = "Final notes"
        renamedLayer.isVisible = false
        try assertRoundTrip(
            .updateLayer(canvasID: canvasID, before: original.canvases[0].layers[0], after: renamedLayer),
            original: original
        )
        try assertRoundTrip(
            .changeTemplate(canvasID: canvasID, before: .dotSmall, after: .yellowLegalPad),
            original: original
        )
    }

    func testContentOperationsApplyUndoRedoAndSerializeExactly() throws {
        let original = DomainFixtures.notebook()
        let canvas = original.canvases[0]
        let layer = canvas.layers[0]
        let stroke = try XCTUnwrap(layer.objects[0].strokeValue)
        let placement = ObjectPlacement(layerID: layer.id, index: 0, object: .stroke(stroke))
        try assertRoundTrip(.deleteObjects(canvasID: canvas.id, objects: [placement]), original: original)

        let addedStroke = DomainFixtures.stroke(id: StrokeID(), layerID: layer.id)
        try assertRoundTrip(
            .addStroke(canvasID: canvas.id, layerID: layer.id, stroke: addedStroke),
            original: original
        )

        let text = TextBlock(
            id: ObjectID(),
            layerID: layer.id,
            text: "Converted",
            frame: stroke.bounds,
            fontSize: 20,
            alignment: .left
        )
        try assertRoundTrip(
            .convertStrokesToText(canvasID: canvas.id, sourceObjects: [placement], textBlock: text),
            original: original
        )

        let transformed = placement.object.applying(
            SelectionTransform(
                scaleX: 1,
                scaleY: 1,
                rotation: 0,
                translation: CanvasPoint(x: 20, y: 10)
            ),
            around: stroke.bounds.origin
        )
        try assertRoundTrip(
            .replaceObjects(
                canvasID: canvas.id,
                before: [placement],
                after: [ObjectPlacement(layerID: layer.id, index: 0, object: transformed)]
            ),
            original: original
        )
    }

    private func assertRoundTrip(
        _ operation: DocumentOperation,
        original: Notebook,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let encoded = try JSONEncoder().encode(operation)
        XCTAssertEqual(try JSONDecoder().decode(DocumentOperation.self, from: encoded), operation)
        var notebook = original
        var history = DocumentHistory()
        try history.execute(operation, on: &notebook)
        let applied = notebook
        XCTAssertNotEqual(applied, original, file: file, line: line)
        try history.undo(on: &notebook)
        XCTAssertEqual(notebook, original, file: file, line: line)
        try history.redo(on: &notebook)
        XCTAssertEqual(notebook, applied, file: file, line: line)
    }
}
