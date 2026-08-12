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

    @MainActor
    func testEditingRecognizedInkRemovesTheOldSearchResult() throws {
        var notebook = DomainFixtures.notebook()
        let canvas = notebook.canvases[0]
        let layer = canvas.layers[0]
        let stroke = try XCTUnwrap(layer.objects[0].strokeValue)
        let recognition = HandwritingRecognitionResult(
            text: "Original project estimate",
            confidence: 0.94,
            bounds: stroke.bounds,
            sourceStrokeIDs: [stroke.id],
            recognizerVersion: "test"
        )
        notebook.recognitionByCanvas[canvas.id] = [
            PersistedHandwritingRecognition(result: recognition, sourceStrokes: [stroke])
        ]
        let model = AppModel(recognitionDelay: .milliseconds(10), automaticallyRestore: false)
        model.library = LibraryState(notebooks: [notebook])
        model.refreshSearchIndex(for: notebook.id)
        model.searchQuery = "project estimate"
        XCTAssertEqual(model.searchResults.first?.matchType, .handwriting)
        var changedStroke = stroke
        changedStroke.samples[0].point.x += 40

        model.replaceVisibleStrokes(
            [changedStroke],
            in: notebook.id,
            canvasID: canvas.id,
            layerID: layer.id
        )

        XCTAssertTrue(model.searchResults.isEmpty)
    }

    @MainActor
    func testConvertingRecognizedInkRemovesTheOldHandwritingResult() async throws {
        var notebook = DomainFixtures.notebook()
        let canvas = notebook.canvases[0]
        let stroke = try XCTUnwrap(canvas.layers[0].objects[0].strokeValue)
        let phrase = "Converted project estimate"
        let recognition = HandwritingRecognitionResult(
            text: phrase,
            confidence: 0.94,
            bounds: stroke.bounds,
            sourceStrokeIDs: [stroke.id],
            recognizerVersion: "test"
        )
        notebook.recognitionByCanvas[canvas.id] = [
            PersistedHandwritingRecognition(result: recognition, sourceStrokes: [stroke])
        ]
        let model = AppModel(
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: SearchHandwritingRecognizer(result: recognition)
            ),
            recognitionDelay: .milliseconds(10),
            automaticallyRestore: false
        )
        model.library = LibraryState(notebooks: [notebook])
        model.refreshSearchIndex(for: notebook.id)
        model.searchQuery = "converted project"

        model.convertStrokesToText([stroke.id], in: notebook.id, canvasID: canvas.id)
        for _ in 0..<100 where model.searchResults.allSatisfy({ $0.matchType != .typedText }) {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertTrue(model.searchResults.contains { $0.matchType == .typedText })
        XCTAssertFalse(model.searchResults.contains { $0.matchType == .handwriting })
    }

    @MainActor
    func testDeletingARecognizedCanvasRemovesItsHandwritingResult() throws {
        var notebook = DomainFixtures.notebook()
        let canvas = notebook.canvases[0]
        let stroke = try XCTUnwrap(canvas.layers[0].objects[0].strokeValue)
        let recognition = HandwritingRecognitionResult(
            text: "Delete canvas transcript",
            confidence: 0.94,
            bounds: stroke.bounds,
            sourceStrokeIDs: [stroke.id],
            recognizerVersion: "test"
        )
        notebook.recognitionByCanvas[canvas.id] = [
            PersistedHandwritingRecognition(result: recognition, sourceStrokes: [stroke])
        ]
        notebook.canvases.append(Canvas(title: "Canvas 2"))
        let model = AppModel(recognitionDelay: .milliseconds(10), automaticallyRestore: false)
        model.library = LibraryState(notebooks: [notebook])
        model.refreshSearchIndex(for: notebook.id)
        model.searchQuery = "canvas transcript"
        XCTAssertEqual(model.searchResults.first?.canvasID, canvas.id)

        model.deleteCanvas(canvas.id, in: notebook.id)

        XCTAssertTrue(model.searchResults.isEmpty)
        XCTAssertNil(model.notebook(notebook.id)?.recognitionByCanvas[canvas.id])
    }

    @MainActor
    func testDeletingRecognizedInkRemovesItsHandwritingResult() throws {
        var notebook = DomainFixtures.notebook()
        let canvas = notebook.canvases[0]
        let stroke = try XCTUnwrap(canvas.layers[0].objects[0].strokeValue)
        let recognition = HandwritingRecognitionResult(
            text: "Delete selected handwriting",
            confidence: 0.94,
            bounds: stroke.bounds,
            sourceStrokeIDs: [stroke.id],
            recognizerVersion: "test"
        )
        notebook.recognitionByCanvas[canvas.id] = [
            PersistedHandwritingRecognition(result: recognition, sourceStrokes: [stroke])
        ]
        let model = AppModel(recognitionDelay: .milliseconds(10), automaticallyRestore: false)
        model.library = LibraryState(notebooks: [notebook])
        model.refreshSearchIndex(for: notebook.id)
        model.searchQuery = "selected handwriting"

        model.deleteObjects([stroke.objectID], notebookID: notebook.id, canvasID: canvas.id)

        XCTAssertTrue(model.searchResults.isEmpty)
        XCTAssertTrue(model.notebook(notebook.id)?.canvases[0].layers[0].objects.isEmpty == true)
    }

    @MainActor
    func testDeletingInkWhileConversionRunsDoesNotInsertStaleText() async throws {
        let notebook = DomainFixtures.notebook()
        let canvas = notebook.canvases[0]
        let stroke = try XCTUnwrap(canvas.layers[0].objects[0].strokeValue)
        let phrase = "Text from deleted ink"
        let recognizer = FirstCallPausingSearchRecognizer(result: HandwritingRecognitionResult(
            text: phrase,
            confidence: 0.94,
            bounds: stroke.bounds,
            sourceStrokeIDs: [stroke.id],
            recognizerVersion: "test"
        ))
        let model = AppModel(
            recognitionCoordinator: HandwritingRecognitionCoordinator(recognizer: recognizer),
            recognitionDelay: .milliseconds(10),
            automaticallyRestore: false
        )
        model.library = LibraryState(notebooks: [notebook])
        model.searchQuery = "deleted ink"

        model.convertStrokesToText([stroke.id], in: notebook.id, canvasID: canvas.id)
        await recognizer.waitUntilPaused()
        model.deleteObjects([stroke.objectID], notebookID: notebook.id, canvasID: canvas.id)
        await recognizer.finish()
        try await Task.sleep(for: .milliseconds(100))

        let objects = try XCTUnwrap(model.notebook(notebook.id)?.canvases[0].layers[0].objects)
        XCTAssertTrue(objects.isEmpty)
        XCTAssertTrue(model.searchResults.isEmpty)
    }

    @MainActor
    func testMovingStrokeLayersDuringRecognitionStillProducesSearchText() async throws {
        let firstLayer = Layer(name: "First", objects: [
            .stroke(DomainFixtures.stroke(layerID: LayerID()))
        ])
        var firstStroke = try XCTUnwrap(firstLayer.objects[0].strokeValue)
        firstStroke.layerID = firstLayer.id
        let secondLayer = Layer(name: "Second")
        let canvas = Canvas(title: "Canvas 1", layers: [
            Layer(id: firstLayer.id, name: firstLayer.name, objects: [.stroke(firstStroke)]),
            secondLayer
        ])
        let notebook = Notebook(title: "Layer order", canvases: [canvas])
        let addedStroke = DomainFixtures.stroke(id: StrokeID(), layerID: secondLayer.id)
        let phrase = "Layer order handwriting"
        let recognizer = FirstCallPausingSearchRecognizer(result: HandwritingRecognitionResult(
            text: phrase,
            confidence: 0.94,
            bounds: addedStroke.bounds,
            sourceStrokeIDs: [firstStroke.id, addedStroke.id],
            recognizerVersion: "test"
        ))
        let model = AppModel(
            recognitionCoordinator: HandwritingRecognitionCoordinator(recognizer: recognizer),
            recognitionDelay: .milliseconds(10),
            automaticallyRestore: false
        )
        model.library = LibraryState(notebooks: [notebook])
        model.searchQuery = "layer order"

        _ = model.addStrokes(
            [addedStroke],
            to: notebook.id,
            canvasID: canvas.id,
            layerID: secondLayer.id
        )
        await recognizer.waitUntilPaused()
        model.moveLayer(from: 0, to: 1, canvasID: canvas.id, notebookID: notebook.id)
        await recognizer.finish()
        for _ in 0..<100 where !model.searchResults.contains(where: { $0.matchType == .handwriting }) {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertTrue(model.searchResults.contains { result in
            result.matchType == .handwriting && result.snippet == phrase
        })
    }
}

private struct SearchHandwritingRecognizer: HandwritingRecognizer {
    let result: HandwritingRecognitionResult

    func recognize(strokes: [Stroke]) async throws -> HandwritingRecognitionResult { result }
}

private actor FirstCallPausingSearchRecognizer: HandwritingRecognizer {
    let result: HandwritingRecognitionResult
    private var isPaused = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<Void, Never>?

    init(result: HandwritingRecognitionResult) {
        self.result = result
    }

    func recognize(strokes: [Stroke]) async throws -> HandwritingRecognitionResult {
        if !isPaused {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                isPaused = true
                pauseWaiters.forEach { $0.resume() }
                pauseWaiters.removeAll()
            }
        }
        return result
    }

    func waitUntilPaused() async {
        guard !isPaused else { return }
        await withCheckedContinuation { pauseWaiters.append($0) }
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}
