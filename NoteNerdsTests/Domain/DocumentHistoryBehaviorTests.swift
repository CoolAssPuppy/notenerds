import XCTest
@testable import NoteNerds

final class DocumentHistoryBehaviorTests: XCTestCase {
    func testAddingStrokeIsOneUndoableAndRedoableAction() throws {
        var notebook = emptyNotebook()
        var history = DocumentHistory()
        let canvas = notebook.canvases[0]
        let layer = canvas.layers[0]
        let stroke = DomainFixtures.stroke(layerID: layer.id)

        try history.execute(.addStroke(canvasID: canvas.id, layerID: layer.id, stroke: stroke), on: &notebook)
        XCTAssertEqual(notebook.canvases[0].layers[0].objects, [.stroke(stroke)])

        try history.undo(on: &notebook)
        XCTAssertTrue(notebook.canvases[0].layers[0].objects.isEmpty)

        try history.redo(on: &notebook)
        XCTAssertEqual(notebook.canvases[0].layers[0].objects, [.stroke(stroke)])
    }

    func testNewActionAfterUndoClearsRedoBranch() throws {
        var notebook = emptyNotebook()
        var history = DocumentHistory()
        let canvas = notebook.canvases[0]
        let layer = canvas.layers[0]
        let firstStroke = DomainFixtures.stroke(layerID: layer.id)
        let secondStroke = DomainFixtures.stroke(id: StrokeID(), layerID: layer.id)

        try history.execute(.addStroke(canvasID: canvas.id, layerID: layer.id, stroke: firstStroke), on: &notebook)
        try history.undo(on: &notebook)
        try history.execute(.addStroke(canvasID: canvas.id, layerID: layer.id, stroke: secondStroke), on: &notebook)

        XCTAssertFalse(history.canRedo)
        XCTAssertThrowsError(try history.redo(on: &notebook)) { error in
            XCTAssertEqual(error as? DocumentHistoryError, .nothingToRedo)
        }
    }

    func testHistoryDropsTheOldestActionsWhenItExceedsCapacity() throws {
        var notebook = emptyNotebook()
        var history = DocumentHistory(capacity: 40)
        let canvas = notebook.canvases[0]
        let layer = canvas.layers[0]

        for _ in 0..<50 {
            let stroke = DomainFixtures.stroke(id: StrokeID(), layerID: layer.id)
            try history.execute(.addStroke(canvasID: canvas.id, layerID: layer.id, stroke: stroke), on: &notebook)
        }
        for _ in 0..<40 {
            try history.undo(on: &notebook)
        }

        XCTAssertEqual(notebook.canvases[0].layers[0].objects.count, 10)
    }

    func testHandwritingConversionUndoRestoresExactOriginalStroke() throws {
        var notebook = DomainFixtures.notebook()
        var history = DocumentHistory()
        let canvas = notebook.canvases[0]
        let layer = canvas.layers[0]
        let originalStroke = try XCTUnwrap(layer.objects[0].strokeValue)
        let textBlock = TextBlock(
            id: ObjectID(),
            layerID: layer.id,
            text: "Discuss pricing",
            frame: originalStroke.bounds,
            fontSize: 18,
            alignment: .left
        )
        let operation = DocumentOperation.convertStrokesToText(
            canvasID: canvas.id,
            sourceObjects: [ObjectPlacement(layerID: layer.id, index: 0, object: .stroke(originalStroke))],
            textBlock: textBlock
        )

        try history.execute(operation, on: &notebook)
        XCTAssertEqual(notebook.canvases[0].layers[0].objects, [.text(textBlock)])

        try history.undo(on: &notebook)
        XCTAssertEqual(notebook.canvases[0].layers[0].objects, [.stroke(originalStroke)])
    }

    private func emptyNotebook() -> Notebook {
        Notebook(title: "Empty", canvases: [Canvas(title: "Canvas 1")])
    }
}
