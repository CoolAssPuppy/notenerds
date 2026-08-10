import XCTest
@testable import NoteNerds

@MainActor
final class RemoteHandwritingSyncTests: XCTestCase {
    // swiftlint:disable:next function_body_length
    func testRemoteHandwritingDeletionIsSavedBeforeAcknowledgementAndRelaunch() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        let provider = InMemorySyncProvider()
        let stateStore = InMemorySyncStateStore()
        var notebook = DomainFixtures.notebook(title: "Remote handwriting")
        let canvas = notebook.canvases[0]
        let stroke = try XCTUnwrap(canvas.layers[0].objects[0].strokeValue)
        let recognition = HandwritingRecognitionResult(
            text: "Remote deletion must stay deleted",
            confidence: 0.95,
            bounds: stroke.bounds,
            sourceStrokeIDs: [stroke.id],
            recognizerVersion: "test"
        )
        notebook.recognitionByCanvas[canvas.id] = [
            PersistedHandwritingRecognition(result: recognition, sourceStrokes: [stroke])
        ]
        try await repository.save(LibraryState(notebooks: [notebook]))
        try await documentStore.save(NativeNotebookPackage(schemaVersion: .current, notebook: notebook))
        let receivingSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            syncProvider: provider,
            syncStateStore: stateStore,
            deviceID: "receiving-device",
            automaticallyRestore: false
        )
        await receivingSession.restoreLibrary()
        let operation = try DocumentOperation.deleteObjects(
            in: notebook,
            canvasID: canvas.id,
            objectIDs: [stroke.objectID]
        )
        let remoteChange = try SyncChangeEncoder(deviceID: "remote-device").change(
            for: operation,
            notebookID: notebook.id,
            sequence: 1,
            timestamp: DomainFixtures.fixedDate.addingTimeInterval(1)
        )
        try await provider.push([remoteChange])

        await receivingSession.synchronize()

        XCTAssertFalse(receivingSession.notebook(notebook.id)?.containsStroke(stroke.id) == true)
        let acknowledgedState = await stateStore.load()
        XCTAssertTrue(acknowledgedState?.receivedChanges.isEmpty == true)
        let reopenedSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            syncProvider: provider,
            syncStateStore: stateStore,
            deviceID: "receiving-device",
            automaticallyRestore: false
        )
        await reopenedSession.restoreLibrary()
        reopenedSession.searchQuery = "remote deletion"

        XCTAssertFalse(reopenedSession.notebook(notebook.id)?.containsStroke(stroke.id) == true)
        XCTAssertTrue(reopenedSession.searchResults.isEmpty)
    }

    func testRemoteDocumentChangeStaysQueuedWhenDocumentSaveFails() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let blockedDocumentURL = directoryURL.appending(path: "Documents")
        let notebook = DomainFixtures.notebook(title: "Unsaved remote document")
        try await repository.save(LibraryState(notebooks: [notebook]))
        try Data().write(to: blockedDocumentURL)
        let provider = InMemorySyncProvider()
        let stateStore = InMemorySyncStateStore()
        let canvas = notebook.canvases[0]
        let stroke = try XCTUnwrap(canvas.layers[0].objects[0].strokeValue)
        let operation = try DocumentOperation.deleteObjects(
            in: notebook,
            canvasID: canvas.id,
            objectIDs: [stroke.objectID]
        )
        let remoteChange = try SyncChangeEncoder(deviceID: "remote-device").change(
            for: operation,
            notebookID: notebook.id,
            sequence: 1,
            timestamp: DomainFixtures.fixedDate.addingTimeInterval(1)
        )
        try await provider.push([remoteChange])
        let model = AppModel(
            repository: repository,
            documentStore: LocalDocumentStore(rootURL: blockedDocumentURL),
            syncProvider: provider,
            syncStateStore: stateStore,
            deviceID: "receiving-device",
            automaticallyRestore: false
        )
        model.library = LibraryState(notebooks: [notebook])

        await model.synchronize()

        let savedState = await stateStore.load()
        XCTAssertEqual(savedState?.receivedChanges, [remoteChange])
        XCTAssertNotNil(model.presentedError)
    }

    func testSavedRemoteStrokeIsNotAppliedAgainWhenAcknowledgementWasInterrupted() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        let syncDirectoryURL = directoryURL.appending(path: "Sync")
        var notebook = DomainFixtures.notebook(title: "Interrupted acknowledgement")
        let canvas = notebook.canvases[0]
        let layer = canvas.layers[0]
        let remoteStroke = DomainFixtures.stroke(id: StrokeID(), layerID: layer.id)
        let operation = DocumentOperation.addStroke(
            canvasID: canvas.id,
            layerID: layer.id,
            stroke: remoteStroke
        )
        try operation.apply(to: &notebook)
        let remoteChange = try SyncChangeEncoder(deviceID: "remote-device").change(
            for: operation,
            notebookID: notebook.id,
            sequence: 1,
            timestamp: DomainFixtures.fixedDate.addingTimeInterval(1)
        )
        try await repository.save(LibraryState(notebooks: [notebook]))
        try await documentStore.save(
            NativeNotebookPackage(
                schemaVersion: .current,
                notebook: notebook,
                appliedRemoteChangeIDs: [remoteChange.id]
            )
        )
        try await saveInterruptedState(remoteChange, at: syncDirectoryURL)
        let restoredStateStore = LocalSyncStateStore(directoryURL: syncDirectoryURL)
        let restoredSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            syncProvider: InMemorySyncProvider(),
            syncStateStore: restoredStateStore,
            deviceID: "receiving-device",
            automaticallyRestore: false
        )

        await restoredSession.restoreLibrary()

        let restoredNotebook = try XCTUnwrap(restoredSession.notebook(notebook.id))
        let matchingStrokeCount = restoredNotebook.canvases
            .flatMap(\.layers)
            .flatMap(\.objects)
            .filter { $0.strokeValue?.id == remoteStroke.id }
            .count
        let acknowledgedState = try await restoredStateStore.load()
        XCTAssertEqual(matchingStrokeCount, 1)
        XCTAssertTrue(acknowledgedState?.receivedChanges.isEmpty == true)
    }

    func testSavedRemoteStrokeDeletionIsAcknowledgedWhenAcknowledgementWasInterrupted() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        let syncDirectoryURL = directoryURL.appending(path: "Sync")
        var notebook = DomainFixtures.notebook(title: "Interrupted deletion acknowledgement")
        let canvas = notebook.canvases[0]
        let stroke = try XCTUnwrap(canvas.layers[0].objects[0].strokeValue)
        let operation = try DocumentOperation.deleteObjects(
            in: notebook,
            canvasID: canvas.id,
            objectIDs: [stroke.objectID]
        )
        try operation.apply(to: &notebook)
        let remoteChange = try SyncChangeEncoder(deviceID: "remote-device").change(
            for: operation,
            notebookID: notebook.id,
            sequence: 1,
            timestamp: DomainFixtures.fixedDate.addingTimeInterval(1)
        )
        try await repository.save(LibraryState(notebooks: [notebook]))
        try await documentStore.save(
            NativeNotebookPackage(
                schemaVersion: .current,
                notebook: notebook,
                appliedRemoteChangeIDs: [remoteChange.id]
            )
        )
        try await saveInterruptedState(remoteChange, at: syncDirectoryURL)
        let restoredStateStore = LocalSyncStateStore(directoryURL: syncDirectoryURL)
        let restoredSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            syncProvider: InMemorySyncProvider(),
            syncStateStore: restoredStateStore,
            deviceID: "receiving-device",
            automaticallyRestore: false
        )

        await restoredSession.restoreLibrary()

        XCTAssertFalse(restoredSession.notebook(notebook.id)?.containsStroke(stroke.id) == true)
        let acknowledgedState = try await restoredStateStore.load()
        XCTAssertTrue(acknowledgedState?.receivedChanges.isEmpty == true)
    }

    func testRemoteFolderRestoreMakesContainedHandwritingSearchable() async throws {
        let fixture = try await makeRemoteFolderFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let provider = InMemorySyncProvider()
        let stateStore = InMemorySyncStateStore()
        let restoreChange = try SyncChangeEncoder(deviceID: "remote-device").change(
            for: .restoreFolder(fixture.folder.id),
            notebookID: NotebookID(rawValue: fixture.folder.id.rawValue),
            sequence: 1,
            timestamp: DomainFixtures.fixedDate.addingTimeInterval(1)
        )
        try await provider.push([restoreChange])
        let receivingSession = AppModel(
            repository: fixture.repository,
            documentStore: fixture.documentStore,
            syncProvider: provider,
            syncStateStore: stateStore,
            deviceID: "receiving-device",
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: SyncPersistenceHandwritingRecognizer(text: fixture.phrase)
            ),
            automaticallyRestore: false
        )
        receivingSession.searchQuery = fixture.phrase

        await receivingSession.restoreLibrary()
        for _ in 0..<150 where receivingSession.searchResults.isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        await receivingSession.documentPersistenceTask?.value
        await receivingSession.libraryPersistenceTask?.value
        let reopenedSession = AppModel(
            repository: fixture.repository,
            documentStore: fixture.documentStore,
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: FailingSyncRecognizer()
            ),
            automaticallyRestore: false
        )
        await reopenedSession.restoreLibrary()
        reopenedSession.searchQuery = fixture.phrase

        XCTAssertNil(reopenedSession.library.folder(id: fixture.folder.id)?.trashedAt)
        XCTAssertNil(reopenedSession.notebook(fixture.searchableNotebook.id)?.trashedAt)
        XCTAssertNil(reopenedSession.notebook(fixture.rawInkNotebook.id)?.trashedAt)
        XCTAssertEqual(reopenedSession.searchResults.first?.matchType, .handwriting)
    }

    private func makeRemoteFolderFixture() async throws -> RemoteFolderFixture {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        let folder = Folder(
            name: "Restored remotely",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate,
            trashedAt: DomainFixtures.fixedDate
        )
        var searchableNotebook = DomainFixtures.notebook(title: "Remote folder notebook")
        searchableNotebook.parentFolderID = folder.id
        searchableNotebook.trashedAt = DomainFixtures.fixedDate
        var rawInkNotebook = DomainFixtures.notebook(id: NotebookID(), title: "Remote folder raw ink")
        rawInkNotebook.parentFolderID = folder.id
        rawInkNotebook.trashedAt = DomainFixtures.fixedDate
        rawInkNotebook.canvases[0].layers[0].isVisible = false
        let library = LibraryState(folders: [folder], notebooks: [searchableNotebook, rawInkNotebook])
        try await repository.save(library)
        for notebook in library.notebooks {
            try await documentStore.save(NativeNotebookPackage(schemaVersion: .current, notebook: notebook))
        }
        return RemoteFolderFixture(
            directoryURL: directoryURL,
            repository: repository,
            documentStore: documentStore,
            folder: folder,
            searchableNotebook: searchableNotebook,
            rawInkNotebook: rawInkNotebook,
            phrase: "Remote restored handwriting"
        )
    }

    private func saveInterruptedState(_ change: DocumentChange, at directoryURL: URL) async throws {
        try await saveInterruptedState([change], at: directoryURL)
    }

    private func saveInterruptedState(_ changes: [DocumentChange], at directoryURL: URL) async throws {
        let interruptedStateStore = LocalSyncStateStore(directoryURL: directoryURL)
        try await interruptedStateStore.save(
            SyncEngineSnapshot(
                pendingChanges: [],
                pendingAssets: [],
                receivedChanges: changes,
                cursor: nil
            )
        )
    }

}

private extension Notebook {
    func containsStroke(_ strokeID: StrokeID) -> Bool {
        canvases
            .flatMap(\.layers)
            .flatMap(\.objects)
            .contains { $0.strokeValue?.id == strokeID }
    }
}

private struct SyncPersistenceHandwritingRecognizer: HandwritingRecognizer {
    let text: String

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

private struct FailingSyncRecognizer: HandwritingRecognizer {
    func recognize(strokes: [Stroke]) async throws -> HandwritingRecognitionResult {
        throw CocoaError(.featureUnsupported)
    }
}

private struct RemoteFolderFixture {
    let directoryURL: URL
    let repository: LocalLibraryRepository
    let documentStore: LocalDocumentStore
    let folder: Folder
    let searchableNotebook: Notebook
    let rawInkNotebook: Notebook
    let phrase: String
}
