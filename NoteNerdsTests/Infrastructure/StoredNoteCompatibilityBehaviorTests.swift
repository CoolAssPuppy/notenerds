import PencilKit
import XCTest
@testable import NoteNerds

/// Checks that notes already on a device survive the schema 7 change.
///
/// Version 7 is where rendering began trusting a stored PencilKit archive
/// instead of re-deriving it on every read. Every note written by a shipped
/// build is older than that, so these tests read real files back through the
/// document store rather than exercising the repair in isolation.
@MainActor
final class StoredNoteCompatibilityBehaviorTests: XCTestCase {
    func testAnOlderNoteKeepsInkWhoseArchiveStillDescribesIt() async throws {
        let context = try makeStore()
        defer { context.remove() }
        let stroke = archivedStroke()
        let archive = try XCTUnwrap(stroke.pencilKitArchive)
        try await context.store.save(package(
            with: stroke,
            schemaVersion: olderVersion,
            notebookID: context.notebookID
        ))

        let recovered = try await context.store.recover(notebookID: context.notebookID)

        let restored = try XCTUnwrap(firstStroke(in: recovered))
        XCTAssertEqual(restored.pencilKitArchive, archive)
        XCTAssertEqual(
            PencilCanvasRenderer.drawing(from: [restored]).strokes.first?.randomSeed,
            PencilKitStrokeArchiveCodec.stroke(for: stroke)?.randomSeed
        )
    }

    func testAnOlderNoteDropsInkWhoseArchiveNoLongerDescribesIt() async throws {
        let context = try makeStore()
        defer { context.remove() }
        try await context.store.save(package(
            with: staleArchivedStroke(),
            schemaVersion: olderVersion,
            notebookID: context.notebookID
        ))

        let recovered = try await context.store.recover(notebookID: context.notebookID)

        let restored = try XCTUnwrap(firstStroke(in: recovered))
        XCTAssertNil(
            restored.pencilKitArchive,
            "Stale ink from an older build would render a shape the stroke no longer has"
        )
        XCTAssertEqual(PencilCanvasRenderer.drawing(from: [restored]).strokes.count, 1)
    }

    func testACurrentNoteIsTrustedWithoutBeingWalked() async throws {
        let context = try makeStore()
        defer { context.remove() }
        let stale = staleArchivedStroke()
        try await context.store.save(package(
            with: stale,
            schemaVersion: .current,
            notebookID: context.notebookID
        ))

        let recovered = try await context.store.recover(notebookID: context.notebookID)

        XCTAssertEqual(
            firstStroke(in: recovered)?.pencilKitArchive,
            stale.pencilKitArchive,
            "A note at the current version must not pay for a repair pass on load"
        )
    }

    func testARepairedNoteIsNotRepairedAgainAfterItIsSaved() async throws {
        let context = try makeStore()
        defer { context.remove() }
        try await context.store.save(package(
            with: staleArchivedStroke(),
            schemaVersion: olderVersion,
            notebookID: context.notebookID
        ))

        let recovered = try await context.store.recover(notebookID: context.notebookID)
        try await context.store.save(recovered)
        let reopened = try await context.store.recover(notebookID: context.notebookID)

        XCTAssertEqual(reopened.schemaVersion, .current)
        XCTAssertNil(firstStroke(in: reopened)?.pencilKitArchive)
    }

    func testLoadingALegacyFileRepairsAndRewritesItOnlyOnce() async throws {
        let context = try makeStore()
        defer { context.remove() }
        let package = package(
            with: staleArchivedStroke(),
            schemaVersion: olderVersion,
            notebookID: context.notebookID
        )
        let snapshotsURL = context.directoryURL.appending(path: "Snapshots", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)
        let snapshotURL = snapshotsURL.appending(
            path: "\(context.notebookID.rawValue.uuidString).notenerds.json"
        )
        try NativeDocumentSerializer().encode(package).write(to: snapshotURL, options: .atomic)
        let writes = SnapshotWriteCounter()
        let store = LocalDocumentStore(rootURL: context.directoryURL, afterSnapshotWrite: { writes.record() })

        let firstLoad = try await store.load(notebookID: context.notebookID)
        let secondLoad = try await store.load(notebookID: context.notebookID)

        XCTAssertNil(firstStroke(in: firstLoad)?.pencilKitArchive)
        XCTAssertNil(firstStroke(in: secondLoad)?.pencilKitArchive)
        XCTAssertEqual(firstLoad.schemaVersion, .current)
        XCTAssertEqual(writes.count, 1, "A legacy note must be rewritten once after repair")
    }

    func testAnOlderNoteWithManyStrokesStillReadsEveryOne() async throws {
        let context = try makeStore()
        defer { context.remove() }
        let strokes = (0..<40).map { index in
            PencilKitStrokeArchiveCodec.preserving(
                PencilStrokeTestFixture.blackPenStroke(randomSeed: UInt32(index + 1)),
                in: DomainFixtures.stroke(id: StrokeID())
            )
        }
        var notebook = DomainFixtures.notebook(id: context.notebookID, title: "Many strokes")
        notebook.canvases[0].layers[0].objects = strokes.map(CanvasObject.stroke)
        try await context.store.save(
            NativeNotebookPackage(schemaVersion: olderVersion, notebook: notebook)
        )

        let recovered = try await context.store.recover(notebookID: context.notebookID)

        let restored = recovered.notebook.canvases[0].layers[0].objects.compactMap(\.strokeValue)
        XCTAssertEqual(restored.count, strokes.count)
        XCTAssertEqual(PencilCanvasRenderer.drawing(from: restored).strokes.count, strokes.count)
    }

    private var olderVersion: DocumentSchemaVersion {
        DocumentSchemaVersion(
            rawValue: DocumentSchemaVersion.selfInvalidatingStrokeArchives.rawValue - 1
        )
    }

    private func makeStore() throws -> StoredNoteContext {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return StoredNoteContext(
            store: LocalDocumentStore(rootURL: directoryURL),
            notebookID: NotebookID(),
            directoryURL: directoryURL
        )
    }

    private func package(
        with stroke: Stroke,
        schemaVersion: DocumentSchemaVersion,
        notebookID: NotebookID
    ) -> NativeNotebookPackage {
        var notebook = DomainFixtures.notebook(id: notebookID, title: "Stored note")
        notebook.canvases[0].layers[0].objects = [.stroke(stroke)]
        return NativeNotebookPackage(schemaVersion: schemaVersion, notebook: notebook)
    }

    private func firstStroke(in package: NativeNotebookPackage) -> Stroke? {
        package.notebook.canvases[0].layers[0].objects.compactMap(\.strokeValue).first
    }

    private func archivedStroke() -> Stroke {
        PencilKitStrokeArchiveCodec.preserving(
            PencilStrokeTestFixture.blackPenStroke(randomSeed: 21),
            in: DomainFixtures.stroke(id: StrokeID())
        )
    }

    /// A stroke carrying ink that no longer matches its samples, the shape an
    /// older build could leave behind by transforming a stroke in place.
    private func staleArchivedStroke() -> Stroke {
        var stroke = archivedStroke()
        let archive = stroke.pencilKitArchive
        stroke.samples = Array(stroke.samples.prefix(1))
        stroke.pencilKitArchive = archive
        return stroke
    }
}

private struct StoredNoteContext {
    let store: LocalDocumentStore
    let notebookID: NotebookID
    let directoryURL: URL

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
