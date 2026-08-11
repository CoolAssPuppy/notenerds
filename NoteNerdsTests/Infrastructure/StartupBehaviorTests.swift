import XCTest
@testable import NoteNerds

final class StartupBehaviorTests: XCTestCase {
    @MainActor
    func testTrashedLibraryMetadataWinsOverAnOlderActiveNotebookCheckpoint() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentStore = LocalDocumentStore(rootURL: directoryURL.appending(path: "Documents"))
        let activeNotebook = Notebook(
            title: "Older title",
            canvases: [Canvas(title: "Recovered canvas")],
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate,
            lastOpenedAt: DomainFixtures.fixedDate
        )
        var trashedNotebook = activeNotebook
        trashedNotebook.title = "Test Note"
        trashedNotebook.canvases = [Canvas(title: "Stale library canvas")]
        trashedNotebook.modifiedAt = DomainFixtures.fixedDate.addingTimeInterval(30)
        trashedNotebook.lastOpenedAt = DomainFixtures.fixedDate.addingTimeInterval(60)
        trashedNotebook.isFavorite = true
        trashedNotebook.tags = ["keep"]
        let trashDate = DomainFixtures.fixedDate.addingTimeInterval(90)
        trashedNotebook.trashedAt = trashDate
        try await documentStore.save(
            NativeNotebookPackage(schemaVersion: .current, notebook: activeNotebook)
        )
        try await repository.save(LibraryState(notebooks: [trashedNotebook]))

        let reopenedSession = AppModel(
            repository: repository,
            documentStore: documentStore,
            automaticallyRestore: false
        )
        await reopenedSession.restoreLibrary()

        let restoredNotebook = try XCTUnwrap(reopenedSession.notebook(activeNotebook.id))
        XCTAssertEqual(restoredNotebook.title, "Test Note")
        XCTAssertEqual(restoredNotebook.canvases.map(\.title), ["Recovered canvas"])
        XCTAssertEqual(restoredNotebook.modifiedAt, trashedNotebook.modifiedAt)
        XCTAssertEqual(restoredNotebook.lastOpenedAt, trashedNotebook.lastOpenedAt)
        XCTAssertTrue(restoredNotebook.isFavorite)
        XCTAssertEqual(restoredNotebook.tags, ["keep"])
        XCTAssertEqual(restoredNotebook.trashedAt, trashDate)
        XCTAssertFalse(reopenedSession.visibleNotebooks.contains { $0.id == activeNotebook.id })
    }

    @MainActor
    func testLocalLibraryOpensWhileInitialCloudSyncIsStillWaiting() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let notebook = DomainFixtures.notebook(title: "Available offline")
        try await repository.save(LibraryState(notebooks: [notebook]))
        let provider = PausingInitialSyncProvider()
        let model = AppModel(
            repository: repository,
            syncProvider: provider,
            automaticallyRestore: false
        )

        let localRestoreFinished = expectation(description: "Local restore finished")
        let restoreTask = Task {
            await model.restoreLocalLibrary()
            localRestoreFinished.fulfill()
        }
        await provider.waitUntilStart()

        XCTAssertTrue(model.hasRestoredLibrary)
        XCTAssertEqual(model.library.notebook(id: notebook.id), notebook)
        await fulfillment(of: [localRestoreFinished], timeout: 0.2)

        await provider.resumeStart()
        await restoreTask.value
    }
}

private actor PausingInitialSyncProvider: SyncProvider {
    nonisolated let identifier = "pausing-initial-sync"
    private var hasStarted = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func start() async {
        hasStarted = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { startContinuation = $0 }
    }

    func push(_ changes: [DocumentChange]) async throws {}

    func pull(since cursor: SyncCursor?) async throws -> SyncBatch {
        SyncBatch(changes: [], cursor: cursor)
    }

    func uploadAsset(_ asset: DocumentAsset) async throws {}

    func fetchAsset(_ id: AssetID) async throws -> Data {
        throw CocoaError(.fileNoSuchFile)
    }

    func waitUntilStart() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func resumeStart() {
        startContinuation?.resume()
        startContinuation = nil
    }
}
