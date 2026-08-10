import Foundation
import XCTest
@testable import NoteNerds

final class FolderMoveIntoDeletionBehaviorTests: XCTestCase {
    func testPermanentParentDeleteWinsConcurrentFolderMoveIntoParent() throws {
        let parent = Folder(
            name: "Deleted parent",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        var movedFolder = Folder(
            name: "Moved folder",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        let original = LibraryState(folders: [parent, movedFolder])
        movedFolder.parentID = parent.id
        movedFolder.modifiedAt = DomainFixtures.fixedDate.addingTimeInterval(10)
        let deletion = LibrarySyncMutation.deleteFolder(parent.id)
        let move = LibrarySyncMutation.updateFolder(movedFolder)
        var deleteThenMove = original
        var moveThenDelete = original

        try apply([deletion, move], to: &deleteThenMove)
        try apply([move, deletion], to: &moveThenDelete)

        XCTAssertEqual(deleteThenMove, moveThenDelete)
        XCTAssertNil(deleteThenMove.folder(id: movedFolder.id))
        try move.apply(to: &deleteThenMove)
        XCTAssertNil(deleteThenMove.folder(id: movedFolder.id))
    }

    func testPermanentParentDeleteWinsConcurrentNotebookMoveIntoParent() throws {
        let parent = Folder(
            name: "Deleted parent",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        var movedNotebook = DomainFixtures.notebook()
        let original = LibraryState(folders: [parent], notebooks: [movedNotebook])
        movedNotebook.parentFolderID = parent.id
        movedNotebook.modifiedAt = DomainFixtures.fixedDate.addingTimeInterval(10)
        let deletion = LibrarySyncMutation.deleteFolder(parent.id)
        let move = LibrarySyncMutation.updateNotebookMetadata(
            NotebookSyncMetadata(notebook: movedNotebook)
        )
        var deleteThenMove = original
        var moveThenDelete = original

        try apply([deletion, move], to: &deleteThenMove)
        try apply([move, deletion], to: &moveThenDelete)

        XCTAssertEqual(deleteThenMove, moveThenDelete)
        XCTAssertNil(deleteThenMove.notebook(id: movedNotebook.id))
        try move.apply(to: &deleteThenMove)
        XCTAssertNil(deleteThenMove.notebook(id: movedNotebook.id))
    }

    private func apply(
        _ mutations: [LibrarySyncMutation],
        to library: inout LibraryState
    ) throws {
        for mutation in mutations { try mutation.apply(to: &library) }
    }
}

@MainActor
final class AppModelFolderDeletionBehaviorTests: XCTestCase {
    func testPermanentlyDeleteFolderEnqueuesDeleteForEveryRemovedDescendant() async throws {
        let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let model = AppModel(
            repository: LocalLibraryRepository(fileURL: directoryURL.appending(path: "library.json")),
            syncProvider: OutboxHoldingSyncProvider(),
            deviceID: "deleting-device",
            automaticallyRestore: false
        )
        let parent = try model.library.createFolder(
            named: "Parent",
            in: nil,
            at: DomainFixtures.fixedDate
        )
        let child = try model.library.createFolder(
            named: "Child",
            in: parent.id,
            at: DomainFixtures.fixedDate
        )
        let notebook = DomainFixtures.notebook()
        try model.library.addNotebook(notebook, to: child.id)

        model.permanentlyDeleteFolder(parent.id)
        await model.checkpointDocuments()

        let engine = try XCTUnwrap(model.syncEngine)
        let pendingChanges = await engine.pendingChanges
        let mutations = try pendingChanges.map(SyncChangeEncoder.decodeLibraryMutation)
        XCTAssertEqual(
            mutations,
            [
                .deleteFolder(parent.id),
                .deleteFolder(child.id),
                .deleteNotebook(notebook.id)
            ]
        )
    }
}

private actor OutboxHoldingSyncProvider: SyncProvider {
    let identifier = "outbox-holding"

    func start() async throws { throw SyncProviderFailure.serviceUnavailable }
    func push(_ changes: [DocumentChange]) async throws {}
    func pull(since cursor: SyncCursor?) async throws -> SyncBatch {
        SyncBatch(changes: [], cursor: cursor)
    }
    func uploadAsset(_ asset: DocumentAsset) async throws {}
    func fetchAsset(_ id: AssetID) async throws -> Data {
        throw SyncProviderFailure.serviceUnavailable
    }
}
