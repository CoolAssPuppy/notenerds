import XCTest
@testable import NoteNerds

final class StartupBehaviorTests: XCTestCase {
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
