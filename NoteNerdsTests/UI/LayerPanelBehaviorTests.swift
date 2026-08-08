import XCTest
@testable import NoteNerds

@MainActor
final class LayerPanelBehaviorTests: XCTestCase {
    func testPanelShowsFrontmostLayerFirstAndKeepsAValidExplicitSelection() {
        let background = Layer(name: "Background")
        let notes = Layer(name: "Notes")
        let highlights = Layer(name: "Highlights")
        let presentation = LayerStackPresentation(
            layers: [background, notes, highlights],
            selectedLayerID: notes.id
        )

        XCTAssertEqual(presentation.displayedLayers.map(\.id), [highlights.id, notes.id, background.id])
        XCTAssertEqual(presentation.activeLayerID, notes.id)
    }

    func testMissingSelectionFallsBackToTheFrontmostLayer() {
        let background = Layer(name: "Background")
        let notes = Layer(name: "Notes")

        let presentation = LayerStackPresentation(layers: [background, notes], selectedLayerID: LayerID())

        XCTAssertEqual(presentation.activeLayerID, notes.id)
    }

    func testNewLayerIsInsertedImmediatelyAboveTheActiveLayer() {
        let background = Layer(name: "Background")
        let notes = Layer(name: "Notes")
        let highlights = Layer(name: "Highlights")
        let presentation = LayerStackPresentation(
            layers: [background, notes, highlights],
            selectedLayerID: notes.id
        )

        XCTAssertEqual(presentation.newLayerInsertionIndex, 2)
    }

    func testDeletingTheActiveLayerSelectsTheNearestRemainingLayer() {
        let background = Layer(name: "Background")
        let notes = Layer(name: "Notes")
        let highlights = Layer(name: "Highlights")
        let layers = [background, notes, highlights]

        XCTAssertEqual(
            LayerStackPresentation(layers: layers, selectedLayerID: notes.id)
                .activeLayerID(afterDeleting: notes.id),
            background.id
        )
        XCTAssertEqual(
            LayerStackPresentation(layers: layers, selectedLayerID: background.id)
                .activeLayerID(afterDeleting: background.id),
            notes.id
        )
    }

    func testPanelDragMapsFrontToBackRowsIntoDocumentStackIndices() {
        let background = Layer(name: "Background")
        let notes = Layer(name: "Notes")
        let highlights = Layer(name: "Highlights")
        let presentation = LayerStackPresentation(
            layers: [background, notes, highlights],
            selectedLayerID: highlights.id
        )

        XCTAssertEqual(
            presentation.layerMove(fromDisplayedOffsets: IndexSet(integer: 0), toDisplayedOffset: 3),
            LayerStackMove(sourceIndex: 2, destinationIndex: 0)
        )
        XCTAssertEqual(
            presentation.layerMove(fromDisplayedOffsets: IndexSet(integer: 2), toDisplayedOffset: 0),
            LayerStackMove(sourceIndex: 0, destinationIndex: 2)
        )
    }

    func testCreatingALayerInsertsItAboveTheActiveLayerAndReturnsItsIdentifier() throws {
        let background = Layer(name: "Background")
        let notes = Layer(name: "Notes")
        let highlights = Layer(name: "Highlights")
        let canvas = Canvas(title: "Page 1", layers: [background, notes, highlights])
        let notebook = Notebook(title: "Notebook", canvases: [canvas])
        let model = makeModel(notebook: notebook)

        let insertedID = try XCTUnwrap(
            model.addLayer(to: canvas.id, in: notebook.id, at: 2)
        )

        let layers = try XCTUnwrap(model.notebook(notebook.id)?.canvases.first?.layers)
        XCTAssertEqual(layers.map(\.name), ["Background", "Notes", "Layer 1", "Highlights"])
        XCTAssertEqual(layers[2].id, insertedID)
    }

    func testPastingIntoAnActiveLayerMovesEveryPastedObjectToThatLayer() throws {
        let background = Layer(name: "Background")
        let notes = Layer(name: "Notes")
        let canvas = Canvas(title: "Page 1", layers: [background, notes])
        let notebook = Notebook(title: "Notebook", canvases: [canvas])
        let model = makeModel(notebook: notebook)
        let pastedText = TextBlock(
            id: ObjectID(),
            layerID: background.id,
            text: "Copied note",
            frame: CanvasRect(x: 10, y: 10, width: 120, height: 40),
            fontSize: 18,
            alignment: .left
        )

        model.pasteObjects(
            [.text(pastedText)],
            notebookID: notebook.id,
            canvasID: canvas.id,
            layerID: notes.id
        )

        let layers = try XCTUnwrap(model.notebook(notebook.id)?.canvases.first?.layers)
        XCTAssertTrue(layers[0].objects.isEmpty)
        XCTAssertEqual(layers[1].objects.first?.layerID, notes.id)
    }

    func testPencilKitChangesOnlyReplaceStrokesOnTheActiveLayer() throws {
        let backgroundID = LayerID()
        let notesID = LayerID()
        let backgroundStroke = DomainFixtures.stroke(id: StrokeID(), layerID: backgroundID)
        let notesStroke = DomainFixtures.stroke(id: StrokeID(), layerID: notesID)
        let background = Layer(
            id: backgroundID,
            name: "Background",
            objects: [.stroke(backgroundStroke)]
        )
        let notes = Layer(id: notesID, name: "Notes", objects: [.stroke(notesStroke)])
        let canvas = Canvas(title: "Page 1", layers: [background, notes])
        let notebook = Notebook(title: "Notebook", canvases: [canvas])
        let model = makeModel(notebook: notebook)

        model.replaceVisibleStrokes(
            [notesStroke],
            in: notebook.id,
            canvasID: canvas.id,
            layerID: notesID
        )

        let layers = try XCTUnwrap(model.notebook(notebook.id)?.canvases.first?.layers)
        XCTAssertEqual(layers[0].objects, [.stroke(backgroundStroke)])
        XCTAssertEqual(layers[1].objects, [.stroke(notesStroke)])
        XCTAssertFalse(model.histories[notebook.id]?.canUndo ?? false)
    }

    private func makeModel(notebook: Notebook) -> AppModel {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "library.json")
        let model = AppModel(
            repository: LocalLibraryRepository(fileURL: fileURL),
            automaticallyRestore: false
        )
        model.library = LibraryState(notebooks: [notebook])
        return model
    }
}
