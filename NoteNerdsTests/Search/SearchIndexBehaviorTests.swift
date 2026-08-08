import XCTest
@testable import NoteNerds

final class SearchIndexBehaviorTests: XCTestCase {
    func testSearchFindsTypedTextAndNavigatesToItsBounds() {
        var notebook = DomainFixtures.notebook()
        let layerID = notebook.canvases[0].layers[0].id
        let text = TextBlock(
            id: ObjectID(),
            layerID: layerID,
            text: "Quarterly pricing review",
            frame: CanvasRect(x: 80, y: 120, width: 260, height: 60),
            fontSize: 18,
            alignment: .left
        )
        notebook.canvases[0].layers[0].objects.append(.text(text))
        var index = LibrarySearchIndex()

        index.update(notebook)
        let result = index.search("pricing").first

        XCTAssertEqual(result?.notebookID, notebook.id)
        XCTAssertEqual(result?.canvasID, notebook.canvases[0].id)
        XCTAssertEqual(result?.bounds, text.frame)
        XCTAssertEqual(result?.matchType, .typedText)
    }

    func testRecognitionResultKeepsOriginalInkAndSourceStrokeNavigation() {
        let notebook = DomainFixtures.notebook()
        let stroke = notebook.canvases[0].layers[0].objects[0].strokeValue!
        let recognition = HandwritingRecognitionResult(
            text: "Discuss pricing with engineering",
            confidence: 0.94,
            bounds: stroke.bounds,
            sourceStrokeIDs: [stroke.id],
            recognizerVersion: "apple-v1"
        )
        var index = LibrarySearchIndex()

        index.update(notebook, recognitionResults: [notebook.canvases[0].id: [recognition]])
        let result = index.search("engineering").first

        XCTAssertEqual(result?.sourceStrokeIDs, [stroke.id])
        XCTAssertEqual(notebook.canvases[0].layers[0].objects[0], .stroke(stroke))
    }

    func testUpdatingOneNotebookLeavesOtherNotebookEntriesIntact() {
        let first = DomainFixtures.notebook(title: "Alpha planning")
        let second = Notebook(title: "Beta research", canvases: [Canvas(title: "Canvas 1")])
        var index = LibrarySearchIndex()
        index.update(first)
        index.update(second)

        var renamedFirst = first
        renamedFirst.title = "Gamma planning"
        index.update(renamedFirst)

        XCTAssertTrue(index.search("beta").contains { $0.notebookID == second.id })
        XCTAssertTrue(index.search("alpha").isEmpty)
    }

    func testIncrementalCanvasUpdatePreservesEntriesFromOtherCanvases() {
        var notebook = DomainFixtures.notebook()
        let secondLayerID = LayerID()
        let secondLayer = Layer(id: secondLayerID, name: "Text", objects: [
            .text(TextBlock(
                id: ObjectID(),
                layerID: secondLayerID,
                text: "Keep this result",
                frame: CanvasRect(x: 10, y: 10, width: 200, height: 60),
                fontSize: 17,
                alignment: .left
            ))
        ])
        notebook.canvases.append(Canvas(title: "Second", layers: [secondLayer]))
        var index = LibrarySearchIndex()
        index.update(notebook)
        notebook.canvases[0].layers[0].objects = []

        index.update(canvasID: notebook.canvases[0].id, in: notebook)

        XCTAssertTrue(index.search("keep this").contains { $0.canvasID == notebook.canvases[1].id })
    }

    func testRemovingNotebookClearsItsSearchEntries() {
        let notebook = DomainFixtures.notebook(title: "Remove this notebook")
        var index = LibrarySearchIndex()
        index.update(notebook)

        index.remove(notebookID: notebook.id)

        XCTAssertTrue(index.search("remove this").isEmpty)
    }

    func testTrashedNotebookIsExcludedFromSearch() {
        var notebook = DomainFixtures.notebook(title: "Archived result")
        var index = LibrarySearchIndex()
        index.update(notebook)
        notebook.trashedAt = DomainFixtures.fixedDate

        index.update(notebook)

        XCTAssertTrue(index.search("archived").isEmpty)
    }
}
