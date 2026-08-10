import XCTest
@testable import NoteNerds

@MainActor
final class LocalEchoRecoveryBehaviorTests: XCTestCase {
    func testFailedDocumentSaveLeavesNoLocalMarkerAndTheEchoRecoversTheEdit() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentRootURL = directoryURL.appending(path: "Documents")
        let documentStore = LocalDocumentStore(rootURL: documentRootURL)
        let stateStore = ReceivedChangeSyncStateStore(
            directoryURL: directoryURL.appending(path: "Sync")
        )
        let provider = InMemorySyncProvider()
        let notebook = DomainFixtures.notebook(title: "Recovered local echo")
        let (operation, stroke) = makeStrokeOperation(in: notebook)
        try await repository.save(LibraryState(notebooks: [notebook]))
        try await documentStore.save(
            NativeNotebookPackage(schemaVersion: .current, notebook: notebook)
        )
        let editingModel = makeModel(
            repository: repository,
            documentStore: documentStore,
            provider: provider,
            stateStore: stateStore,
            deviceID: "editing-device"
        )
        await editingModel.restoreLibrary()
        try FileManager.default.removeItem(at: documentRootURL)
        try Data("blocked".utf8).write(to: documentRootURL)

        editingModel.execute(operation, on: notebook.id)
        await stateStore.waitUntilReceivedChangeIsSaved()

        let loadedInterruptedState = try await stateStore.load()
        let interruptedState = try XCTUnwrap(loadedInterruptedState)
        XCTAssertEqual(interruptedState.receivedChanges.count, 1)
        XCTAssertTrue(interruptedState.locallyAppliedChangeIDs.isEmpty)
        try FileManager.default.removeItem(at: documentRootURL)
        try await documentStore.save(
            NativeNotebookPackage(schemaVersion: .current, notebook: notebook)
        )
        let reopenedModel = makeModel(
            repository: repository,
            documentStore: documentStore,
            provider: provider,
            stateStore: stateStore,
            deviceID: "receiving-device"
        )

        await reopenedModel.restoreLibrary()

        let reopened = try XCTUnwrap(reopenedModel.notebook(notebook.id))
        let loadedAcknowledgedState = try await stateStore.load()
        let acknowledgedState = try XCTUnwrap(loadedAcknowledgedState)
        XCTAssertEqual(reopened.strokeCount(for: stroke.id), 1)
        XCTAssertTrue(acknowledgedState.receivedChanges.isEmpty)
    }

    func testSyncSnapshotReadsFilesWrittenBeforeLocalMarkersExisted() throws {
        let change = DocumentChange.fixture(objectKey: "legacy", sequence: 1)
        let snapshot = SyncEngineSnapshot(
            pendingChanges: [change],
            pendingAssets: [],
            receivedChanges: [],
            cursor: nil
        )
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["locallyAppliedChangeIDs"] = nil
        let legacyData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        let restored = try JSONDecoder().decode(SyncEngineSnapshot.self, from: legacyData)

        XCTAssertEqual(restored.pendingChanges, [change])
        XCTAssertTrue(restored.locallyAppliedChangeIDs.isEmpty)
    }

    func testSyncSnapshotEncodesLocalMarkersInStableOrder() throws {
        let firstID = ChangeID(rawValue: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")))
        let secondID = ChangeID(rawValue: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002")))
        let firstSnapshot = SyncEngineSnapshot(
            pendingChanges: [],
            pendingAssets: [],
            receivedChanges: [],
            cursor: nil,
            locallyAppliedChangeIDs: [secondID, firstID]
        )
        let secondSnapshot = SyncEngineSnapshot(
            pendingChanges: [],
            pendingAssets: [],
            receivedChanges: [],
            cursor: nil,
            locallyAppliedChangeIDs: [firstID, secondID]
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary

        XCTAssertEqual(try encoder.encode(firstSnapshot), try encoder.encode(secondSnapshot))
        XCTAssertEqual(firstSnapshot.locallyAppliedChangeIDs, [firstID, secondID])
    }

    private func makeModel(
        repository: LocalLibraryRepository,
        documentStore: LocalDocumentStore,
        provider: any SyncProvider,
        stateStore: any SyncStateStore,
        deviceID: String
    ) -> AppModel {
        AppModel(
            repository: repository,
            documentStore: documentStore,
            syncProvider: provider,
            syncStateStore: stateStore,
            deviceID: deviceID,
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: LocalEchoRecoveryTestRecognizer()
            ),
            automaticallyRestore: false
        )
    }

    private func makeStrokeOperation(in notebook: Notebook) -> (DocumentOperation, Stroke) {
        let canvas = notebook.canvases[0]
        let layer = canvas.layers[0]
        let stroke = DomainFixtures.stroke(id: StrokeID(), layerID: layer.id)
        return (
            .addStroke(canvasID: canvas.id, layerID: layer.id, stroke: stroke),
            stroke
        )
    }
}

private actor ReceivedChangeSyncStateStore: SyncStateStore {
    private let store: LocalSyncStateStore
    private var didSaveReceivedChange = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(directoryURL: URL) {
        store = LocalSyncStateStore(directoryURL: directoryURL)
    }

    func load() async throws -> SyncEngineSnapshot? {
        try await store.load()
    }

    func save(_ snapshot: SyncEngineSnapshot) async throws {
        try await store.save(snapshot)
        guard !snapshot.receivedChanges.isEmpty else { return }
        didSaveReceivedChange = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func waitUntilReceivedChangeIsSaved() async {
        guard !didSaveReceivedChange else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private struct LocalEchoRecoveryTestRecognizer: HandwritingRecognizer {
    func recognize(strokes: [Stroke]) async throws -> HandwritingRecognitionResult {
        throw CocoaError(.featureUnsupported)
    }
}

private extension Notebook {
    func strokeCount(for id: StrokeID) -> Int {
        canvases
            .flatMap(\.layers)
            .flatMap(\.objects)
            .compactMap(\.strokeValue)
            .count { $0.id == id }
    }
}
