import XCTest
@testable import NoteNerds

final class LocalDocumentStoreBehaviorTests: XCTestCase {
    private enum SimulatedInterruption: Error {
        case afterSnapshotWrite
    }

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

    func testLegacyJournalDoesNotRepeatAStrokeAlreadySavedInTheSnapshot() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let canvas = Canvas(title: "Canvas 1")
        let layer = canvas.layers[0]
        let stroke = DomainFixtures.stroke(layerID: layer.id)
        var notebook = Notebook(title: "Interrupted checkpoint", canvases: [canvas])
        notebook.canvases[0].layers[0].objects = [.stroke(stroke)]
        let package = NativeNotebookPackage(schemaVersion: .current, notebook: notebook)
        let operation = DocumentOperation.replaceObjects(
            canvasID: canvas.id,
            before: [],
            after: [
                ObjectPlacement(
                    layerID: layer.id,
                    index: Int.max,
                    object: .stroke(stroke)
                )
            ]
        )
        try writeLegacySnapshot(package, rootURL: rootURL)
        try writeLegacyJournal(operation, notebookID: notebook.id, rootURL: rootURL)
        try setLegacyFileDates(
            snapshot: Date(timeIntervalSince1970: 2_000),
            journal: Date(timeIntervalSince1970: 1_000),
            notebookID: notebook.id,
            rootURL: rootURL
        )

        let recovered = try await LocalDocumentStore(rootURL: rootURL).recover(notebookID: notebook.id)

        let recoveredObjects = recovered.notebook.canvases[0].layers[0].objects
        XCTAssertEqual(recoveredObjects.count, 1)
        XCTAssertEqual(recoveredObjects, [.stroke(stroke)])
    }

    func testLegacyJournalPreservesDifferentStrokesThatShareAnIdentifier() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let canvas = Canvas(title: "Canvas 1")
        let layer = canvas.layers[0]
        let sharedID = StrokeID()
        let savedStroke = DomainFixtures.stroke(id: sharedID, layerID: layer.id)
        var journalStroke = savedStroke
        journalStroke.samples[0].point.x += 40
        var notebook = Notebook(title: "Legacy duplicates", canvases: [canvas])
        notebook.canvases[0].layers[0].objects = [.stroke(savedStroke)]
        let package = NativeNotebookPackage(schemaVersion: .current, notebook: notebook)
        let operation = strokeInsertion(journalStroke, canvasID: canvas.id, layerID: layer.id)
        try writeLegacySnapshot(package, rootURL: rootURL)
        try writeLegacyJournal(operation, notebookID: notebook.id, rootURL: rootURL)
        try setLegacyFileDates(
            snapshot: Date(timeIntervalSince1970: 1_000),
            journal: Date(timeIntervalSince1970: 2_000),
            notebookID: notebook.id,
            rootURL: rootURL
        )

        let recovered = try await LocalDocumentStore(rootURL: rootURL).recover(notebookID: notebook.id)

        XCTAssertEqual(
            recovered.notebook.canvases[0].layers[0].objects,
            [.stroke(savedStroke), .stroke(journalStroke)]
        )
    }

    func testInterruptedCheckpointDoesNotReplayAnOperationCoveredByItsSnapshot() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let canvas = Canvas(title: "Canvas 1")
        let layer = canvas.layers[0]
        let initialPackage = NativeNotebookPackage(
            schemaVersion: .current,
            notebook: Notebook(title: "Sequenced journal", canvases: [canvas])
        )
        let stroke = DomainFixtures.stroke(layerID: layer.id)
        let operation = strokeInsertion(stroke, canvasID: canvas.id, layerID: layer.id)
        let setupStore = LocalDocumentStore(rootURL: rootURL)
        try await setupStore.save(initialPackage)
        try await setupStore.append(operation, notebookID: initialPackage.notebook.id)
        let interruptedStore = LocalDocumentStore(
            rootURL: rootURL,
            afterSnapshotWrite: { throw SimulatedInterruption.afterSnapshotWrite }
        )
        let recoveredBeforeCheckpoint = try await interruptedStore.recover(
            notebookID: initialPackage.notebook.id
        )

        do {
            try await interruptedStore.save(recoveredBeforeCheckpoint)
            XCTFail("Expected the simulated interruption")
        } catch SimulatedInterruption.afterSnapshotWrite {
        }

        let recoveredAfterInterruption = try await LocalDocumentStore(rootURL: rootURL).recover(
            notebookID: initialPackage.notebook.id
        )
        let objects = recoveredAfterInterruption.notebook.canvases[0].layers[0].objects
        XCTAssertEqual(objects.count, 1)
        XCTAssertEqual(objects, [.stroke(stroke)])
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

    func testAppendAfterAnInterruptedFinalJournalWriteKeepsTheNewOperationRecoverable() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let canvas = Canvas(title: "Canvas 1")
        let layer = canvas.layers[0]
        let package = NativeNotebookPackage(
            schemaVersion: .current,
            notebook: Notebook(title: "Interrupted append", canvases: [canvas])
        )
        let firstStroke = DomainFixtures.stroke(layerID: layer.id)
        let secondStroke = DomainFixtures.stroke(layerID: layer.id)
        let store = LocalDocumentStore(rootURL: rootURL)
        try await store.save(package)
        try await store.append(
            strokeInsertion(firstStroke, canvasID: canvas.id, layerID: layer.id),
            notebookID: package.notebook.id
        )
        let journalURL = journalURL(for: package.notebook.id, rootURL: rootURL)
        let handle = try FileHandle(forWritingTo: journalURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"incomplete\":".utf8))
        try handle.close()

        try await store.append(
            strokeInsertion(secondStroke, canvasID: canvas.id, layerID: layer.id),
            notebookID: package.notebook.id
        )
        let recovered = try await store.recover(notebookID: package.notebook.id)

        XCTAssertEqual(
            recovered.notebook.canvases[0].layers[0].objects,
            [.stroke(firstStroke), .stroke(secondStroke)]
        )
    }

    func testAppendAfterACompleteFinalJournalRecordWithoutANewlineKeepsBothOperations() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let canvas = Canvas(title: "Canvas 1")
        let layer = canvas.layers[0]
        let package = NativeNotebookPackage(
            schemaVersion: .current,
            notebook: Notebook(title: "Missing newline", canvases: [canvas])
        )
        let firstStroke = DomainFixtures.stroke(layerID: layer.id)
        let secondStroke = DomainFixtures.stroke(layerID: layer.id)
        let store = LocalDocumentStore(rootURL: rootURL)
        try await store.save(package)
        try await store.append(
            strokeInsertion(firstStroke, canvasID: canvas.id, layerID: layer.id),
            notebookID: package.notebook.id
        )
        let journalURL = journalURL(for: package.notebook.id, rootURL: rootURL)
        var journal = try Data(contentsOf: journalURL)
        XCTAssertEqual(journal.popLast(), 0x0A)
        try journal.write(to: journalURL, options: .atomic)

        let continuingStore = LocalDocumentStore(rootURL: rootURL)
        try await continuingStore.append(
            strokeInsertion(secondStroke, canvasID: canvas.id, layerID: layer.id),
            notebookID: package.notebook.id
        )
        let recovered = try await LocalDocumentStore(rootURL: rootURL).recover(
            notebookID: package.notebook.id
        )

        XCTAssertEqual(
            recovered.notebook.canvases[0].layers[0].objects,
            [.stroke(firstStroke), .stroke(secondStroke)]
        )
    }

    func testLocalSnapshotRejectsANewerDocumentSchema() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let package = NativeNotebookPackage(schemaVersion: .current, notebook: DomainFixtures.notebook())
        let store = LocalDocumentStore(rootURL: rootURL)
        try await store.save(package)
        let snapshotURL = rootURL
            .appending(path: "Snapshots", directoryHint: .isDirectory)
            .appending(path: "\(package.notebook.id.rawValue.uuidString).notenerds.json")
        let snapshotData = try Data(contentsOf: snapshotURL)
        guard var snapshot = try JSONSerialization.jsonObject(with: snapshotData) as? [String: Any],
              var storedPackage = snapshot["package"] as? [String: Any] else {
            return XCTFail("Expected a local snapshot envelope")
        }
        storedPackage["schemaVersion"] = 999
        snapshot["package"] = storedPackage
        try JSONSerialization.data(withJSONObject: snapshot).write(to: snapshotURL, options: .atomic)

        do {
            _ = try await LocalDocumentStore(rootURL: rootURL).load(notebookID: package.notebook.id)
            XCTFail("Expected the newer document schema to be rejected")
        } catch {
            XCTAssertEqual(error as? NativeDocumentError, .unsupportedNewerVersion(999))
        }
    }

    func testNewerLegacySnapshotDoesNotRepeatAnOlderCanvasMoveJournal() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let firstCanvas = Canvas(title: "First")
        let secondCanvas = Canvas(title: "Second")
        let notebook = Notebook(title: "Moved", canvases: [secondCanvas, firstCanvas])
        let package = NativeNotebookPackage(schemaVersion: .current, notebook: notebook)
        let operation = DocumentOperation.moveCanvas(sourceIndex: 0, destinationIndex: 1)
        try writeLegacySnapshot(package, rootURL: rootURL)
        try writeLegacyJournal(operation, notebookID: notebook.id, rootURL: rootURL)
        try setLegacyFileDates(
            snapshot: Date(timeIntervalSince1970: 2_000),
            journal: Date(timeIntervalSince1970: 1_000),
            notebookID: notebook.id,
            rootURL: rootURL
        )

        let recovered = try await LocalDocumentStore(rootURL: rootURL).recover(notebookID: notebook.id)
        let recoveredAgain = try await LocalDocumentStore(rootURL: rootURL).recover(notebookID: notebook.id)

        XCTAssertEqual(recovered.notebook.canvases.map(\.id), [secondCanvas.id, firstCanvas.id])
        XCTAssertEqual(recoveredAgain.notebook.canvases.map(\.id), [secondCanvas.id, firstCanvas.id])
    }

    func testNewerLegacyJournalReplaysACanvasMoveAfterAnOlderSnapshot() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let firstCanvas = Canvas(title: "First")
        let secondCanvas = Canvas(title: "Second")
        let notebook = Notebook(title: "Pending move", canvases: [firstCanvas, secondCanvas])
        let package = NativeNotebookPackage(schemaVersion: .current, notebook: notebook)
        let operation = DocumentOperation.moveCanvas(sourceIndex: 0, destinationIndex: 1)
        try writeLegacySnapshot(package, rootURL: rootURL)
        try writeLegacyJournal(operation, notebookID: notebook.id, rootURL: rootURL)
        try setLegacyFileDates(
            snapshot: Date(timeIntervalSince1970: 1_000),
            journal: Date(timeIntervalSince1970: 2_000),
            notebookID: notebook.id,
            rootURL: rootURL
        )

        let recovered = try await LocalDocumentStore(rootURL: rootURL).recover(notebookID: notebook.id)
        let recoveredAgain = try await LocalDocumentStore(rootURL: rootURL).recover(notebookID: notebook.id)

        XCTAssertEqual(recovered.notebook.canvases.map(\.id), [secondCanvas.id, firstCanvas.id])
        XCTAssertEqual(recoveredAgain.notebook.canvases.map(\.id), [secondCanvas.id, firstCanvas.id])
    }

    private func strokeInsertion(
        _ stroke: Stroke,
        canvasID: CanvasID,
        layerID: LayerID
    ) -> DocumentOperation {
        .replaceObjects(
            canvasID: canvasID,
            before: [],
            after: [
                ObjectPlacement(
                    layerID: layerID,
                    index: Int.max,
                    object: .stroke(stroke)
                )
            ]
        )
    }

    private func writeLegacyJournal(
        _ operation: DocumentOperation,
        notebookID: NotebookID,
        rootURL: URL
    ) throws {
        let journalURL = journalURL(for: notebookID, rootURL: rootURL)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        var encoded = try encoder.encode(operation)
        encoded.append(0x0A)
        try encoded.write(to: journalURL, options: .atomic)
    }

    private func writeLegacySnapshot(
        _ package: NativeNotebookPackage,
        rootURL: URL
    ) throws {
        let snapshotsURL = rootURL.appending(path: "Snapshots", directoryHint: .isDirectory)
        let journalsURL = rootURL.appending(path: "Journals", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: journalsURL, withIntermediateDirectories: true)
        let snapshotURL = snapshotsURL
            .appending(path: "\(package.notebook.id.rawValue.uuidString).notenerds.json")
        try NativeDocumentSerializer().encode(package).write(to: snapshotURL, options: .atomic)
    }

    private func setLegacyFileDates(
        snapshot: Date,
        journal: Date,
        notebookID: NotebookID,
        rootURL: URL
    ) throws {
        let snapshotURL = rootURL
            .appending(path: "Snapshots", directoryHint: .isDirectory)
            .appending(path: "\(notebookID.rawValue.uuidString).notenerds.json")
        try FileManager.default.setAttributes([.modificationDate: snapshot], ofItemAtPath: snapshotURL.path())
        try FileManager.default.setAttributes(
            [.modificationDate: journal],
            ofItemAtPath: journalURL(for: notebookID, rootURL: rootURL).path()
        )
    }

    private func journalURL(for notebookID: NotebookID, rootURL: URL) -> URL {
        rootURL
            .appending(path: "Journals", directoryHint: .isDirectory)
            .appending(path: "\(notebookID.rawValue.uuidString).journal")
    }
}
