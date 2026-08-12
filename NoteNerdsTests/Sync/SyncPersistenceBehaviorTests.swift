import XCTest
@testable import NoteNerds

final class SyncPersistenceBehaviorTests: XCTestCase {
    @MainActor
    func testRemoteChangesRemainQueuedUntilTheLibrarySaveFinishes() async throws {
        let repository = PausingLibraryRepository()
        let provider = InMemorySyncProvider()
        let stateStore = InMemorySyncStateStore()
        let folder = Folder(
            name: "Remote folder",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        let remoteChange = try SyncChangeEncoder(deviceID: "remote-device").change(
            for: .createFolder(folder),
            notebookID: NotebookID(rawValue: folder.id.rawValue),
            sequence: 1,
            timestamp: DomainFixtures.fixedDate
        )
        try await provider.push([remoteChange])
        let model = AppModel(
            repository: repository,
            syncProvider: provider,
            syncStateStore: stateStore,
            deviceID: "receiving-device",
            automaticallyRestore: false
        )

        let syncTask = Task { await model.synchronize() }
        await repository.waitUntilSaveStarted()
        for _ in 0..<100 { await Task.yield() }

        let duringSave = await stateStore.load()
        XCTAssertEqual(duringSave?.receivedChanges, [remoteChange])

        await repository.resumeSave()
        await syncTask.value

        let savedLibrary = await repository.savedLibrary()
        let afterSave = await stateStore.load()
        XCTAssertEqual(savedLibrary?.folder(id: folder.id), folder)
        XCTAssertTrue(afterSave?.receivedChanges.isEmpty == true)
    }

    @MainActor
    func testRemoteChangesStayQueuedWhenTheLibrarySaveFails() async throws {
        let provider = InMemorySyncProvider()
        let stateStore = InMemorySyncStateStore()
        let folder = Folder(
            name: "Retry folder",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        let remoteChange = try SyncChangeEncoder(deviceID: "remote-device").change(
            for: .createFolder(folder),
            notebookID: NotebookID(rawValue: folder.id.rawValue),
            sequence: 1,
            timestamp: DomainFixtures.fixedDate
        )
        try await provider.push([remoteChange])
        let model = AppModel(
            repository: FailingLibraryRepository(),
            syncProvider: provider,
            syncStateStore: stateStore,
            deviceID: "receiving-device",
            automaticallyRestore: false
        )

        await model.synchronize()

        let savedState = await stateStore.load()
        XCTAssertEqual(savedState?.receivedChanges, [remoteChange])
        XCTAssertNotNil(model.presentedError)
    }

    @MainActor
    func testEchoedLocalChangeWaitsForItsLocalLibrarySave() async {
        let repository = PausingLibraryRepository()
        let stateStore = InMemorySyncStateStore()
        let model = AppModel(
            repository: repository,
            syncProvider: InMemorySyncProvider(),
            syncStateStore: stateStore,
            deviceID: "editing-device",
            automaticallyRestore: false
        )

        model.createFolder()
        await repository.waitUntilSaveStarted()

        var duringSave = await stateStore.load()
        for _ in 0..<100 where duringSave?.receivedChanges.isEmpty != false {
            await Task.yield()
            duringSave = await stateStore.load()
        }
        XCTAssertEqual(duringSave?.receivedChanges.count, 1)

        await repository.resumeSave()
        var afterSave = await stateStore.load()
        for _ in 0..<100 where afterSave?.receivedChanges.isEmpty != true {
            await Task.yield()
            afterSave = await stateStore.load()
        }
        XCTAssertTrue(afterSave?.receivedChanges.isEmpty == true)
    }

    @MainActor
    func testSavedLocalStrokeIsNotAppliedAgainWhenRestartOccursBeforeEchoHandling() async throws {
        let notebook = DomainFixtures.notebook(title: "Local stroke echo")
        let canvas = notebook.canvases[0]
        let layer = canvas.layers[0]
        let stroke = DomainFixtures.stroke(id: StrokeID(), layerID: layer.id)
        let operation = DocumentOperation.addStroke(
            canvasID: canvas.id,
            layerID: layer.id,
            stroke: stroke
        )
        let fixture = try await makePreHandlingLocalEchoFixture(
            operation: operation,
            notebook: notebook
        )
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }

        let savedBeforeRelaunch = try await fixture.documentStore.load(notebookID: notebook.id)
        XCTAssertEqual(savedBeforeRelaunch.notebook.strokeCount(for: stroke.id), 1)
        XCTAssertEqual(
            try SyncChangeEncoder.decodeDocumentAction(fixture.echo),
            SyncedDocumentAction(operation: operation, direction: .apply)
        )

        let offlineModel = makeLocalEchoModel(
            repository: fixture.repository,
            documentStore: fixture.documentStore
        )
        await offlineModel.restoreLibrary()
        let offlineNotebook = try XCTUnwrap(offlineModel.notebook(notebook.id))
        var editedStroke = stroke
        editedStroke.samples[0].point.x += 40
        let editOperation = try DocumentOperation.replacingObjects(
            in: offlineNotebook,
            canvasID: canvas.id,
            objectIDs: [stroke.objectID],
            with: [.stroke(editedStroke)]
        )
        offlineModel.execute(editOperation, on: notebook.id)
        await offlineModel.checkpointDocuments()

        let reopenedModel = makeLocalEchoModel(
            repository: fixture.repository,
            documentStore: fixture.documentStore,
            provider: fixture.provider,
            stateStore: fixture.stateStore
        )
        await reopenedModel.restoreLibrary()

        let reopened = try XCTUnwrap(reopenedModel.notebook(notebook.id))
        let acknowledgedState = try await fixture.stateStore.load()
        XCTAssertEqual(reopened.strokes(for: stroke.id), [editedStroke])
        XCTAssertTrue(acknowledgedState?.receivedChanges.isEmpty == true)
    }

    @MainActor
    func testSavedLocalCanvasInsertIsNotAppliedAgainWhenRestartOccursBeforeEchoHandling() async throws {
        let notebook = DomainFixtures.notebook(title: "Local canvas echo")
        // Fixed timestamps: the change is compared after a JSON round trip, and
        // `Date()` carries sub-millisecond precision that the encoding cannot
        // return exactly, which made this test fail at random.
        let insertedCanvas = Canvas(
            title: "Local canvas",
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        let operation = DocumentOperation.insertCanvas(canvas: insertedCanvas, index: 1)
        let fixture = try await makePreHandlingLocalEchoFixture(
            operation: operation,
            notebook: notebook
        )
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }

        let savedBeforeRelaunch = try await fixture.documentStore.load(notebookID: notebook.id)
        XCTAssertEqual(savedBeforeRelaunch.notebook.canvasCount(for: insertedCanvas.id), 1)
        XCTAssertEqual(
            try SyncChangeEncoder.decodeDocumentAction(fixture.echo),
            SyncedDocumentAction(operation: operation, direction: .apply)
        )

        let offlineModel = makeLocalEchoModel(
            repository: fixture.repository,
            documentStore: fixture.documentStore
        )
        await offlineModel.restoreLibrary()
        offlineModel.renameCanvas(insertedCanvas.id, to: "Renamed offline", in: notebook.id)
        await offlineModel.checkpointDocuments()

        let reopenedModel = makeLocalEchoModel(
            repository: fixture.repository,
            documentStore: fixture.documentStore,
            provider: fixture.provider,
            stateStore: fixture.stateStore
        )
        await reopenedModel.restoreLibrary()

        let reopened = try XCTUnwrap(reopenedModel.notebook(notebook.id))
        let acknowledgedState = try await fixture.stateStore.load()
        XCTAssertEqual(reopened.canvasCount(for: insertedCanvas.id), 1)
        XCTAssertEqual(
            reopened.canvases.first { $0.id == insertedCanvas.id }?.title,
            "Renamed offline"
        )
        XCTAssertTrue(acknowledgedState?.receivedChanges.isEmpty == true)
    }

    @MainActor
    func testBackgroundCheckpointWaitsForTheSyncOutboxSave() async {
        let stateStore = PausingInitialLoadSyncStateStore()
        let model = AppModel(
            repository: LocalLibraryRepository(
                fileURL: FileManager.default.temporaryDirectory
                    .appending(path: UUID().uuidString)
                    .appending(path: "library.json")
            ),
            syncProvider: InMemorySyncProvider(),
            syncStateStore: stateStore,
            deviceID: "editing-device",
            automaticallyRestore: false
        )
        let completion = CheckpointCompletionProbe()

        model.createFolder()
        await stateStore.waitUntilLoadStarted()
        let checkpointTask = Task {
            await model.checkpointDocuments()
            let hasResumed = await stateStore.hasResumed()
            await completion.finish(afterOutboxSave: hasResumed)
        }
        for _ in 0..<100 { await Task.yield() }

        let didFinishBeforeOutboxSave = await completion.isFinished()
        XCTAssertFalse(didFinishBeforeOutboxSave)

        await stateStore.resumeLoad()
        await checkpointTask.value

        let didWaitForOutboxSave = await completion.didFinishAfterOutboxSave
        XCTAssertTrue(
            didWaitForOutboxSave,
            "The background checkpoint returned before the sync outbox had been saved"
        )
        let savedState = await stateStore.load()
        XCTAssertEqual(savedState?.pendingChanges.count, 1)
    }

    @MainActor
    func testNotebookCreationWaitsForItsMissingFolderAndRetries() async throws {
        let provider = InMemorySyncProvider()
        let stateStore = InMemorySyncStateStore()
        let parent = Folder(
            name: "Parent",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        var notebook = DomainFixtures.notebook()
        notebook.parentFolderID = parent.id
        let encoder = SyncChangeEncoder(deviceID: "remote-device")
        let notebookChange = try encoder.change(
            for: .createNotebook(notebook),
            notebookID: notebook.id,
            sequence: 1,
            timestamp: DomainFixtures.fixedDate
        )
        try await provider.push([notebookChange])
        let model = AppModel(
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

        await model.synchronize()

        XCTAssertNil(model.library.notebook(id: notebook.id))
        let stateWaitingForFolder = await stateStore.load()
        XCTAssertEqual(stateWaitingForFolder?.receivedChanges, [notebookChange])

        let folderChange = try encoder.change(
            for: .createFolder(parent),
            notebookID: NotebookID(rawValue: parent.id.rawValue),
            sequence: 2,
            timestamp: DomainFixtures.fixedDate.addingTimeInterval(1)
        )
        try await provider.push([folderChange])
        await model.synchronize()

        XCTAssertEqual(model.library.folder(id: parent.id), parent)
        XCTAssertEqual(model.library.notebook(id: notebook.id), notebook)
        let stateAfterRetry = await stateStore.load()
        XCTAssertTrue(stateAfterRetry?.receivedChanges.isEmpty == true)
    }

    @MainActor
    private func makePreHandlingLocalEchoFixture(
        operation: DocumentOperation,
        notebook: Notebook
    ) async throws -> PreHandlingLocalEchoFixture {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        let provider = InMemorySyncProvider()
        let stateStore = LocalSyncStateStore(directoryURL: directoryURL.appending(path: "Sync"))
        try await repository.save(LibraryState(notebooks: [notebook]))
        try await documentStore.save(
            NativeNotebookPackage(schemaVersion: .current, notebook: notebook)
        )
        let editingModel = makeLocalEchoModel(
            repository: repository,
            documentStore: documentStore
        )
        await editingModel.restoreLibrary()

        editingModel.execute(operation, on: notebook.id)
        await editingModel.checkpointDocuments()
        let savedPackage = try await documentStore.load(notebookID: notebook.id)
        XCTAssertTrue(savedPackage.appliedRemoteChangeIDs.isEmpty)
        let echo = try SyncChangeEncoder(deviceID: "editing-device").change(
            for: operation,
            notebookID: notebook.id,
            sequence: 1,
            timestamp: DomainFixtures.fixedDate
        )
        let syncEngine = SyncEngine(provider: provider, stateStore: stateStore)
        await syncEngine.enqueue(echo)
        await syncEngine.synchronize()
        let storedState = try await stateStore.load()
        let interruptedState = try XCTUnwrap(storedState)
        XCTAssertEqual(interruptedState.receivedChanges, [echo])

        return PreHandlingLocalEchoFixture(
            directoryURL: directoryURL,
            repository: repository,
            documentStore: documentStore,
            provider: provider,
            stateStore: stateStore,
            echo: echo
        )
    }

    @MainActor
    private func makeLocalEchoModel(
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
            deviceID: "editing-device",
            recognitionCoordinator: HandwritingRecognitionCoordinator(
                recognizer: LocalEchoTestRecognizer()
            ),
            automaticallyRestore: false
        )
    }
}

private struct LocalEchoTestRecognizer: HandwritingRecognizer {
    func recognize(strokes: [Stroke]) async throws -> HandwritingRecognitionResult {
        throw CocoaError(.featureUnsupported)
    }
}

private struct PreHandlingLocalEchoFixture {
    let directoryURL: URL
    let repository: LocalLibraryRepository
    let documentStore: LocalDocumentStore
    let provider: InMemorySyncProvider
    let stateStore: LocalSyncStateStore
    let echo: DocumentChange
}

private extension Notebook {
    func strokeCount(for id: StrokeID) -> Int {
        strokes(for: id).count
    }

    func strokes(for id: StrokeID) -> [Stroke] {
        canvases
            .flatMap(\.layers)
            .flatMap(\.objects)
            .compactMap(\.strokeValue)
            .filter { $0.id == id }
    }

    func canvasCount(for id: CanvasID) -> Int {
        canvases.filter { $0.id == id }.count
    }
}

private actor PausingLibraryRepository: LibraryRepository {
    private var saved: LibraryState?
    private var saveContinuation: CheckedContinuation<Void, Never>?
    private var saveWaiters: [CheckedContinuation<Void, Never>] = []

    func load() async throws -> LibraryState {
        saved ?? LibraryState()
    }

    func save(_ library: LibraryState) async throws {
        saved = library
        saveWaiters.forEach { $0.resume() }
        saveWaiters.removeAll()
        await withCheckedContinuation { saveContinuation = $0 }
    }

    func waitUntilSaveStarted() async {
        guard saved == nil else { return }
        await withCheckedContinuation { saveWaiters.append($0) }
    }

    func resumeSave() {
        saveContinuation?.resume()
        saveContinuation = nil
    }

    func savedLibrary() -> LibraryState? {
        saved
    }
}

private actor FailingLibraryRepository: LibraryRepository {
    func load() async throws -> LibraryState {
        LibraryState()
    }

    func save(_ library: LibraryState) async throws {
        throw CocoaError(.fileWriteUnknown)
    }
}

private actor PausingInitialLoadSyncStateStore: SyncStateStore {
    private var snapshot: SyncEngineSnapshot?
    private var hasStartedLoading = false
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []
    private var hasResumedLoad = false

    func load() async -> SyncEngineSnapshot? {
        guard !hasStartedLoading else { return snapshot }
        hasStartedLoading = true
        loadWaiters.forEach { $0.resume() }
        loadWaiters.removeAll()
        await withCheckedContinuation { loadContinuation = $0 }
        return snapshot
    }

    func save(_ snapshot: SyncEngineSnapshot) {
        self.snapshot = snapshot
    }

    func waitUntilLoadStarted() async {
        guard !hasStartedLoading else { return }
        await withCheckedContinuation { loadWaiters.append($0) }
    }

    func resumeLoad() {
        hasResumedLoad = true
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func hasResumed() -> Bool {
        hasResumedLoad
    }
}

private actor CheckpointCompletionProbe {
    private var didFinish = false
    private(set) var didFinishAfterOutboxSave = false

    func finish(afterOutboxSave: Bool) {
        didFinish = true
        didFinishAfterOutboxSave = afterOutboxSave
    }

    func isFinished() -> Bool {
        didFinish
    }
}
