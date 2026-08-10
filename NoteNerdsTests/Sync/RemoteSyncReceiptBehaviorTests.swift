import XCTest
@testable import NoteNerds

@MainActor
final class RemoteSyncReceiptBehaviorTests: XCTestCase {
    func testInterruptedRemoteStrokeAddDoesNotDuplicateAfterTheStrokeIsEdited() async throws {
        var notebook = DomainFixtures.notebook(title: "Edited remote stroke")
        let canvasID = notebook.canvases[0].id
        let layerID = notebook.canvases[0].layers[0].id
        let remoteStroke = DomainFixtures.stroke(id: StrokeID(), layerID: layerID)
        let addOperation = DocumentOperation.addStroke(
            canvasID: canvasID,
            layerID: layerID,
            stroke: remoteStroke
        )
        try addOperation.apply(to: &notebook)
        var editedStroke = remoteStroke
        editedStroke.samples[0].point.x += 80
        let editOperation = try DocumentOperation.replacingObjects(
            in: notebook,
            canvasID: canvasID,
            objectIDs: [remoteStroke.objectID],
            with: [.stroke(editedStroke)]
        )
        try editOperation.apply(to: &notebook)
        let changes = try [
            remoteChange(for: addOperation, notebookID: notebook.id, sequence: 1),
            remoteChange(for: editOperation, notebookID: notebook.id, sequence: 2)
        ]
        let fixture = try await restoreInterruptedChanges(changes, in: notebook)
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }

        let restored = try XCTUnwrap(fixture.model.notebook(notebook.id))
        let matchingStrokes = restored.canvases
            .flatMap(\.layers)
            .flatMap(\.objects)
            .compactMap(\.strokeValue)
            .filter { $0.id == remoteStroke.id }
        let restoredSyncState = try await fixture.stateStore.load()

        XCTAssertEqual(matchingStrokes, [editedStroke])
        XCTAssertTrue(restoredSyncState?.receivedChanges.isEmpty == true)
    }

    func testInterruptedRemoteCanvasInsertDoesNotDuplicateAfterTheCanvasIsRenamed() async throws {
        var notebook = DomainFixtures.notebook(title: "Edited remote canvas")
        let insertedCanvas = Canvas(title: "Remote canvas")
        let insertOperation = DocumentOperation.insertCanvas(canvas: insertedCanvas, index: 1)
        try insertOperation.apply(to: &notebook)
        let editOperation = DocumentOperation.renameCanvas(
            canvasID: insertedCanvas.id,
            before: insertedCanvas.title,
            after: "Renamed after sync"
        )
        try editOperation.apply(to: &notebook)
        let changes = try [
            remoteChange(for: insertOperation, notebookID: notebook.id, sequence: 1),
            remoteChange(for: editOperation, notebookID: notebook.id, sequence: 2)
        ]
        let fixture = try await restoreInterruptedChanges(changes, in: notebook)
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }

        let restored = try XCTUnwrap(fixture.model.notebook(notebook.id))
        let matchingCanvases = restored.canvases.filter { $0.id == insertedCanvas.id }
        let restoredSyncState = try await fixture.stateStore.load()

        XCTAssertEqual(matchingCanvases.count, 1)
        XCTAssertEqual(matchingCanvases.first?.title, "Renamed after sync")
        XCTAssertTrue(restoredSyncState?.receivedChanges.isEmpty == true)
    }

    func testInterruptedRemoteLayerInsertDoesNotDuplicateAfterTheLayerIsEdited() async throws {
        var notebook = DomainFixtures.notebook(title: "Edited remote layer")
        let canvasID = notebook.canvases[0].id
        let insertedLayer = Layer(name: "Remote layer")
        let insertOperation = DocumentOperation.insertLayer(
            canvasID: canvasID,
            layer: insertedLayer,
            index: 1
        )
        try insertOperation.apply(to: &notebook)
        var editedLayer = insertedLayer
        editedLayer.name = "Renamed after sync"
        editedLayer.isVisible = false
        let editOperation = DocumentOperation.updateLayer(
            canvasID: canvasID,
            before: insertedLayer,
            after: editedLayer
        )
        try editOperation.apply(to: &notebook)
        let changes = try [
            remoteChange(for: insertOperation, notebookID: notebook.id, sequence: 1),
            remoteChange(for: editOperation, notebookID: notebook.id, sequence: 2)
        ]
        let fixture = try await restoreInterruptedChanges(changes, in: notebook)
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }

        let restored = try XCTUnwrap(fixture.model.notebook(notebook.id))
        let matchingLayers = restored.canvases[0].layers.filter { $0.id == insertedLayer.id }
        let restoredSyncState = try await fixture.stateStore.load()

        XCTAssertEqual(matchingLayers, [editedLayer])
        XCTAssertTrue(restoredSyncState?.receivedChanges.isEmpty == true)
    }

    func testInterruptedRemoteCanvasMoveIsNotAppliedAgain() async throws {
        let first = Canvas(title: "First")
        let second = Canvas(title: "Second")
        let third = Canvas(title: "Third")
        var notebook = Notebook(title: "Moved canvases", canvases: [first, second, third])
        let operation = DocumentOperation.moveCanvas(sourceIndex: 0, destinationIndex: 2)
        try operation.apply(to: &notebook)
        let expectedCanvasIDs = notebook.canvases.map(\.id)
        let change = try remoteChange(for: operation, notebookID: notebook.id, sequence: 1)
        let fixture = try await restoreInterruptedChanges([change], in: notebook)
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }

        let restored = try XCTUnwrap(fixture.model.notebook(notebook.id))
        let restoredSyncState = try await fixture.stateStore.load()

        XCTAssertEqual(restored.canvases.map(\.id), expectedCanvasIDs)
        XCTAssertTrue(restoredSyncState?.receivedChanges.isEmpty == true)
    }

    func testInterruptedRemoteLayerMoveIsNotAppliedAgain() async throws {
        let first = Layer(name: "First")
        let second = Layer(name: "Second")
        let third = Layer(name: "Third")
        let canvas = Canvas(title: "Layered canvas", layers: [first, second, third])
        var notebook = Notebook(title: "Moved layers", canvases: [canvas])
        let operation = DocumentOperation.moveLayer(
            canvasID: canvas.id,
            sourceIndex: 0,
            destinationIndex: 2
        )
        try operation.apply(to: &notebook)
        let expectedLayerIDs = notebook.canvases[0].layers.map(\.id)
        let change = try remoteChange(for: operation, notebookID: notebook.id, sequence: 1)
        let fixture = try await restoreInterruptedChanges([change], in: notebook)
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }

        let restored = try XCTUnwrap(fixture.model.notebook(notebook.id))
        let restoredSyncState = try await fixture.stateStore.load()

        XCTAssertEqual(restored.canvases[0].layers.map(\.id), expectedLayerIDs)
        XCTAssertTrue(restoredSyncState?.receivedChanges.isEmpty == true)
    }

    func testFailedAcknowledgementReceiptSurvivesCheckpointAndRelaunch() async throws {
        let fixture = try await makeInterruptedAcknowledgementFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let initiallySaved = try await fixture.documentStore.load(notebookID: fixture.notebook.id)
        XCTAssertTrue(initiallySaved.appliedRemoteChangeIDs.contains(fixture.change.id))

        let editingModel = makeModel(
            repository: fixture.repository,
            documentStore: fixture.documentStore
        )
        await editingModel.restoreLibrary()
        let canvasID = fixture.notebook.canvases[0].id
        editingModel.renameCanvas(canvasID, to: "Locally renamed", in: fixture.notebook.id)
        await editingModel.checkpointDocuments()

        let checkpoint = try await fixture.documentStore.load(notebookID: fixture.notebook.id)
        XCTAssertTrue(checkpoint.appliedRemoteChangeIDs.contains(fixture.change.id))
        let reopenedModel = makeModel(
            repository: fixture.repository,
            documentStore: fixture.documentStore,
            provider: fixture.provider,
            stateStore: fixture.stateStore
        )
        await reopenedModel.restoreLibrary()
        let reopened = try XCTUnwrap(reopenedModel.notebook(fixture.notebook.id))
        let matchingStrokeCount = reopened.canvases
            .flatMap(\.layers)
            .flatMap(\.objects)
            .filter { $0.strokeValue?.id == fixture.stroke.id }
            .count
        let interruptedState = await fixture.stateStore.load()
        let stillSaved = try await fixture.documentStore.load(notebookID: fixture.notebook.id)

        XCTAssertEqual(matchingStrokeCount, 1)
        XCTAssertEqual(reopened.canvases[0].title, "Locally renamed")
        XCTAssertEqual(interruptedState?.receivedChanges, [fixture.change])
        XCTAssertTrue(stillSaved.appliedRemoteChangeIDs.contains(fixture.change.id))
    }

    func testSuccessfulAcknowledgementPrunesRemoteReceipt() async throws {
        let fixture = try await makeInterruptedAcknowledgementFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        await fixture.stateStore.allowAcknowledgementPersistence()
        let reopenedModel = makeModel(
            repository: fixture.repository,
            documentStore: fixture.documentStore,
            provider: fixture.provider,
            stateStore: fixture.stateStore
        )

        await reopenedModel.restoreLibrary()

        let reopened = try XCTUnwrap(reopenedModel.notebook(fixture.notebook.id))
        let matchingStrokeCount = reopened.canvases
            .flatMap(\.layers)
            .flatMap(\.objects)
            .filter { $0.strokeValue?.id == fixture.stroke.id }
            .count
        let acknowledgedState = await fixture.stateStore.load()
        let savedPackage = try await fixture.documentStore.load(notebookID: fixture.notebook.id)

        XCTAssertEqual(matchingStrokeCount, 1)
        XCTAssertTrue(acknowledgedState?.receivedChanges.isEmpty == true)
        XCTAssertTrue(savedPackage.appliedRemoteChangeIDs.isEmpty)
    }

    func testLocalCheckpointPreservesRemoteReceipt() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        let stateStore = LocalSyncStateStore(directoryURL: directoryURL.appending(path: "Sync"))
        let first = Canvas(title: "First")
        let second = Canvas(title: "Second")
        let third = Canvas(title: "Third")
        var notebook = Notebook(title: "Checkpoint receipt", canvases: [first, second, third])
        let operation = DocumentOperation.moveCanvas(sourceIndex: 0, destinationIndex: 2)
        try operation.apply(to: &notebook)
        let change = try remoteChange(for: operation, notebookID: notebook.id, sequence: 1)
        try await repository.save(LibraryState(notebooks: [notebook]))
        try await documentStore.save(
            NativeNotebookPackage(
                schemaVersion: .current,
                notebook: notebook,
                appliedRemoteChangeIDs: [change.id]
            )
        )
        let editingModel = makeModel(repository: repository, documentStore: documentStore)
        await editingModel.restoreLibrary()
        editingModel.renameCanvas(second.id, to: "Locally renamed", in: notebook.id)
        await editingModel.checkpointDocuments()
        let checkpoint = try await documentStore.load(notebookID: notebook.id)
        XCTAssertTrue(checkpoint.appliedRemoteChangeIDs.contains(change.id))

        try await saveInterruptedState([change], in: stateStore)
        let reopenedModel = makeModel(
            repository: repository,
            documentStore: documentStore,
            provider: InMemorySyncProvider(),
            stateStore: stateStore
        )
        await reopenedModel.restoreLibrary()
        let reopened = try XCTUnwrap(reopenedModel.notebook(notebook.id))
        let acknowledgedState = try await stateStore.load()

        XCTAssertEqual(reopened.canvases.map(\.id), notebook.canvases.map(\.id))
        XCTAssertEqual(reopened.canvases.first { $0.id == second.id }?.title, "Locally renamed")
        XCTAssertTrue(acknowledgedState?.receivedChanges.isEmpty == true)
    }

    func testOnlyReceiptedChangesAreSkippedDuringReplay() async throws {
        var notebook = DomainFixtures.notebook(title: "Partial receipt")
        let insertedCanvas = Canvas(title: "Inserted")
        let insertOperation = DocumentOperation.insertCanvas(canvas: insertedCanvas, index: 1)
        try insertOperation.apply(to: &notebook)
        let renameOperation = DocumentOperation.renameCanvas(
            canvasID: insertedCanvas.id,
            before: insertedCanvas.title,
            after: "Renamed on replay"
        )
        let insertChange = try remoteChange(for: insertOperation, notebookID: notebook.id, sequence: 1)
        let renameChange = try remoteChange(for: renameOperation, notebookID: notebook.id, sequence: 2)
        let fixture = try await restoreInterruptedChanges(
            [insertChange, renameChange],
            receiptIDs: [insertChange.id],
            in: notebook
        )
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }

        let restored = try XCTUnwrap(fixture.model.notebook(notebook.id))
        let matchingCanvases = restored.canvases.filter { $0.id == insertedCanvas.id }
        let savedPackage = try await fixture.documentStore.load(notebookID: notebook.id)
        let restoredState = try await fixture.stateStore.load()

        XCTAssertEqual(matchingCanvases.count, 1)
        XCTAssertEqual(matchingCanvases.first?.title, "Renamed on replay")
        XCTAssertTrue(savedPackage.appliedRemoteChangeIDs.isEmpty)
        XCTAssertTrue(restoredState?.receivedChanges.isEmpty == true)
    }

    private func remoteChange(
        for operation: DocumentOperation,
        notebookID: NotebookID,
        sequence: Int
    ) throws -> DocumentChange {
        try SyncChangeEncoder(deviceID: "remote-device").change(
            for: operation,
            notebookID: notebookID,
            sequence: sequence,
            timestamp: DomainFixtures.fixedDate.addingTimeInterval(TimeInterval(sequence))
        )
    }

    private func makeInterruptedAcknowledgementFixture() async throws -> InterruptedAcknowledgementFixture {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        let provider = InMemorySyncProvider()
        let stateStore = InterruptingAcknowledgementStateStore()
        let notebook = DomainFixtures.notebook(title: "Interrupted receipt write")
        let canvas = notebook.canvases[0]
        let layer = canvas.layers[0]
        let stroke = DomainFixtures.stroke(id: StrokeID(), layerID: layer.id)
        let operation = DocumentOperation.addStroke(
            canvasID: canvas.id,
            layerID: layer.id,
            stroke: stroke
        )
        let change = try remoteChange(for: operation, notebookID: notebook.id, sequence: 1)
        try await repository.save(LibraryState(notebooks: [notebook]))
        try await documentStore.save(NativeNotebookPackage(schemaVersion: .current, notebook: notebook))
        try await provider.push([change])
        let receivingModel = makeModel(
            repository: repository,
            documentStore: documentStore,
            provider: provider,
            stateStore: stateStore
        )

        await receivingModel.restoreLibrary()

        return InterruptedAcknowledgementFixture(
            directoryURL: directoryURL,
            repository: repository,
            documentStore: documentStore,
            provider: provider,
            stateStore: stateStore,
            notebook: notebook,
            change: change,
            stroke: stroke
        )
    }

    private func restoreInterruptedChanges(
        _ changes: [DocumentChange],
        receiptIDs: Set<ChangeID>? = nil,
        in notebook: Notebook
    ) async throws -> ReceiptReplayFixture {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        let stateStore = LocalSyncStateStore(directoryURL: directoryURL.appending(path: "Sync"))
        try await repository.save(LibraryState(notebooks: [notebook]))
        try await documentStore.save(
            NativeNotebookPackage(
                schemaVersion: .current,
                notebook: notebook,
                appliedRemoteChangeIDs: receiptIDs ?? Set(changes.map(\.id))
            )
        )
        try await saveInterruptedState(changes, in: stateStore)
        let model = makeModel(
            repository: repository,
            documentStore: documentStore,
            provider: InMemorySyncProvider(),
            stateStore: stateStore
        )

        await model.restoreLibrary()

        return ReceiptReplayFixture(
            directoryURL: directoryURL,
            documentStore: documentStore,
            model: model,
            stateStore: stateStore
        )
    }

    private func saveInterruptedState(
        _ changes: [DocumentChange],
        in stateStore: LocalSyncStateStore
    ) async throws {
        try await stateStore.save(
            SyncEngineSnapshot(
                pendingChanges: [],
                pendingAssets: [],
                receivedChanges: changes,
                cursor: nil
            )
        )
    }

    private func makeModel(
        repository: LocalLibraryRepository,
        documentStore: LocalDocumentStore,
        provider: (any SyncProvider)? = nil,
        stateStore: (any SyncStateStore)? = nil
    ) -> AppModel {
        AppModel(
            repository: repository,
            documentStore: documentStore,
            syncProvider: provider,
            syncStateStore: stateStore,
            deviceID: "receiving-device",
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: ReceiptTestRecognizer()
            ),
            automaticallyRestore: false
        )
    }
}

private actor InterruptingAcknowledgementStateStore: SyncStateStore {
    private var snapshot: SyncEngineSnapshot?
    private var rejectsAcknowledgement = true

    func load() -> SyncEngineSnapshot? {
        snapshot
    }

    func save(_ newSnapshot: SyncEngineSnapshot) throws {
        if rejectsAcknowledgement,
           snapshot?.receivedChanges.isEmpty == false,
           newSnapshot.receivedChanges.isEmpty {
            throw CocoaError(.fileWriteUnknown)
        }
        snapshot = newSnapshot
    }

    func allowAcknowledgementPersistence() {
        rejectsAcknowledgement = false
    }
}

private struct ReceiptTestRecognizer: HandwritingRecognizer {
    func recognize(strokes: [Stroke]) async throws -> HandwritingRecognitionResult {
        throw CocoaError(.featureUnsupported)
    }
}

private struct InterruptedAcknowledgementFixture {
    let directoryURL: URL
    let repository: LocalLibraryRepository
    let documentStore: LocalDocumentStore
    let provider: InMemorySyncProvider
    let stateStore: InterruptingAcknowledgementStateStore
    let notebook: Notebook
    let change: DocumentChange
    let stroke: Stroke
}

@MainActor
private struct ReceiptReplayFixture {
    let directoryURL: URL
    let documentStore: LocalDocumentStore
    let model: AppModel
    let stateStore: LocalSyncStateStore
}
