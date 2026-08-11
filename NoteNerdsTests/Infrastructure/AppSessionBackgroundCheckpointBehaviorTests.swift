import Foundation
import XCTest
@testable import NoteNerds

@MainActor
extension AppSessionPersistenceBehaviorTests {
    func testBackgroundCheckpointWaitsForInkQueuedWhileItsSaveIsRunning() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let firstReadStarted = expectation(description: "first document store read started")
        let secondReadStarted = expectation(description: "second document store read started")
        let scenario = try await backgroundCheckpointScenario(
            directoryURL: directoryURL,
            firstReadStarted: firstReadStarted,
            secondReadStarted: secondReadStarted
        )

        let blockedReadTask = Task.detached {
            try await scenario.store.load(notebookID: scenario.notebook.id)
        }
        await fulfillment(of: [firstReadStarted], timeout: 1)

        var didFinishCheckpoint = false
        let checkpointTask = Task {
            await scenario.model.checkpointDocuments()
            didFinishCheckpoint = true
        }
        for _ in 0..<10 { await Task.yield() }

        let secondBlockedReadTask = Task.detached {
            try await scenario.store.load(notebookID: scenario.notebook.id)
        }
        for _ in 0..<10 { await Task.yield() }

        let canvas = try XCTUnwrap(scenario.notebook.canvases.first)
        let layer = try XCTUnwrap(canvas.layers.first)
        let newStroke = DomainFixtures.stroke(id: StrokeID(), layerID: layer.id)
        scenario.model.execute(
            .addStroke(canvasID: canvas.id, layerID: layer.id, stroke: newStroke),
            on: scenario.notebook.id
        )
        for _ in 0..<10 { await Task.yield() }

        scenario.readGate.allowFirstRead()
        await fulfillment(of: [secondReadStarted], timeout: 1)
        try? await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(didFinishCheckpoint)
        scenario.readGate.allowSecondRead()
        _ = try await blockedReadTask.value
        _ = try await secondBlockedReadTask.value
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
        firstReadStarted: XCTestExpectation,
        secondReadStarted: XCTestExpectation
    ) async throws -> BackgroundCheckpointScenario {
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentRootURL = directoryURL.appending(path: "Documents")
        let setupStore = LocalDocumentStore(rootURL: documentRootURL)
        let notebook = DomainFixtures.notebook(id: NotebookID(), title: "Notebook")
        let initialLibrary = LibraryState(notebooks: [notebook])
        try await repository.save(initialLibrary)
        try await setupStore.save(NativeNotebookPackage(schemaVersion: .current, notebook: notebook))
        let readGate = CheckpointDocumentReadGate(
            firstReadStarted: firstReadStarted,
            secondReadStarted: secondReadStarted
        )
        let store = LocalDocumentStore(rootURL: documentRootURL, readData: readGate.read)
        let model = AppModel(repository: repository, documentStore: store, automaticallyRestore: false)
        model.library = initialLibrary
        return BackgroundCheckpointScenario(
            repository: repository,
            documentRootURL: documentRootURL,
            store: store,
            notebook: notebook,
            model: model,
            readGate: readGate
        )
    }
}

private struct BackgroundCheckpointScenario {
    let repository: LocalLibraryRepository
    let documentRootURL: URL
    let store: LocalDocumentStore
    let notebook: Notebook
    let model: AppModel
    let readGate: CheckpointDocumentReadGate
}

private final class CheckpointDocumentReadGate: @unchecked Sendable {
    private let firstReadStarted: XCTestExpectation
    private let secondReadStarted: XCTestExpectation
    private let firstReadPermission = DispatchSemaphore(value: 0)
    private let secondReadPermission = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var readCount = 0

    init(
        firstReadStarted: XCTestExpectation,
        secondReadStarted: XCTestExpectation
    ) {
        self.firstReadStarted = firstReadStarted
        self.secondReadStarted = secondReadStarted
    }

    func read(_ url: URL) throws -> Data {
        lock.lock()
        readCount += 1
        let currentRead = readCount
        lock.unlock()

        if currentRead == 1 {
            firstReadStarted.fulfill()
            firstReadPermission.wait()
        } else if currentRead == 2 {
            secondReadStarted.fulfill()
            secondReadPermission.wait()
        }
        return try Data(contentsOf: url)
    }

    func allowFirstRead() {
        firstReadPermission.signal()
    }

    func allowSecondRead() {
        secondReadPermission.signal()
    }
}
