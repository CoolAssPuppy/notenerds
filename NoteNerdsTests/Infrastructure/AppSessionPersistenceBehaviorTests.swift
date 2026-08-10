import XCTest
@testable import NoteNerds

@MainActor
final class AppSessionPersistenceBehaviorTests: XCTestCase {
    func testNotebookDeepLinkOpensTheMatchingICloudNotebook() async throws {
        let notebook = Notebook(title: "Linked notebook", canvases: [Canvas(title: "Canvas 1")])
        let model = AppModel(automaticallyRestore: false)
        model.library = LibraryState(notebooks: [notebook])

        model.importExternalFile(
            at: URL(string: "notenerds://notebook/\(notebook.id.rawValue.uuidString.lowercased())")!
        )

        XCTAssertEqual(model.selectedNotebookID, notebook.id)
        XCTAssertNil(model.presentedError)
    }

    func testRestoreRepairsAndPersistsDuplicateCanvasIdentifiers() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        let original = Canvas(title: "Preserved canvas")
        let notebook = Notebook(title: "Legacy notebook", canvases: [original, original])
        try await repository.save(LibraryState(notebooks: [notebook]))
        try await documentStore.save(NativeNotebookPackage(schemaVersion: .current, notebook: notebook))

        let repairedSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            automaticallyRestore: false
        )
        await repairedSession.restoreLibrary()

        let repaired = try XCTUnwrap(repairedSession.notebook(notebook.id))
        XCTAssertEqual(repaired.canvases.map(\.title), ["Preserved canvas", "Preserved canvas"])
        XCTAssertEqual(Set(repaired.canvases.map(\.id)).count, 2)

        let nextSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            automaticallyRestore: false
        )
        await nextSession.restoreLibrary()

        let persisted = try XCTUnwrap(nextSession.notebook(notebook.id))
        XCTAssertEqual(persisted.canvases.map(\.id), repaired.canvases.map(\.id))
    }

    func testNotebookAndCanvasTextRestoreInANewApplicationModel() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        let firstSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            automaticallyRestore: false
        )
        await firstSession.restoreLibrary()
        firstSession.createNotebook()
        let notebookID = try XCTUnwrap(firstSession.selectedNotebookID)
        let notebook = try XCTUnwrap(firstSession.notebook(notebookID))
        let canvas = try XCTUnwrap(notebook.canvases.first)
        let layer = try XCTUnwrap(canvas.layers.first)
        firstSession.addTextBlock(
            TextBlockInsertion(
                text: "Saved between sessions",
                fontSize: 20,
                alignment: .left,
                fontName: nil,
                frame: CanvasRect(x: 100, y: 100, width: 300, height: 44),
                layerID: layer.id,
                canvasID: canvas.id
            ),
            notebookID: notebookID
        )
        firstSession.closeNotebook()
        await firstSession.checkpointDocuments()

        let nextSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            automaticallyRestore: false
        )
        await nextSession.restoreLibrary()

        let restored = try XCTUnwrap(nextSession.notebook(notebookID))
        let restoredText: [String] = restored.canvases[0].layers[0].objects.compactMap { object in
            guard case let .text(block) = object else { return nil }
            return block.text
        }
        XCTAssertEqual(restoredText, ["Saved between sessions"])
    }

    func testHandwritingAddedBeforeCheckpointCanBeSearchedAfterRestore() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        let phrase = "Searchable handwritten decision"
        let recognition = HandwritingRecognitionResult(
            text: phrase,
            confidence: 0.95,
            bounds: CanvasRect(x: 10, y: 20, width: 20, height: 20),
            sourceStrokeIDs: [],
            recognizerVersion: "test"
        )
        let firstSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: PersistenceHandwritingRecognizer(result: recognition)
            ),
            automaticallyRestore: false
        )
        await firstSession.restoreLibrary()
        firstSession.createNotebook()
        let notebookID = try XCTUnwrap(firstSession.selectedNotebookID)
        let canvas = try XCTUnwrap(firstSession.notebook(notebookID)?.canvases.first)
        let layer = try XCTUnwrap(canvas.layers.first)
        var stroke = DomainFixtures.stroke(id: StrokeID(), layerID: layer.id)
        stroke.samples[0].point = CanvasPoint(x: 10, y: 20)
        stroke.samples[1].point = CanvasPoint(x: 30, y: 40)
        firstSession.addStroke(stroke, to: notebookID, canvasID: canvas.id, layerID: layer.id)

        await firstSession.checkpointDocuments()

        let nextSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: PersistenceHandwritingRecognizer(result: recognition)
            ),
            automaticallyRestore: false
        )
        await nextSession.restoreLibrary()
        nextSession.searchQuery = "handwritten decision"

        let result = try await waitForHandwritingResult(in: nextSession, matching: phrase)
        XCTAssertEqual(result.matchType, .handwriting)
        XCTAssertEqual(result.notebookID, notebookID)
        XCTAssertEqual(result.canvasID, canvas.id)
    }

    func testReopeningANoteRecognizesSavedInkForSearch() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        let notebook = DomainFixtures.notebook(title: "Existing ink")
        let stroke = try XCTUnwrap(notebook.canvases[0].layers[0].objects[0].strokeValue)
        try await repository.save(LibraryState(notebooks: [notebook]))
        try await documentStore.save(NativeNotebookPackage(schemaVersion: .current, notebook: notebook))
        let phrase = "Recovered handwritten plan"
        let recognition = HandwritingRecognitionResult(
            text: phrase,
            confidence: 0.95,
            bounds: stroke.bounds,
            sourceStrokeIDs: [],
            recognizerVersion: "test"
        )
        let restoredSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: PersistenceHandwritingRecognizer(result: recognition)
            ),
            automaticallyRestore: false
        )

        await restoredSession.restoreLibrary()
        restoredSession.searchQuery = "handwritten plan"
        let result = try await waitForHandwritingResult(in: restoredSession, matching: phrase)

        XCTAssertEqual(result.matchType, .handwriting)
        XCTAssertEqual(result.notebookID, notebook.id)
        XCTAssertEqual(result.canvasID, notebook.canvases[0].id)
    }

    func testReopeningANoteReplacesStaleHandwritingSearchText() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        var notebook = DomainFixtures.notebook(title: "Changed ink")
        let canvas = notebook.canvases[0]
        let originalStroke = try XCTUnwrap(canvas.layers[0].objects[0].strokeValue)
        let staleResult = HandwritingRecognitionResult(
            text: "Old handwritten answer",
            confidence: 0.95,
            bounds: originalStroke.bounds,
            sourceStrokeIDs: [originalStroke.id],
            recognizerVersion: "test"
        )
        notebook.recognitionByCanvas[canvas.id] = [
            PersistedHandwritingRecognition(result: staleResult, sourceStrokes: [originalStroke])
        ]
        var changedStroke = originalStroke
        changedStroke.samples[0].point.x += 80
        notebook.canvases[0].layers[0].objects[0] = .stroke(changedStroke)
        try await repository.save(LibraryState(notebooks: [notebook]))
        try await documentStore.save(NativeNotebookPackage(schemaVersion: .current, notebook: notebook))
        let currentResult = HandwritingRecognitionResult(
            text: "Current handwritten answer",
            confidence: 0.95,
            bounds: changedStroke.bounds,
            sourceStrokeIDs: [changedStroke.id],
            recognizerVersion: "test"
        )
        let restoredSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: PersistenceHandwritingRecognizer(result: currentResult)
            ),
            automaticallyRestore: false
        )

        await restoredSession.restoreLibrary()
        restoredSession.searchQuery = "current handwritten"
        _ = try await waitForHandwritingResult(in: restoredSession, matching: currentResult.text)
        restoredSession.searchQuery = "old handwritten"

        XCTAssertTrue(restoredSession.searchResults.isEmpty)
    }

    func testReopeningANoteRetriesAnEmptyHandwritingRecognitionResult() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        var notebook = DomainFixtures.notebook(title: "Recognition retry")
        let canvas = notebook.canvases[0]
        notebook.recognitionByCanvas[canvas.id] = []
        try await repository.save(LibraryState(notebooks: [notebook]))
        try await documentStore.save(NativeNotebookPackage(schemaVersion: .current, notebook: notebook))
        let phrase = "Recovered after recognition retry"
        let recognition = HandwritingRecognitionResult(
            text: phrase,
            confidence: 0.95,
            bounds: CanvasRect(x: 10, y: 20, width: 20, height: 20),
            sourceStrokeIDs: [],
            recognizerVersion: "Vision-1"
        )
        let restoredSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: PersistenceHandwritingRecognizer(result: recognition)
            ),
            automaticallyRestore: false
        )

        await restoredSession.restoreLibrary()
        restoredSession.searchQuery = "recognition retry"
        let result = try await waitForHandwritingResult(in: restoredSession, matching: phrase)

        XCTAssertEqual(result.snippet, phrase)
        XCTAssertEqual(result.notebookID, notebook.id)
        XCTAssertEqual(result.canvasID, canvas.id)
    }

    func testReopeningANoteRefreshesRecognitionFromAnOlderRecognizerVersion() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        var notebook = DomainFixtures.notebook(title: "Recognition upgrade")
        let canvas = notebook.canvases[0]
        let stroke = try XCTUnwrap(canvas.layers[0].objects[0].strokeValue)
        let oldPhrase = "Vision one handwritten text"
        let oldRecognition = HandwritingRecognitionResult(
            text: oldPhrase,
            confidence: 0.95,
            bounds: stroke.bounds,
            sourceStrokeIDs: [stroke.id],
            recognizerVersion: "Vision-1"
        )
        notebook.recognitionByCanvas[canvas.id] = [
            PersistedHandwritingRecognition(result: oldRecognition, sourceStrokes: [stroke])
        ]
        try await repository.save(LibraryState(notebooks: [notebook]))
        try await documentStore.save(NativeNotebookPackage(schemaVersion: .current, notebook: notebook))
        let newPhrase = "Vision two handwritten text"
        let newRecognition = HandwritingRecognitionResult(
            text: newPhrase,
            confidence: 0.95,
            bounds: stroke.bounds,
            sourceStrokeIDs: [],
            recognizerVersion: "Vision-2"
        )
        let restoredSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: PersistenceHandwritingRecognizer(result: newRecognition)
            ),
            automaticallyRestore: false
        )

        await restoredSession.restoreLibrary()
        restoredSession.searchQuery = "Vision two"
        let result = try await waitForHandwritingResult(in: restoredSession, matching: newPhrase)
        restoredSession.searchQuery = "Vision one"

        XCTAssertEqual(result.snippet, newPhrase)
        XCTAssertTrue(restoredSession.searchResults.isEmpty)
    }

    func testJournaledInkChangeRefreshesRecognitionForTheRecoveredNotebook() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        var notebook = DomainFixtures.notebook(title: "Journal recovery")
        let canvas = notebook.canvases[0]
        let layer = canvas.layers[0]
        let strokeA = try XCTUnwrap(layer.objects[0].strokeValue)
        let oldPhrase = "Snapshot handwriting"
        let oldRecognition = recognitionResult(text: oldPhrase, strokes: [strokeA], version: "Vision-1")
        notebook.recognitionByCanvas[canvas.id] = [
            PersistedHandwritingRecognition(result: oldRecognition, sourceStrokes: [strokeA])
        ]
        try await repository.save(LibraryState(notebooks: [notebook]))
        try await documentStore.save(NativeNotebookPackage(schemaVersion: .current, notebook: notebook))
        var strokeB = DomainFixtures.stroke(id: StrokeID(), layerID: layer.id)
        strokeB.samples[0].point = CanvasPoint(x: 40, y: 20)
        strokeB.samples[1].point = CanvasPoint(x: 60, y: 40)
        let addStrokeB = DocumentOperation.replaceObjects(
            canvasID: canvas.id,
            before: [],
            after: [ObjectPlacement(layerID: layer.id, index: Int.max, object: .stroke(strokeB))]
        )
        try await documentStore.append(addStrokeB, notebookID: notebook.id)
        let currentPhrase = "Recovered journal handwriting"
        let currentRecognition = recognitionResult(
            text: currentPhrase,
            strokes: [strokeA, strokeB],
            version: "Vision-1"
        )
        let restoredSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: PersistenceHandwritingRecognizer(result: currentRecognition)
            ),
            automaticallyRestore: false
        )

        await restoredSession.restoreLibrary()
        restoredSession.searchQuery = "Recovered journal"
        let result = try await waitForHandwritingResult(in: restoredSession, matching: currentPhrase)
        restoredSession.searchQuery = "Snapshot handwriting"

        XCTAssertEqual(result.snippet, currentPhrase)
        XCTAssertTrue(restoredSession.searchResults.isEmpty)
        let restoredObjects = try XCTUnwrap(restoredSession.notebook(notebook.id)?.canvases[0].layers[0].objects)
        XCTAssertEqual(Set(restoredObjects.compactMap(\.strokeValue).map(\.id)), [strokeA.id, strokeB.id])
    }

    func testPlannerPaperAndRegionContentRestoreInANewApplicationModel() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        let firstSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            automaticallyRestore: false
        )
        await firstSession.restoreLibrary()
        firstSession.createNotebook()
        let notebookID = try XCTUnwrap(firstSession.selectedNotebookID)
        let initialCanvas = try XCTUnwrap(firstSession.notebook(notebookID)?.canvases.first)
        let today = try addPlannerContent(
            to: firstSession,
            notebookID: notebookID,
            canvas: initialCanvas
        )
        await firstSession.checkpointDocuments()

        let nextSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            automaticallyRestore: false
        )
        await nextSession.restoreLibrary()

        let restoredCanvas = try XCTUnwrap(nextSession.notebook(notebookID)?.canvases.first)
        XCTAssertEqual(restoredCanvas.template, .dailyPlanner)
        XCTAssertEqual(restoredCanvas.layers.flatMap(\.objects).count, 2)
        let restoredText = try XCTUnwrap(restoredCanvas.layers.flatMap(\.objects).compactMap { object -> TextBlock? in
            guard case let .text(text) = object else { return nil }
            return text
        }.first)
        XCTAssertLessThanOrEqual(restoredText.frame.maxX, today.frame.maxX)
        XCTAssertLessThanOrEqual(restoredText.frame.maxY, today.frame.maxY)
    }

    private func addPlannerContent(
        to session: AppModel,
        notebookID: NotebookID,
        canvas: Canvas
    ) throws -> CanvasRegion {
        session.changeTemplate(.dailyPlanner, notebookID: notebookID, canvasID: canvas.id)
        let today = try XCTUnwrap(
            PlannerRegionCatalog.regions(for: .dailyPlanner).first { $0.id == "today" }
        )
        let layerID = canvas.layers[0].id
        let textSession = CanvasTextEditingSession.new(
            layerID: layerID,
            insertionPoint: CanvasPoint(x: today.frame.maxX - 10, y: today.frame.minY + 80),
            constrainedTo: today.frame
        )
        session.addTextBlock(
            TextBlockInsertion(textBlock: textSession.textBlock, canvasID: canvas.id),
            notebookID: notebookID
        )
        var plannerStroke = DomainFixtures.stroke(layerID: layerID)
        plannerStroke.samples[0].point = CanvasPoint(
            x: today.frame.minX + today.frame.size.width / 2,
            y: today.frame.minY + today.frame.size.height / 2
        )
        plannerStroke.samples = [plannerStroke.samples[0]]
        session.addStroke(plannerStroke, to: notebookID, canvasID: canvas.id, layerID: layerID)
        return today
    }

    private func waitForHandwritingResult(
        in model: AppModel,
        matching phrase: String
    ) async throws -> LibrarySearchResult {
        for _ in 0..<100 {
            if let result = model.searchResults.first(where: { result in
                result.matchType == .handwriting && result.snippet == phrase
            }) {
                return result
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return try XCTUnwrap(model.searchResults.first { $0.matchType == .handwriting })
    }

    private func recognitionResult(
        text: String,
        strokes: [Stroke],
        version: String
    ) -> HandwritingRecognitionResult {
        HandwritingRecognitionResult(
            text: text,
            confidence: 0.95,
            bounds: CanvasRect.enclosing(strokes.flatMap { $0.samples.map(\.point) }),
            sourceStrokeIDs: Set(strokes.map(\.id)),
            recognizerVersion: version
        )
    }
}

private struct PersistenceHandwritingRecognizer: HandwritingRecognizer {
    let result: HandwritingRecognitionResult

    var recognizerVersion: String { result.recognizerVersion }

    func recognize(strokes: [Stroke]) async throws -> HandwritingRecognitionResult {
        var recognized = result
        recognized.bounds = CanvasRect.enclosing(strokes.flatMap { $0.samples.map(\.point) })
        recognized.sourceStrokeIDs = Set(strokes.map(\.id))
        return recognized
    }
}

private extension TextBlockInsertion {
    init(textBlock: TextBlock, canvasID: CanvasID) {
        self.init(
            text: textBlock.text,
            fontSize: textBlock.fontSize,
            alignment: textBlock.alignment,
            fontName: textBlock.fontName,
            frame: textBlock.frame,
            layerID: textBlock.layerID,
            canvasID: canvasID
        )
    }
}
