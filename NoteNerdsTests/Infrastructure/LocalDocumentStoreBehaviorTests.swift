import XCTest
@testable import NoteNerds

final class LocalDocumentStoreBehaviorTests: XCTestCase {
    func testSnapshotRoundTripPreservesNotebook() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = LocalDocumentStore(rootURL: rootURL)
        let package = NativeNotebookPackage(schemaVersion: .current, notebook: DomainFixtures.notebook())

        try await store.save(package)
        let restored = try await store.load(notebookID: package.notebook.id)

        XCTAssertEqual(restored, package)
    }

    func testReadableSnapshotLoadsWithoutAFileExistencePreflight() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let package = NativeNotebookPackage(schemaVersion: .current, notebook: DomainFixtures.notebook())
        let encoded = try NativeDocumentSerializer().encode(package)
        let store = LocalDocumentStore(rootURL: rootURL, readData: { _ in encoded })

        let restored = try await store.load(notebookID: package.notebook.id)

        XCTAssertEqual(restored, package)
    }

    func testJournalReplaysCompletedStrokeAfterLastSnapshot() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = LocalDocumentStore(rootURL: rootURL)
        let package = NativeNotebookPackage(
            schemaVersion: .current,
            notebook: Notebook(title: "Journal", canvases: [Canvas(title: "Canvas 1")])
        )
        try await store.save(package)
        let canvas = package.notebook.canvases[0]
        let layer = canvas.layers[0]
        let stroke = DomainFixtures.stroke(layerID: layer.id)
        let operation = DocumentOperation.addStroke(canvasID: canvas.id, layerID: layer.id, stroke: stroke)

        try await store.append(operation, notebookID: package.notebook.id)
        let recovered = try await store.recover(notebookID: package.notebook.id)

        XCTAssertEqual(recovered.notebook.canvases[0].layers[0].objects, [.stroke(stroke)])
    }

    func testRecoveryIgnoresOnlyAnInterruptedFinalJournalWrite() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = LocalDocumentStore(rootURL: rootURL)
        let package = NativeNotebookPackage(
            schemaVersion: .current,
            notebook: Notebook(title: "Journal", canvases: [Canvas(title: "Canvas 1")])
        )
        try await store.save(package)
        let canvas = package.notebook.canvases[0]
        let layer = canvas.layers[0]
        let stroke = DomainFixtures.stroke(layerID: layer.id)
        try await store.append(
            .addStroke(canvasID: canvas.id, layerID: layer.id, stroke: stroke),
            notebookID: package.notebook.id
        )
        let journalURL = rootURL
            .appending(path: "Journals", directoryHint: .isDirectory)
            .appending(path: "\(package.notebook.id.rawValue.uuidString).journal")
        let handle = try FileHandle(forWritingTo: journalURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"incomplete\":".utf8))
        try handle.close()

        let recovered = try await store.recover(notebookID: package.notebook.id)

        XCTAssertEqual(recovered.notebook.canvases[0].layers[0].objects, [.stroke(stroke)])
    }
}
