import XCTest
@testable import NoteNerds

final class HandwritingSearchRecoveryBehaviorTests: XCTestCase {
    @MainActor
    func testRestoringATrashedNotebookMakesItsHandwritingSearchable() async throws {
        var notebook = DomainFixtures.notebook(title: "Restored from Trash")
        notebook.trashedAt = DomainFixtures.fixedDate
        let phrase = "Restored notebook handwriting"
        let model = AppModel(
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: RecoveryHandwritingRecognizer(text: phrase)
            ),
            automaticallyRestore: false
        )
        model.library = LibraryState(notebooks: [notebook])
        model.searchQuery = phrase

        model.restore(notebook.id)
        let result = try await waitForSearchResult(in: model, notebookID: notebook.id)

        XCTAssertEqual(result.matchType, .handwriting)
        XCTAssertNil(model.notebook(notebook.id)?.trashedAt)
    }

    @MainActor
    func testRestoringAFolderMakesItsNotebooksHandwritingSearchable() async throws {
        let (folder, notebook) = trashedNotebookInFolder()
        let phrase = "Restored folder handwriting"
        let model = AppModel(
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: RecoveryHandwritingRecognizer(text: phrase)
            ),
            automaticallyRestore: false
        )
        model.library = LibraryState(folders: [folder], notebooks: [notebook])
        model.searchQuery = phrase

        model.restoreFolder(folder.id)
        let result = try await waitForSearchResult(in: model, notebookID: notebook.id)

        XCTAssertEqual(result.matchType, .handwriting)
    }

    @MainActor
    func testRestoringSelectedItemsMakesTheirHandwritingSearchable() async throws {
        let (folder, notebook) = trashedNotebookInFolder()
        let phrase = "Restored selected handwriting"
        let model = AppModel(
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: RecoveryHandwritingRecognizer(text: phrase)
            ),
            automaticallyRestore: false
        )
        model.library = LibraryState(folders: [folder], notebooks: [notebook])
        model.searchQuery = phrase

        model.restoreItems([.notebook(notebook.id)])
        let result = try await waitForSearchResult(in: model, notebookID: notebook.id)

        XCTAssertEqual(result.matchType, .handwriting)
    }

    @MainActor
    func testTrashingANotebookWhileRecognitionRunsDoesNotSaveSearchMetadata() async throws {
        let notebook = DomainFixtures.notebook(title: "Trashed during recognition")
        let canvasID = notebook.canvases[0].id
        let recognizer = PausingRecoveryHandwritingRecognizer(text: "Discarded handwriting")
        let model = AppModel(
            recognitionCoordinator: HandwritingRecognitionCoordinator(recognizer: recognizer),
            automaticallyRestore: false
        )
        model.library = LibraryState(notebooks: [notebook])
        model.searchQuery = "Discarded handwriting"

        model.refreshHandwritingSearch(in: notebook.id)
        await recognizer.waitUntilPaused()
        model.delete(notebook.id)
        await recognizer.finish()
        try await waitForBackfillToFinish(in: model)

        XCTAssertNil(model.notebook(notebook.id)?.recognitionByCanvas[canvasID])
        XCTAssertTrue(model.searchResults.isEmpty)
    }

    @MainActor
    func testTrashingANotebookPersistsItsTrashStateAcrossRelaunch() async throws {
        let notebook = hiddenInkNotebook(title: "Persisted Trash")
        let fixture = try await makePersistenceFixture(library: LibraryState(notebooks: [notebook]))
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let model = await restoredModel(from: fixture)

        model.delete(notebook.id)
        try await waitForStoredTrashState(true, notebookID: notebook.id, fixture: fixture)
        let reopenedModel = await restoredModel(from: fixture)

        XCTAssertNotNil(reopenedModel.notebook(notebook.id)?.trashedAt)
    }

    @MainActor
    func testRestoringANotebookPersistsItsActiveStateAcrossRelaunch() async throws {
        var notebook = hiddenInkNotebook(title: "Persisted restore")
        notebook.trashedAt = DomainFixtures.fixedDate
        let fixture = try await makePersistenceFixture(library: LibraryState(notebooks: [notebook]))
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let model = await restoredModel(from: fixture)

        model.restore(notebook.id)
        try await waitForStoredTrashState(false, notebookID: notebook.id, fixture: fixture)
        let reopenedModel = await restoredModel(from: fixture)

        XCTAssertNil(reopenedModel.notebook(notebook.id)?.trashedAt)
    }

    @MainActor
    func testRestoringAFolderPersistsEveryContainedNotebookAcrossRelaunch() async throws {
        let folder = Folder(
            name: "Persisted folder restore",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        let notebooks = [
            hiddenInkNotebook(title: "First restored notebook", parentFolderID: folder.id),
            hiddenInkNotebook(title: "Second restored notebook", parentFolderID: folder.id)
        ]
        var library = LibraryState(folders: [folder], notebooks: notebooks)
        try library.moveFolderToTrash(folder.id, at: DomainFixtures.fixedDate)
        let fixture = try await makePersistenceFixture(library: library)
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let model = await restoredModel(from: fixture)

        model.restoreFolder(folder.id)
        for notebook in notebooks {
            try await waitForStoredTrashState(false, notebookID: notebook.id, fixture: fixture)
        }
        let reopenedModel = await restoredModel(from: fixture)

        XCTAssertNil(reopenedModel.library.folder(id: folder.id)?.trashedAt)
        for notebook in notebooks {
            XCTAssertNil(reopenedModel.notebook(notebook.id)?.trashedAt)
        }
    }

    @MainActor
    func testRestoringSelectedItemsPersistsEveryNotebookAcrossRelaunch() async throws {
        let notebooks = [
            hiddenInkNotebook(title: "First selected restore"),
            hiddenInkNotebook(title: "Second selected restore")
        ]
        let selectedItems = Set(notebooks.map { LibraryItemID.notebook($0.id) })
        var library = LibraryState(notebooks: notebooks)
        try library.moveItemsToTrash(selectedItems, at: DomainFixtures.fixedDate)
        let fixture = try await makePersistenceFixture(library: library)
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let model = await restoredModel(from: fixture)

        model.restoreItems(selectedItems)
        for notebook in notebooks {
            try await waitForStoredTrashState(false, notebookID: notebook.id, fixture: fixture)
        }
        let reopenedModel = await restoredModel(from: fixture)

        for notebook in notebooks {
            XCTAssertNil(reopenedModel.notebook(notebook.id)?.trashedAt)
        }
    }

    @MainActor
    func testRestoreSavesOneRecognitionUpdateForSeveralCanvasesInOneNotebook() async throws {
        let canvases = (1...3).map { index in
            var canvas = DomainFixtures.notebook().canvases[0].duplicated(at: DomainFixtures.fixedDate)
            canvas.title = "Canvas \(index)"
            return canvas
        }
        let notebook = Notebook(title: "Backfill", canvases: canvases)
        let repository = CountingHandwritingRepository(library: LibraryState(notebooks: [notebook]))
        let model = AppModel(
            repository: repository,
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: RecoveryHandwritingRecognizer(text: "Recovered handwriting")
            ),
            automaticallyRestore: false
        )

        await model.restoreLibrary()
        try await waitForRecognition(in: model, notebookID: notebook.id, canvasCount: 3)
        await model.checkpointDocuments()
        let saveCount = await repository.saveCount

        XCTAssertEqual(saveCount, 1)
    }

    @MainActor
    func testDuplicatingANotebookMakesItsHandwritingSearchable() async throws {
        let notebook = DomainFixtures.notebook(title: "Original")
        let model = AppModel(
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: RecoveryHandwritingRecognizer(text: "Duplicated handwriting")
            ),
            automaticallyRestore: false
        )
        model.library = LibraryState(notebooks: [notebook])
        model.searchQuery = "Duplicated handwriting"

        model.duplicateNotebook(notebook.id)
        let duplicate = try XCTUnwrap(model.library.notebooks.first { $0.id != notebook.id })
        let result = try await waitForSearchResult(in: model, notebookID: duplicate.id)

        XCTAssertEqual(result.matchType, .handwriting)
    }

    @MainActor
    func testNotionRestoreMakesRestoredHandwritingSearchable() async throws {
        let notebook = DomainFixtures.notebook(title: "Restored")
        let repository = CountingHandwritingRepository()
        let model = AppModel(
            repository: repository,
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: RecoveryHandwritingRecognizer(text: "Notion restored handwriting")
            ),
            automaticallyRestore: false
        )
        model.searchQuery = "Notion restored handwriting"

        await model.replaceLibraryAfterNotionRestore(LibraryState(notebooks: [notebook]))
        let result = try await waitForSearchResult(in: model, notebookID: notebook.id)

        XCTAssertEqual(result.matchType, .handwriting)
    }

    @MainActor
    func testImportRefreshesHandwritingFromAnOlderRecognizerVersion() async throws {
        let archiveURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        var notebook = DomainFixtures.notebook(title: "Imported")
        let canvas = notebook.canvases[0]
        let stroke = try XCTUnwrap(canvas.layers[0].objects[0].strokeValue)
        let oldRecognition = HandwritingRecognitionResult(
            text: "Old imported words",
            confidence: 0.95,
            bounds: stroke.bounds,
            sourceStrokeIDs: [stroke.id],
            recognizerVersion: "Vision-1"
        )
        notebook.recognitionByCanvas[canvas.id] = [
            PersistedHandwritingRecognition(result: oldRecognition, sourceStrokes: [stroke])
        ]
        try NativeNotebookArchive().write(
            package: NativeNotebookPackage(schemaVersion: .current, notebook: notebook),
            assets: [],
            to: archiveURL
        )
        let model = AppModel(
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: RecoveryHandwritingRecognizer(
                    text: "Current imported handwriting",
                    recognizerVersion: "Vision-2"
                )
            ),
            automaticallyRestore: false
        )
        model.searchQuery = "Current imported handwriting"

        model.importExternalFile(at: archiveURL)
        let result = try await waitForSearchResult(in: model, notebookID: notebook.id)
        model.searchQuery = "Old imported words"

        XCTAssertEqual(result.matchType, .handwriting)
        XCTAssertTrue(model.searchResults.isEmpty)
    }

    @MainActor
    func testRecoveryRebuildsRecognitionWithDuplicateStrokeIDsWithoutTrapping() async throws {
        var notebook = DomainFixtures.notebook(title: "Duplicate stroke recovery")
        let canvasID = notebook.canvases[0].id
        let sourceStroke = try XCTUnwrap(notebook.canvases[0].layers[0].objects[0].strokeValue)
        var duplicateStroke = sourceStroke
        duplicateStroke.samples[0].point.x += 4
        notebook.canvases[0].layers[0].objects.append(.stroke(duplicateStroke))
        let oldRecognition = HandwritingRecognitionResult(
            text: "Old duplicate words",
            confidence: 0.95,
            bounds: sourceStroke.bounds,
            sourceStrokeIDs: [sourceStroke.id],
            recognizerVersion: "Vision-1"
        )
        notebook.recognitionByCanvas[canvasID] = [
            PersistedHandwritingRecognition(result: oldRecognition, sourceStrokes: [sourceStroke])
        ]
        let phrase = "Rebuilt duplicate handwriting"
        let model = AppModel(
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: RecoveryHandwritingRecognizer(
                    text: phrase,
                    recognizerVersion: "Vision-2"
                )
            ),
            automaticallyRestore: false
        )
        model.library = LibraryState(notebooks: [notebook])
        model.searchQuery = phrase

        model.refreshHandwritingSearch(in: notebook.id)
        let result = try await waitForSearchResult(in: model, notebookID: notebook.id)

        XCTAssertEqual(result.matchType, .handwriting)
        XCTAssertEqual(result.snippet, phrase)
    }

    @MainActor
    private func waitForRecognition(
        in model: AppModel,
        notebookID: NotebookID,
        canvasCount: Int
    ) async throws {
        for _ in 0..<150 {
            if model.notebook(notebookID)?.recognitionByCanvas.count == canvasCount { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Expected every canvas to be recognized")
    }

    private func trashedNotebookInFolder() -> (Folder, Notebook) {
        let folder = Folder(
            name: "Archived notes",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate,
            trashedAt: DomainFixtures.fixedDate
        )
        var notebook = DomainFixtures.notebook(title: "Archived handwriting")
        notebook.parentFolderID = folder.id
        notebook.trashedAt = DomainFixtures.fixedDate
        return (folder, notebook)
    }

    private func hiddenInkNotebook(
        title: String,
        parentFolderID: FolderID? = nil
    ) -> Notebook {
        var notebook = DomainFixtures.notebook(id: NotebookID(), title: title)
        notebook.parentFolderID = parentFolderID
        notebook.canvases[0].layers[0].isVisible = false
        return notebook
    }

    @MainActor
    private func makePersistenceFixture(
        library: LibraryState
    ) async throws -> HandwritingRecoveryPersistenceFixture {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        try await repository.save(library)
        for notebook in library.notebooks {
            try await documentStore.save(NativeNotebookPackage(schemaVersion: .current, notebook: notebook))
        }
        return HandwritingRecoveryPersistenceFixture(
            directoryURL: directoryURL,
            repository: repository,
            documentStore: documentStore
        )
    }

    @MainActor
    private func restoredModel(
        from fixture: HandwritingRecoveryPersistenceFixture
    ) async -> AppModel {
        let model = AppModel(
            repository: fixture.repository,
            documentStore: fixture.documentStore,
            automaticallyRestore: false
        )
        await model.restoreLibrary()
        return model
    }

    @MainActor
    private func waitForStoredTrashState(
        _ isTrashed: Bool,
        notebookID: NotebookID,
        fixture: HandwritingRecoveryPersistenceFixture
    ) async throws {
        for _ in 0..<100 {
            let package = try await fixture.documentStore.load(notebookID: notebookID)
            let library = try await fixture.repository.load()
            let isDocumentTrashed = package.notebook.trashedAt != nil
            let isLibraryTrashed = library.notebook(id: notebookID)?.trashedAt != nil
            if isDocumentTrashed == isTrashed, isLibraryTrashed == isTrashed { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        let package = try await fixture.documentStore.load(notebookID: notebookID)
        let library = try await fixture.repository.load()
        XCTAssertEqual(package.notebook.trashedAt != nil, isTrashed)
        XCTAssertEqual(library.notebook(id: notebookID)?.trashedAt != nil, isTrashed)
    }

    @MainActor
    private func waitForSearchResult(
        in model: AppModel,
        notebookID: NotebookID
    ) async throws -> LibrarySearchResult {
        for _ in 0..<150 {
            if let result = model.searchResults.first(where: { result in
                result.notebookID == notebookID && result.matchType == .handwriting
            }) {
                return result
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return try XCTUnwrap(model.searchResults.first { $0.notebookID == notebookID })
    }

    @MainActor
    private func waitForBackfillToFinish(in model: AppModel) async throws {
        for _ in 0..<150 {
            if model.recognitionBackfillTask == nil { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Expected handwriting backfill to finish")
    }
}

private struct HandwritingRecoveryPersistenceFixture {
    let directoryURL: URL
    let repository: LocalLibraryRepository
    let documentStore: LocalDocumentStore
}

private struct RecoveryHandwritingRecognizer: HandwritingRecognizer {
    let text: String
    var recognizerVersion = "test"

    func recognize(strokes: [Stroke]) async throws -> HandwritingRecognitionResult {
        HandwritingRecognitionResult(
            text: text,
            confidence: 0.95,
            bounds: CanvasRect.enclosing(strokes.flatMap { $0.samples.map(\.point) }),
            sourceStrokeIDs: Set(strokes.map(\.id)),
            recognizerVersion: recognizerVersion
        )
    }
}

private actor CountingHandwritingRepository: LibraryRepository {
    private var library: LibraryState
    private(set) var saveCount = 0

    init(library: LibraryState = LibraryState()) {
        self.library = library
    }

    func load() async throws -> LibraryState { library }

    func save(_ library: LibraryState) async throws {
        self.library = library
        saveCount += 1
    }
}

private actor PausingRecoveryHandwritingRecognizer: HandwritingRecognizer {
    let text: String
    private var isPaused = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var recognitionContinuation: CheckedContinuation<Void, Never>?

    init(text: String) {
        self.text = text
    }

    func recognize(strokes: [Stroke]) async throws -> HandwritingRecognitionResult {
        await withCheckedContinuation { continuation in
            recognitionContinuation = continuation
            isPaused = true
            pauseWaiters.forEach { $0.resume() }
            pauseWaiters.removeAll()
        }
        return HandwritingRecognitionResult(
            text: text,
            confidence: 0.95,
            bounds: CanvasRect.enclosing(strokes.flatMap { $0.samples.map(\.point) }),
            sourceStrokeIDs: Set(strokes.map(\.id)),
            recognizerVersion: "test"
        )
    }

    func waitUntilPaused() async {
        guard !isPaused else { return }
        await withCheckedContinuation { pauseWaiters.append($0) }
    }

    func finish() {
        recognitionContinuation?.resume()
        recognitionContinuation = nil
    }
}
