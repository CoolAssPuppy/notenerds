import Foundation
import XCTest
@testable import NoteNerds

@MainActor
extension AppSessionPersistenceBehaviorTests {
    func testBackgroundCheckpointWaitsForInkQueuedWhileItsSaveIsRunning() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let snapshotWriteStarted = expectation(description: "snapshot write started")
        let journalWriteStarted = expectation(description: "journal write started")
        let scenario = try await backgroundCheckpointScenario(
            directoryURL: directoryURL,
            snapshotWriteStarted: snapshotWriteStarted,
            journalWriteStarted: journalWriteStarted
        )

        var didFinishCheckpoint = false
        let checkpointTask = Task {
            await scenario.model.checkpointDocuments()
            didFinishCheckpoint = true
        }
        await fulfillment(of: [snapshotWriteStarted], timeout: 1)

        let canvas = try XCTUnwrap(scenario.notebook.canvases.first)
        let layer = try XCTUnwrap(canvas.layers.first)
        let newStroke = DomainFixtures.stroke(id: StrokeID(), layerID: layer.id)
        scenario.model.execute(
            .addStroke(canvasID: canvas.id, layerID: layer.id, stroke: newStroke),
            on: scenario.notebook.id
        )

        scenario.writeGate.allowSnapshotWrite()
        await fulfillment(of: [journalWriteStarted], timeout: 1)
        XCTAssertFalse(didFinishCheckpoint)
        scenario.writeGate.allowJournalWrite()
        await checkpointTask.value
        XCTAssertTrue(didFinishCheckpoint)

        let restoredModel = AppModel(
            repository: scenario.repository,
            documentStore: LocalDocumentStore(rootURL: scenario.documentRootURL),
            automaticallyRestore: false
        )
        await restoredModel.restoreLibrary()

        let restoredNotebook = try XCTUnwrap(restoredModel.notebook(scenario.notebook.id))
        XCTAssertTrue(restoredNotebook.canvases.flatMap(\.layers).flatMap(\.objects).contains(.stroke(newStroke)))
    }

    private func backgroundCheckpointScenario(
        directoryURL: URL,
        snapshotWriteStarted: XCTestExpectation,
        journalWriteStarted: XCTestExpectation
    ) async throws -> BackgroundCheckpointScenario {
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentRootURL = directoryURL.appending(path: "Documents")
        let setupStore = LocalDocumentStore(rootURL: documentRootURL)
        let notebook = DomainFixtures.notebook(id: NotebookID(), title: "Notebook")
        let initialLibrary = LibraryState(notebooks: [notebook])
        try await repository.save(initialLibrary)
        try await setupStore.save(NativeNotebookPackage(schemaVersion: .current, notebook: notebook))
        let writeGate = CheckpointDocumentWriteGate(
            snapshotWriteStarted: snapshotWriteStarted,
            journalWriteStarted: journalWriteStarted
        )
        let store = LocalDocumentStore(
            rootURL: documentRootURL,
            afterSnapshotWrite: writeGate.afterSnapshotWrite,
            afterJournalWrite: writeGate.afterJournalWrite
        )
        let model = AppModel(repository: repository, documentStore: store, automaticallyRestore: false)
        model.library = initialLibrary
        model.scheduleDeferredCheckpoint(for: notebook.id)
        return BackgroundCheckpointScenario(
            repository: repository,
            documentRootURL: documentRootURL,
            store: store,
            notebook: notebook,
            model: model,
            writeGate: writeGate
        )
    }
}

private struct BackgroundCheckpointScenario {
    let repository: LocalLibraryRepository
    let documentRootURL: URL
    let store: LocalDocumentStore
    let notebook: Notebook
    let model: AppModel
    let writeGate: CheckpointDocumentWriteGate
}

private final class CheckpointDocumentWriteGate: @unchecked Sendable {
    private let snapshotWriteStarted: XCTestExpectation
    private let journalWriteStarted: XCTestExpectation
    private let snapshotWritePermission = DispatchSemaphore(value: 0)
    private let journalWritePermission = DispatchSemaphore(value: 0)

    init(
        snapshotWriteStarted: XCTestExpectation,
        journalWriteStarted: XCTestExpectation
    ) {
        self.snapshotWriteStarted = snapshotWriteStarted
        self.journalWriteStarted = journalWriteStarted
    }

    func afterSnapshotWrite() {
        snapshotWriteStarted.fulfill()
        snapshotWritePermission.wait()
    }

    func afterJournalWrite() {
        journalWriteStarted.fulfill()
        journalWritePermission.wait()
    }

    func allowSnapshotWrite() {
        snapshotWritePermission.signal()
    }

    func allowJournalWrite() {
        journalWritePermission.signal()
    }
}
