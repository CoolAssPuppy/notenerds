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
            await completion.finish()
        }
        for _ in 0..<100 { await Task.yield() }

        let didFinishBeforeOutboxSave = await completion.isFinished()
        XCTAssertFalse(didFinishBeforeOutboxSave)

        await stateStore.resumeLoad()
        await checkpointTask.value

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
        loadContinuation?.resume()
        loadContinuation = nil
    }
}

private actor CheckpointCompletionProbe {
    private var didFinish = false

    func finish() {
        didFinish = true
    }

    func isFinished() -> Bool {
        didFinish
    }
}
