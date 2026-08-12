import Foundation
import XCTest
@testable import NoteNerds

/// Guards the writing path against the work that made ink stall on device.
///
/// A trace from an iPad showed full notebook snapshots of 100–500ms landing in
/// the middle of live Pencil contacts, triggered by handwriting recognition,
/// including for notebooks that were not open. These tests fail if that returns.
@MainActor
final class WritingLatencyBehaviorTests: XCTestCase {
    func testNoSnapshotIsWrittenWhileStrokesAreStillArriving() async throws {
        let context = try makeContext(title: "Live writing")
        defer { context.removeDirectory() }
        let canvas = context.notebook.canvases[0]
        let layer = canvas.layers[0]

        context.model.scheduleDeferredCheckpoint(for: context.notebook.id)
        for _ in 0..<6 {
            try await Task.sleep(for: .milliseconds(25))
            _ = context.model.addStrokes(
                [DomainFixtures.stroke(id: StrokeID(), layerID: layer.id)],
                to: context.notebook.id,
                canvasID: canvas.id,
                layerID: layer.id
            )
        }
        await context.model.waitForDocumentPersistenceToFinish()

        XCTAssertEqual(
            context.snapshotWrites.count,
            0,
            "A full notebook snapshot was written between strokes"
        )
    }

    func testCompactingTheJournalDoesNotInterruptWriting() async throws {
        let context = try makeContext(title: "Journal rollover")
        defer { context.removeDirectory() }
        let canvas = context.notebook.canvases[0]
        let layer = canvas.layers[0]

        // Past the point where the journal is compacted into a snapshot. That
        // compaction used to run inline, so roughly a paragraph of handwriting
        // put a whole-notebook write back on the writing path.
        for _ in 0..<25 {
            _ = context.model.addStrokes(
                [DomainFixtures.stroke(id: StrokeID(), layerID: layer.id)],
                to: context.notebook.id,
                canvasID: canvas.id,
                layerID: layer.id
            )
        }
        await context.model.waitForDocumentPersistenceToFinish()

        XCTAssertEqual(
            context.snapshotWrites.count,
            0,
            "Compacting the journal wrote a whole notebook while strokes were arriving"
        )
    }

    func testADeferredSnapshotIsWrittenOnceWritingStops() async throws {
        let context = try makeContext(title: "Quiet after writing")
        defer { context.removeDirectory() }

        context.model.scheduleDeferredCheckpoint(for: context.notebook.id)
        try await Task.sleep(for: .milliseconds(220))
        await context.model.waitForDocumentPersistenceToFinish()

        XCTAssertEqual(context.snapshotWrites.count, 1)
    }

    func testADeferredSnapshotWaitsForALivePencilContactToEnd() async throws {
        let context = try makeContext(title: "Long Pencil contact")
        defer { context.removeDirectory() }
        let canvasID = context.notebook.canvases[0].id

        context.model.pencilContactBegan(on: canvasID)
        context.model.scheduleDeferredCheckpoint(for: context.notebook.id)
        try await Task.sleep(for: .milliseconds(220))
        await context.model.waitForDocumentPersistenceToFinish()

        XCTAssertEqual(context.snapshotWrites.count, 0)

        context.model.pencilContactEnded(on: canvasID)
        try await Task.sleep(for: .milliseconds(220))
        await context.model.waitForDocumentPersistenceToFinish()

        XCTAssertEqual(context.snapshotWrites.count, 1)
    }

    func testADirectCheckpointRequestWaitsForALivePencilContactToEnd() async throws {
        let context = try makeContext(title: "Direct checkpoint")
        defer { context.removeDirectory() }
        let canvasID = context.notebook.canvases[0].id

        context.model.pencilContactBegan(on: canvasID)
        context.model.persistCheckpoint(context.notebook)
        await context.model.waitForDocumentPersistenceToFinish()

        XCTAssertEqual(context.snapshotWrites.count, 0)

        context.model.pencilContactEnded(on: canvasID)
        try await Task.sleep(for: .milliseconds(220))
        await context.model.waitForDocumentPersistenceToFinish()

        XCTAssertEqual(context.snapshotWrites.count, 1)
    }

    func testBackgroundCheckpointCannotStartBeforePencilSnapshotFlushEndsTheContact() async throws {
        let context = try makeContext(title: "Background contact")
        defer { context.removeDirectory() }
        let canvasID = context.notebook.canvases[0].id

        context.model.pencilContactBegan(on: canvasID)
        await context.model.checkpointDocuments()

        XCTAssertEqual(context.snapshotWrites.count, 0)

        context.model.pencilContactEnded(on: canvasID)
        await context.model.checkpointDocuments()

        XCTAssertGreaterThanOrEqual(context.snapshotWrites.count, 1)
    }

    func testRemoteSyncWaitsForALivePencilContactBeforeWritingANotebook() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let repository = LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json"))
        let documentRootURL = directoryURL.appending(path: "Documents")
        let notebook = DomainFixtures.notebook(id: NotebookID(), title: "Remote sync")
        try await repository.save(LibraryState(notebooks: [notebook]))
        try await LocalDocumentStore(rootURL: documentRootURL).save(
            NativeNotebookPackage(schemaVersion: .current, notebook: notebook)
        )
        let writes = SnapshotWriteCounter()
        let provider = InMemorySyncProvider()
        let canvas = notebook.canvases[0]
        let layer = canvas.layers[0]
        let stroke = DomainFixtures.stroke(id: StrokeID(), layerID: layer.id)
        let change = try SyncChangeEncoder(deviceID: "remote").change(
            for: .addStroke(canvasID: canvas.id, layerID: layer.id, stroke: stroke),
            notebookID: notebook.id,
            sequence: 1
        )
        try await provider.push([change])
        let model = AppModel(
            repository: repository,
            documentStore: LocalDocumentStore(rootURL: documentRootURL, afterSnapshotWrite: { writes.record() }),
            syncProvider: provider,
            syncStateStore: LocalSyncStateStore(directoryURL: directoryURL.appending(path: "Sync")),
            automaticallyRestore: false
        )
        model.library = LibraryState(notebooks: [notebook])

        model.pencilContactBegan(on: canvas.id)
        await model.synchronize()

        XCTAssertEqual(writes.count, 0)
        XCTAssertFalse(model.notebook(notebook.id)?.canvases[0].layers[0].objects.contains(.stroke(stroke)) == true)

        model.pencilContactEnded(on: canvas.id)
        await model.synchronize()

        XCTAssertTrue(model.notebook(notebook.id)?.canvases[0].layers[0].objects.contains(.stroke(stroke)) == true)
        XCTAssertGreaterThanOrEqual(writes.count, 1)
    }

    func testUndoSurvivesTerminationBeforeADeferredCheckpoint() async throws {
        let context = try makeContext(title: "Undo recovery", deferredCheckpointDelay: .seconds(30))
        defer { context.removeDirectory() }
        let canvas = context.notebook.canvases[0]
        let layer = canvas.layers[0]
        await context.model.checkpointDocuments()
        let stroke = DomainFixtures.stroke(id: StrokeID(), layerID: layer.id)
        _ = context.model.addStrokes(
            [stroke],
            to: context.notebook.id,
            canvasID: canvas.id,
            layerID: layer.id
        )
        context.model.undo(context.notebook.id)
        await context.model.waitForDocumentPersistenceToFinish()

        let recovered = try await LocalDocumentStore(rootURL: context.documentRootURL)
            .recover(notebookID: context.notebook.id)

        XCTAssertFalse(recovered.notebook.canvases[0].layers[0].objects.contains(.stroke(stroke)))
    }

    func testRedoSurvivesTerminationBeforeADeferredCheckpoint() async throws {
        let context = try makeContext(title: "Redo recovery", deferredCheckpointDelay: .seconds(30))
        defer { context.removeDirectory() }
        let canvas = context.notebook.canvases[0]
        let layer = canvas.layers[0]
        await context.model.checkpointDocuments()
        let stroke = DomainFixtures.stroke(id: StrokeID(), layerID: layer.id)
        _ = context.model.addStrokes(
            [stroke],
            to: context.notebook.id,
            canvasID: canvas.id,
            layerID: layer.id
        )
        context.model.undo(context.notebook.id)
        await context.model.checkpointDocuments()
        context.model.redo(context.notebook.id)
        await context.model.waitForDocumentPersistenceToFinish()

        let recovered = try await LocalDocumentStore(rootURL: context.documentRootURL)
            .recover(notebookID: context.notebook.id)

        XCTAssertTrue(recovered.notebook.canvases[0].layers[0].objects.contains(.stroke(stroke)))
    }

    func testRepeatedRecognitionResultsCoalesceIntoOneWrite() async throws {
        let context = try makeContext(title: "Coalesced")
        defer { context.removeDirectory() }

        for _ in 0..<8 {
            context.model.scheduleDeferredCheckpoint(for: context.notebook.id)
        }
        try await Task.sleep(for: .milliseconds(220))
        await context.model.waitForDocumentPersistenceToFinish()

        XCTAssertEqual(context.snapshotWrites.count, 1)
    }

    func testBackgroundingWritesEverythingStillDeferred() async throws {
        let context = try makeContext(title: "Backgrounded")
        defer { context.removeDirectory() }

        context.model.scheduleDeferredCheckpoint(for: context.notebook.id)
        await context.model.checkpointDocuments()

        XCTAssertGreaterThanOrEqual(context.snapshotWrites.count, 1)
        XCTAssertTrue(context.model.notebookIDsAwaitingCheckpoint.isEmpty)
    }

    func testRecognitionWaitsLongerThanAPauseBetweenWords() throws {
        let context = try makeContext(title: "Delay", recognitionDelay: nil)
        defer { context.removeDirectory() }

        XCTAssertGreaterThanOrEqual(
            context.model.recognitionDelay,
            .seconds(2),
            "A short recognition delay fires between words and stalls writing"
        )
    }

    private func makeContext(
        title: String,
        recognitionDelay: Duration? = .milliseconds(10),
        deferredCheckpointDelay: Duration = .milliseconds(120)
    ) throws -> WritingLatencyContext {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let writes = SnapshotWriteCounter()
        let documentStore = LocalDocumentStore(
            rootURL: directoryURL,
            afterSnapshotWrite: { writes.record() }
        )
        let notebook = DomainFixtures.notebook(title: title)
        let model = AppModel(
            repository: LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json")),
            documentStore: documentStore,
            recognitionDelay: recognitionDelay ?? .seconds(3),
            deferredCheckpointDelay: deferredCheckpointDelay,
            automaticallyRestore: false
        )
        model.library = LibraryState(notebooks: [notebook])
        return WritingLatencyContext(
            model: model,
            notebook: notebook,
            snapshotWrites: writes,
            documentRootURL: directoryURL,
            directoryURL: directoryURL
        )
    }
}

@MainActor
private struct WritingLatencyContext {
    let model: AppModel
    let notebook: Notebook
    let snapshotWrites: SnapshotWriteCounter
    let documentRootURL: URL
    let directoryURL: URL

    func removeDirectory() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

/// Counts snapshot writes from whichever thread the document store runs on.
final class SnapshotWriteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCount = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCount
    }

    func record() {
        lock.lock()
        storedCount += 1
        lock.unlock()
    }
}
