import XCTest
@testable import NoteNerds

final class SyncDependencyRetryBehaviorTests: XCTestCase {
    @MainActor
    func testNotebookRestoreWaitsForTheNotebookCreateAndThenWins() async throws {
        let provider = InMemorySyncProvider()
        let stateStore = InMemorySyncStateStore()
        var notebook = DomainFixtures.notebook()
        notebook.trashedAt = DomainFixtures.fixedDate
        let encoder = SyncChangeEncoder(deviceID: "remote-device")
        let restore = try encoder.change(
            for: .restoreNotebook(notebook.id),
            notebookID: notebook.id,
            sequence: 1,
            timestamp: DomainFixtures.fixedDate
        )
        try await provider.push([restore])
        let model = model(provider: provider, stateStore: stateStore)

        await model.synchronize()

        XCTAssertNil(model.library.notebook(id: notebook.id))
        let waitingState = await stateStore.load()
        XCTAssertEqual(waitingState?.receivedChanges, [restore])

        let create = try encoder.change(
            for: .createNotebook(notebook),
            notebookID: notebook.id,
            sequence: 2,
            timestamp: DomainFixtures.fixedDate.addingTimeInterval(1)
        )
        try await provider.push([create])
        await model.synchronize()

        XCTAssertNil(model.library.notebook(id: notebook.id)?.trashedAt)
        let restoredState = await stateStore.load()
        XCTAssertTrue(restoredState?.receivedChanges.isEmpty == true)
    }

    @MainActor
    func testChangesForPermanentlyDeletedNotebookAreDiscarded() async throws {
        let provider = InMemorySyncProvider()
        let stateStore = InMemorySyncStateStore()
        let notebook = DomainFixtures.notebook()
        let canvasID = notebook.canvases[0].id
        let layerID = notebook.canvases[0].layers[0].id
        let encoder = SyncChangeEncoder(deviceID: "stale-device")
        let metadata = try encoder.change(
            for: .updateNotebookMetadata(NotebookSyncMetadata(notebook: notebook)),
            notebookID: notebook.id,
            sequence: 1,
            timestamp: DomainFixtures.fixedDate
        )
        let ink = try encoder.change(
            for: DocumentOperation.addStroke(
                canvasID: canvasID,
                layerID: layerID,
                stroke: DomainFixtures.stroke(id: StrokeID(), layerID: layerID)
            ),
            notebookID: notebook.id,
            sequence: 2,
            timestamp: DomainFixtures.fixedDate.addingTimeInterval(1)
        )
        try await provider.push([metadata, ink])
        let model = model(provider: provider, stateStore: stateStore)
        model.library.permanentlyDeleteNotebook(notebook.id)

        await model.synchronize()

        XCTAssertNil(model.library.notebook(id: notebook.id))
        let state = await stateStore.load()
        XCTAssertTrue(state?.receivedChanges.isEmpty == true)
    }

    @MainActor
    private func model(
        provider: InMemorySyncProvider,
        stateStore: InMemorySyncStateStore
    ) -> AppModel {
        AppModel(
            repository: LocalLibraryRepository(
                fileURL: FileManager.default.temporaryDirectory
                    .appending(path: UUID().uuidString)
                    .appending(path: "library.json")
            ),
            syncProvider: provider,
            syncStateStore: stateStore,
            deviceID: "receiving-device",
            automaticallyRestore: false
        )
    }
}
