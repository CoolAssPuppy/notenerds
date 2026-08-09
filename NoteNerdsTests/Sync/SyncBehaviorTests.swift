import XCTest
@testable import NoteNerds

final class SyncBehaviorTests: XCTestCase {
    func testSimulatorBuildUsesLocalStorageWithoutCreatingACloudContainer() {
        XCTAssertFalse(CloudKitRuntime.isAvailable)
        XCTAssertNil(DefaultSyncProvider.make())
    }

    func testProviderPushIsIdempotentAndPullUsesCursor() async throws {
        let provider = InMemorySyncProvider()
        try await SyncProviderContractAssertions.verify(provider)
    }

    func testIndependentConcurrentStrokeAddsBothSurviveConflictResolution() {
        let local = DocumentChange.fixture(objectKey: "stroke-local", sequence: 1)
        let remote = DocumentChange.fixture(objectKey: "stroke-remote", sequence: 2)

        XCTAssertEqual(SyncConflictResolver.resolve(local: [local], remote: [remote]), [local, remote])
    }

    func testSameObjectConflictUsesTimestampThenDeviceIdentifier() {
        let date = Date(timeIntervalSince1970: 100)
        let first = DocumentChange.fixture(objectKey: "same", sequence: 1, timestamp: date, deviceID: "A")
        let second = DocumentChange.fixture(objectKey: "same", sequence: 2, timestamp: date, deviceID: "B")

        XCTAssertEqual(SyncConflictResolver.resolve(local: [first], remote: [second]), [second])
    }

    func testFailedPushKeepsOfflineChangesForRetry() async {
        let provider = FailingSyncProvider()
        let change = DocumentChange.fixture(objectKey: "offline-stroke", sequence: 1)
        let engine = SyncEngine(provider: provider)
        await engine.enqueue(change)

        await engine.synchronize()

        let pendingChanges = await engine.pendingChanges
        XCTAssertEqual(pendingChanges, [change])
        let state = await engine.state
        XCTAssertEqual(state, .waitingToRetry)
    }

    func testFailedAssetUploadKeepsAssetForRetry() async {
        let provider = FailingSyncProvider()
        let asset = DocumentAsset(id: AssetID(), data: Data("image".utf8), contentType: "image/png")
        let engine = SyncEngine(provider: provider)
        await engine.enqueue(asset)

        await engine.synchronize()

        let pendingAssets = await engine.pendingAssets
        XCTAssertEqual(pendingAssets[asset.id], asset)
    }

    func testProviderFailureRetainsAnUnderstandableRetryReason() async {
        let engine = SyncEngine(provider: AccountUnavailableSyncProvider())

        await engine.synchronize()

        let failure = await engine.lastFailure
        XCTAssertEqual(failure, .accountUnavailable)
        XCTAssertEqual(
            failure?.userMessage,
            "Sign in to iCloud to sync. Changes remain saved on this iPad."
        )
    }

    func testPendingChangesSurviveEngineRestart() async throws {
        let provider = InMemorySyncProvider()
        let store = InMemorySyncStateStore()
        let change = DocumentChange.fixture(objectKey: "restart-stroke", sequence: 1)
        let firstEngine = SyncEngine(provider: FailingSyncProvider(), stateStore: store)
        await firstEngine.enqueue(change)
        await firstEngine.synchronize()

        let restartedEngine = SyncEngine(provider: provider, stateStore: store)
        await restartedEngine.synchronize()

        let remote = try await provider.pull(since: nil)
        XCTAssertEqual(remote.changes, [change])
        let pending = await restartedEngine.pendingChanges
        XCTAssertTrue(pending.isEmpty)
    }

    func testSyncStateWriteFailureIsVisibleAndKeepsTheChangeInMemory() async {
        let change = DocumentChange.fixture(objectKey: "unsaved", sequence: 1)
        let engine = SyncEngine(provider: InMemorySyncProvider(), stateStore: FailingSyncStateStore())

        await engine.enqueue(change)

        let pending = await engine.pendingChanges
        let state = await engine.state
        let failure = await engine.lastFailure
        XCTAssertEqual(pending, [change])
        XCTAssertEqual(state, .waitingToRetry)
        XCTAssertEqual(failure, .persistent)
    }

    func testCloudPushBatchesStayWithinTheProviderLimit() {
        let changes = (0..<451).map {
            DocumentChange.fixture(objectKey: "stroke-\($0)", sequence: $0)
        }

        let batches = SyncPushBatcher.batches(changes, maximumCount: 200)

        XCTAssertEqual(batches.map(\.count), [200, 200, 51])
        XCTAssertEqual(batches.flatMap { $0 }, changes)
    }

    func testLocalSyncStateUsesCompactBinaryEncodingAndRoundTrips() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = LocalSyncStateStore(directoryURL: directoryURL)
        let change = DocumentChange.fixture(objectKey: "protected", sequence: 1)
        let snapshot = SyncEngineSnapshot(
            pendingChanges: [change],
            pendingAssets: [],
            receivedChanges: [],
            cursor: nil
        )

        try await store.save(snapshot)

        let fileURL = directoryURL.appending(path: "sync-state.plist")
        let encoded = try Data(contentsOf: fileURL)
        let restored = try await store.load()
        XCTAssertEqual(String(bytes: encoded.prefix(6), encoding: .utf8), "bplist")
        XCTAssertEqual(restored, snapshot)
    }

    func testLocalSyncStateReadsTheCurrentFileWithoutAnExistencePreflight() async throws {
        let change = DocumentChange.fixture(objectKey: "protected", sequence: 1)
        let snapshot = SyncEngineSnapshot(
            pendingChanges: [change],
            pendingAssets: [],
            receivedChanges: [],
            cursor: nil
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let storedData = try encoder.encode(snapshot)
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = LocalSyncStateStore(directoryURL: directoryURL) { url in
            guard url.lastPathComponent == "sync-state.plist" else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            return storedData
        }

        let restored = try await store.load()

        XCTAssertEqual(restored, snapshot)
    }

    func testReceivedChangesAreDeliveredOnlyOnce() async throws {
        let provider = InMemorySyncProvider()
        let remote = DocumentChange.fixture(objectKey: "remote-stroke", sequence: 1)
        try await provider.push([remote])
        let engine = SyncEngine(provider: provider)

        await engine.synchronize()

        let firstDelivery = await engine.drainReceivedChanges()
        let secondDelivery = await engine.drainReceivedChanges()
        XCTAssertEqual(firstDelivery, [remote])
        XCTAssertTrue(secondDelivery.isEmpty)
    }

    func testSequentialChangesForOneObjectAreNotCollapsed() async throws {
        let provider = InMemorySyncProvider()
        let first = DocumentChange.fixture(objectKey: "same-stroke", sequence: 1)
        let second = DocumentChange.fixture(objectKey: "same-stroke", sequence: 2)
        try await provider.push([first, second])
        let engine = SyncEngine(provider: provider)

        await engine.synchronize()

        let changes = await engine.drainReceivedChanges()
        XCTAssertEqual(changes, [first, second])
    }

    func testDocumentOperationSyncPayloadRoundTrips() throws {
        let notebook = DomainFixtures.notebook()
        let canvasID = notebook.canvases[0].id
        let layerID = notebook.canvases[0].layers[0].id
        let operation = DocumentOperation.addStroke(
            canvasID: canvasID,
            layerID: layerID,
            stroke: DomainFixtures.stroke(id: StrokeID(), layerID: layerID)
        )

        let change = try SyncChangeEncoder(deviceID: "device").change(
            for: operation,
            notebookID: notebook.id,
            sequence: 7,
            timestamp: DomainFixtures.fixedDate
        )

        XCTAssertEqual(try SyncChangeEncoder.decode(change), operation)
        XCTAssertEqual(change.objectKey, "stroke:\(operation.affectedObjectIdentifier)")
        XCTAssertEqual(change.sequence, 7)
    }

    func testLibraryMetadataSyncDoesNotReplaceNotebookContent() throws {
        var notebook = DomainFixtures.notebook(title: "Before")
        var library = LibraryState(notebooks: [notebook])
        notebook.title = "After"
        notebook.isFavorite = true
        let mutation = LibrarySyncMutation.updateNotebookMetadata(NotebookSyncMetadata(notebook: notebook))
        let change = try SyncChangeEncoder(deviceID: "device").change(
            for: mutation,
            notebookID: notebook.id,
            sequence: 3,
            timestamp: DomainFixtures.fixedDate
        )

        try SyncChangeEncoder.decodeLibraryMutation(change).apply(to: &library)

        XCTAssertEqual(library.notebook(id: notebook.id)?.title, "After")
        XCTAssertEqual(library.notebook(id: notebook.id)?.isFavorite, true)
        XCTAssertEqual(library.notebook(id: notebook.id)?.canvases, DomainFixtures.notebook().canvases)
    }

    func testFolderDeletionSyncUsesRecoverableTombstone() throws {
        var library = LibraryState()
        let folder = try library.createFolder(named: "Archive", in: nil, at: DomainFixtures.fixedDate)
        let mutation = LibrarySyncMutation.trashFolder(folder.id, date: DomainFixtures.fixedDate)

        try mutation.apply(to: &library)

        XCTAssertEqual(library.folder(id: folder.id)?.trashedAt, DomainFixtures.fixedDate)
    }

    func testSyncedUndoRemovesTheOperationOnAnotherDevice() throws {
        let original = DomainFixtures.notebook()
        var remote = original
        let canvasID = original.canvases[0].id
        let layerID = original.canvases[0].layers[0].id
        let operation = DocumentOperation.addStroke(
            canvasID: canvasID,
            layerID: layerID,
            stroke: DomainFixtures.stroke(id: StrokeID(), layerID: layerID)
        )
        try operation.apply(to: &remote)
        let action = SyncedDocumentAction(operation: operation, direction: .undo)
        let change = try SyncChangeEncoder(deviceID: "device").change(
            for: action,
            notebookID: original.id,
            sequence: 9,
            timestamp: DomainFixtures.fixedDate
        )

        try SyncChangeEncoder.decodeDocumentAction(change).perform(on: &remote)

        XCTAssertEqual(remote, original)
    }
}

enum SyncProviderContractAssertions {
    static func verify(_ provider: any SyncProvider) async throws {
        let first = DocumentChange.fixture(objectKey: "stroke-a", sequence: 1)
        let second = DocumentChange.fixture(objectKey: "stroke-b", sequence: 2)
        let asset = DocumentAsset(id: AssetID(), data: Data("asset".utf8), contentType: "image/png")

        try await provider.start()
        try await provider.push([first, first, second])
        try await provider.uploadAsset(asset)
        let initialBatch = try await provider.pull(since: nil)
        let laterBatch = try await provider.pull(since: SyncCursor(sequence: 1))
        let fetchedAsset = try await provider.fetchAsset(asset.id)

        XCTAssertEqual(initialBatch.changes, [first, second])
        XCTAssertEqual(laterBatch.changes, [second])
        XCTAssertEqual(fetchedAsset, asset.data)
    }
}

extension DocumentChange {
    static func fixture(
        objectKey: String,
        sequence: Int,
        timestamp: Date = Date(timeIntervalSince1970: 100),
        deviceID: String = "device"
    ) -> DocumentChange {
        DocumentChange(
            id: ChangeID(rawValue: UUID()),
            notebookID: NotebookID(),
            objectKey: objectKey,
            kind: .upsert,
            payload: Data(objectKey.utf8),
            timestamp: timestamp,
            deviceID: deviceID,
            sequence: sequence
        )
    }
}

private actor FailingSyncProvider: SyncProvider {
    let identifier = "failing"

    func start() async throws {}
    func push(_ changes: [DocumentChange]) async throws { throw URLError(.notConnectedToInternet) }
    func pull(since cursor: SyncCursor?) async throws -> SyncBatch { SyncBatch(changes: [], cursor: cursor) }
    func uploadAsset(_ asset: DocumentAsset) async throws { throw URLError(.notConnectedToInternet) }
    func fetchAsset(_ id: AssetID) async throws -> Data { throw URLError(.fileDoesNotExist) }
}

private actor AccountUnavailableSyncProvider: SyncProvider {
    let identifier = "account-unavailable"

    func start() async throws { throw SyncProviderFailure.accountUnavailable }
    func push(_ changes: [DocumentChange]) async throws {}
    func pull(since cursor: SyncCursor?) async throws -> SyncBatch { SyncBatch(changes: [], cursor: cursor) }
    func uploadAsset(_ asset: DocumentAsset) async throws {}
    func fetchAsset(_ id: AssetID) async throws -> Data { throw SyncProviderFailure.persistent }
}

private actor FailingSyncStateStore: SyncStateStore {
    func load() -> SyncEngineSnapshot? { nil }
    func save(_ snapshot: SyncEngineSnapshot) throws { throw CocoaError(.fileWriteUnknown) }
}
