import XCTest
@testable import NoteNerds

final class JournalSidecarBehaviorTests: XCTestCase {
    func testJournalKeepsPencilKitArchiveBytesOutOfTheLog() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = LocalDocumentStore(rootURL: rootURL)
        let package = NativeNotebookPackage(
            schemaVersion: .current,
            notebook: Notebook(title: "Sidecar", canvases: [Canvas(title: "Canvas 1")])
        )
        try await store.save(package)
        let canvas = package.notebook.canvases[0]
        let layer = canvas.layers[0]
        let archiveData = Data((0..<2_048).map { UInt8(truncatingIfNeeded: $0 &* 17) })
        let stroke = archivedStroke(layerID: layer.id, archiveData: archiveData)

        try await store.append(
            .addStroke(canvasID: canvas.id, layerID: layer.id, stroke: stroke),
            notebookID: package.notebook.id
        )

        let journal = try Data(contentsOf: journalURL(for: package.notebook.id, rootURL: rootURL))
        let sidecar = try Data(contentsOf: sidecarURL(for: package.notebook.id, sequence: 1, rootURL: rootURL))
        XCTAssertNil(journal.range(of: archiveData))
        XCTAssertNil(
            String(data: journal, encoding: .utf8)?
                .range(of: archiveData.base64EncodedString())
        )
        XCTAssertNotNil(sidecar.range(of: archiveData))

        let recovered = try await store.recover(notebookID: package.notebook.id)
        XCTAssertEqual(
            firstStroke(in: recovered)?.pencilKitArchive?.data,
            archiveData
        )
    }

    func testCheckpointRemovesJournalSidecars() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = LocalDocumentStore(rootURL: rootURL)
        let package = NativeNotebookPackage(
            schemaVersion: .current,
            notebook: Notebook(title: "Compacted", canvases: [Canvas(title: "Canvas 1")])
        )
        try await store.save(package)
        let canvas = package.notebook.canvases[0]
        let layer = canvas.layers[0]
        let stroke = archivedStroke(
            layerID: layer.id,
            archiveData: Data(repeating: 0x5A, count: 512)
        )
        try await store.append(
            .addStroke(canvasID: canvas.id, layerID: layer.id, stroke: stroke),
            notebookID: package.notebook.id
        )
        let recovered = try await store.recover(notebookID: package.notebook.id)

        try await store.save(recovered)

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: sidecarDirectoryURL(for: package.notebook.id, rootURL: rootURL).path()
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: journalURL(for: package.notebook.id, rootURL: rootURL).path()
            )
        )
    }

    func testMissingSidecarDoesNotReplayAHollowStroke() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let store = LocalDocumentStore(rootURL: rootURL)
        let package = NativeNotebookPackage(
            schemaVersion: .current,
            notebook: Notebook(title: "Hollow", canvases: [Canvas(title: "Canvas 1")])
        )
        try await store.save(package)
        let canvas = package.notebook.canvases[0]
        let layer = canvas.layers[0]
        let stroke = archivedStroke(
            layerID: layer.id,
            archiveData: Data(repeating: 0x11, count: 256)
        )
        try await store.append(
            .addStroke(canvasID: canvas.id, layerID: layer.id, stroke: stroke),
            notebookID: package.notebook.id
        )
        try FileManager.default.removeItem(
            at: sidecarDirectoryURL(for: package.notebook.id, rootURL: rootURL)
        )

        let recovered = try await LocalDocumentStore(rootURL: rootURL).recover(
            notebookID: package.notebook.id
        )

        XCTAssertEqual(recovered.notebook.canvases[0].layers[0].objects, [])
    }

    private func archivedStroke(layerID: LayerID, archiveData: Data) -> Stroke {
        Stroke(
            id: StrokeID(),
            layerID: layerID,
            samples: DomainFixtures.stroke(layerID: layerID).samples,
            style: DomainFixtures.stroke(layerID: layerID).style,
            createdAt: DomainFixtures.fixedDate,
            pencilKitArchive: PencilKitStrokeArchive(
                data: archiveData,
                renderingFingerprint: 99
            )
        )
    }

    private func firstStroke(in package: NativeNotebookPackage) -> Stroke? {
        package.notebook.canvases[0].layers[0].objects.compactMap { object in
            if case let .stroke(stroke) = object { return stroke }
            return nil
        }.first
    }

    private func journalURL(for notebookID: NotebookID, rootURL: URL) -> URL {
        rootURL
            .appending(path: "Journals", directoryHint: .isDirectory)
            .appending(path: "\(notebookID.rawValue.uuidString).journal")
    }

    private func sidecarDirectoryURL(for notebookID: NotebookID, rootURL: URL) -> URL {
        rootURL
            .appending(path: "Journals", directoryHint: .isDirectory)
            .appending(path: "\(notebookID.rawValue.uuidString).sidecars", directoryHint: .isDirectory)
    }

    private func sidecarURL(for notebookID: NotebookID, sequence: UInt64, rootURL: URL) -> URL {
        sidecarDirectoryURL(for: notebookID, rootURL: rootURL)
            .appending(path: "\(sequence).plist")
    }
}
