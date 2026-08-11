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

    func testADeferredSnapshotIsWrittenOnceWritingStops() async throws {
        let context = try makeContext(title: "Quiet after writing")
        defer { context.removeDirectory() }

        context.model.scheduleDeferredCheckpoint(for: context.notebook.id)
        try await Task.sleep(for: .milliseconds(220))
        await context.model.waitForDocumentPersistenceToFinish()

        XCTAssertEqual(context.snapshotWrites.count, 1)
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
        recognitionDelay: Duration? = .milliseconds(10)
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
            deferredCheckpointDelay: .milliseconds(120),
            automaticallyRestore: false
        )
        model.library = LibraryState(notebooks: [notebook])
        return WritingLatencyContext(
            model: model,
            notebook: notebook,
            snapshotWrites: writes,
            directoryURL: directoryURL
        )
    }
}

@MainActor
private struct WritingLatencyContext {
    let model: AppModel
    let notebook: Notebook
    let snapshotWrites: SnapshotWriteCounter
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
