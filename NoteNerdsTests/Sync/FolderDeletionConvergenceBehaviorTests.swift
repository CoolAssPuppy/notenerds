import XCTest
@testable import NoteNerds

final class FolderDeletionConvergenceBehaviorTests: XCTestCase {
    func testConcurrentChildMoveOutOfTrashedParentConvergesOnActiveSubtree() throws {
        let fixture = try makeTree()
        var movedChild = fixture.child
        movedChild.parentID = nil
        movedChild.modifiedAt = DomainFixtures.fixedDate.addingTimeInterval(60)
        let move = LibrarySyncMutation.updateFolder(movedChild)
        let trashDate = DomainFixtures.fixedDate.addingTimeInterval(30)
        let trash = LibrarySyncMutation.trashFolder(fixture.parent.id, date: trashDate)
        var trashThenMove = fixture.library
        var moveThenTrash = fixture.library

        try apply([trash, move], to: &trashThenMove)
        try apply([move, trash], to: &moveThenTrash)

        XCTAssertEqual(trashThenMove, moveThenTrash)
        XCTAssertEqual(trashThenMove.folder(id: fixture.parent.id)?.trashedAt, trashDate)
        XCTAssertNil(trashThenMove.folder(id: fixture.child.id)?.trashedAt)
        XCTAssertNil(trashThenMove.notebook(id: fixture.notebook.id)?.trashedAt)
    }

    func testConcurrentChildMovePreservesEarlierDirectNotebookTrash() throws {
        let fixture = try makeTree()
        let notebookTrashDate = DomainFixtures.fixedDate.addingTimeInterval(10)
        let parentTrashDate = DomainFixtures.fixedDate.addingTimeInterval(20)
        var original = fixture.library
        original.moveNotebookToTrash(fixture.notebook.id, at: notebookTrashDate)
        var movedChild = fixture.child
        movedChild.parentID = nil
        movedChild.modifiedAt = DomainFixtures.fixedDate.addingTimeInterval(30)
        let move = LibrarySyncMutation.updateFolder(movedChild)
        let trash = LibrarySyncMutation.trashFolder(fixture.parent.id, date: parentTrashDate)
        var trashThenMove = original
        var moveThenTrash = original

        try apply([trash, move], to: &trashThenMove)
        try apply([move, trash], to: &moveThenTrash)

        XCTAssertEqual(trashThenMove, moveThenTrash)
        XCTAssertNil(trashThenMove.folder(id: fixture.child.id)?.trashedAt)
        XCTAssertEqual(trashThenMove.notebook(id: fixture.notebook.id)?.trashedAt, notebookTrashDate)
    }

    func testConcurrentChildMoveAfterSiblingRestoreConvergesOnActiveSubtree() throws {
        let fixture = try makeTree(includingSibling: true)
        let sibling = try XCTUnwrap(fixture.sibling)
        let trashDate = DomainFixtures.fixedDate.addingTimeInterval(10)
        var movedChild = fixture.child
        movedChild.parentID = nil
        movedChild.modifiedAt = DomainFixtures.fixedDate.addingTimeInterval(20)
        let move = LibrarySyncMutation.updateFolder(movedChild)
        let trash = LibrarySyncMutation.trashFolder(fixture.parent.id, date: trashDate)
        let restore = LibrarySyncMutation.restoreFolder(sibling.id)
        var restoreThenMove = fixture.library
        var moveThenRestore = fixture.library

        try apply([trash, restore, move], to: &restoreThenMove)
        try apply([move, trash, restore], to: &moveThenRestore)

        XCTAssertEqual(restoreThenMove, moveThenRestore)
        XCTAssertNil(restoreThenMove.folder(id: fixture.parent.id)?.trashedAt)
        XCTAssertNil(restoreThenMove.folder(id: fixture.child.id)?.trashedAt)
        XCTAssertNil(restoreThenMove.notebook(id: fixture.notebook.id)?.trashedAt)
    }

    func testConcurrentNotebookMoveAfterSiblingRestoreConvergesOnActiveNotebook() throws {
        let fixture = try makeTree(includingSibling: true)
        let sibling = try XCTUnwrap(fixture.sibling)
        let trashDate = DomainFixtures.fixedDate.addingTimeInterval(10)
        var movedNotebook = fixture.notebook
        movedNotebook.parentFolderID = nil
        movedNotebook.modifiedAt = DomainFixtures.fixedDate.addingTimeInterval(20)
        let move = LibrarySyncMutation.updateNotebookMetadata(NotebookSyncMetadata(notebook: movedNotebook))
        let trash = LibrarySyncMutation.trashFolder(fixture.parent.id, date: trashDate)
        let restore = LibrarySyncMutation.restoreFolder(sibling.id)
        var restoreThenMove = fixture.library
        var moveThenRestore = fixture.library

        try apply([trash, restore, move], to: &restoreThenMove)
        try apply([move, trash, restore], to: &moveThenRestore)

        XCTAssertEqual(restoreThenMove, moveThenRestore)
        XCTAssertEqual(restoreThenMove.folder(id: fixture.child.id)?.trashedAt, trashDate)
        XCTAssertNil(restoreThenMove.notebook(id: fixture.notebook.id)?.trashedAt)
    }

    func testConcurrentNotebookMoveOutOfTrashedFolderConvergesOnActiveNotebook() throws {
        let fixture = try makeTree()
        let trashDate = DomainFixtures.fixedDate.addingTimeInterval(30)
        var movedNotebook = fixture.notebook
        movedNotebook.parentFolderID = nil
        movedNotebook.modifiedAt = DomainFixtures.fixedDate.addingTimeInterval(60)
        let move = LibrarySyncMutation.updateNotebookMetadata(NotebookSyncMetadata(notebook: movedNotebook))
        let trash = LibrarySyncMutation.trashFolder(fixture.parent.id, date: trashDate)
        var trashThenMove = fixture.library
        var moveThenTrash = fixture.library

        try apply([trash, move], to: &trashThenMove)
        try apply([move, trash], to: &moveThenTrash)

        XCTAssertEqual(trashThenMove, moveThenTrash)
        XCTAssertEqual(trashThenMove.folder(id: fixture.child.id)?.trashedAt, trashDate)
        XCTAssertNil(trashThenMove.notebook(id: fixture.notebook.id)?.trashedAt)
    }

    func testPermanentParentDeleteWinsConcurrentChildMove() throws {
        let fixture = try makeTree()
        var movedChild = fixture.child
        movedChild.parentID = nil
        movedChild.modifiedAt = DomainFixtures.fixedDate.addingTimeInterval(20)
        let move = LibrarySyncMutation.updateFolder(movedChild)
        let deletions: [LibrarySyncMutation] = [
            .deleteFolder(fixture.parent.id),
            .deleteFolder(fixture.child.id),
            .deleteNotebook(fixture.notebook.id)
        ]
        var deleteThenMove = fixture.library
        var moveThenDelete = fixture.library

        try apply(deletions + [move], to: &deleteThenMove)
        try apply([move] + deletions, to: &moveThenDelete)

        XCTAssertEqual(deleteThenMove, moveThenDelete)
        XCTAssertNil(deleteThenMove.folder(id: fixture.parent.id))
        XCTAssertNil(deleteThenMove.folder(id: fixture.child.id))
        XCTAssertNil(deleteThenMove.notebook(id: fixture.notebook.id))
    }

    func testPermanentDeletionTombstonesSurvivePersistence() throws {
        let fixture = try makeTree()
        var deleted = fixture.library
        try LibrarySyncMutation.deleteFolder(fixture.parent.id).apply(to: &deleted)
        let data = try JSONEncoder().encode(deleted)
        var restored = try JSONDecoder().decode(LibraryState.self, from: data)
        var movedChild = fixture.child
        movedChild.parentID = nil

        try LibrarySyncMutation.updateFolder(movedChild).apply(to: &restored)
        try LibrarySyncMutation.createNotebook(fixture.notebook).apply(to: &restored)

        XCTAssertNil(restored.folder(id: fixture.child.id))
        XCTAssertNil(restored.notebook(id: fixture.notebook.id))
    }

    func testExplicitBackupRestoreClearsPermanentDeletionTombstones() throws {
        let fixture = try makeTree()
        var library = fixture.library
        try library.permanentlyDeleteFolder(fixture.parent.id)

        library.restoreFolderFromBackup(fixture.parent)
        library.restoreFolderFromBackup(fixture.child)
        library.restoreNotebookFromBackup(fixture.notebook)

        XCTAssertEqual(library.folder(id: fixture.parent.id), fixture.parent)
        XCTAssertEqual(library.folder(id: fixture.child.id), fixture.child)
        XCTAssertEqual(library.notebook(id: fixture.notebook.id), fixture.notebook)
    }

    func testBackupRestoreRebuildsInheritedNotebookTrashProvenance() throws {
        let fixture = try makeTree(includingSibling: true)
        let sibling = try XCTUnwrap(fixture.sibling)
        let trashDate = DomainFixtures.fixedDate.addingTimeInterval(10)
        var backup = fixture.library
        try backup.moveFolderToTrash(fixture.parent.id, at: trashDate)
        try backup.restoreFolder(sibling.id)
        let trashedNotebook = try XCTUnwrap(backup.notebook(id: fixture.notebook.id))
        var restored = LibraryState(folders: backup.folders)
        restored.restoreNotebookFromBackup(trashedNotebook, inheritedTrashDate: trashDate)
        var movedChild = fixture.child
        movedChild.parentID = nil
        movedChild.modifiedAt = DomainFixtures.fixedDate.addingTimeInterval(20)

        try LibrarySyncMutation.updateFolder(movedChild).apply(to: &restored)

        XCTAssertNil(restored.folder(id: fixture.child.id)?.trashedAt)
        XCTAssertNil(restored.notebook(id: fixture.notebook.id)?.trashedAt)
    }

    func testSelectiveRestoreProvenanceSurvivesLibraryPersistence() throws {
        let fixture = try makeTree(includingSibling: true)
        let sibling = try XCTUnwrap(fixture.sibling)
        let trashDate = DomainFixtures.fixedDate.addingTimeInterval(10)
        var library = fixture.library
        try library.moveFolderToTrash(fixture.parent.id, at: trashDate)
        try library.restoreFolder(sibling.id)
        let data = try JSONEncoder().encode(library)
        var restored = try JSONDecoder().decode(LibraryState.self, from: data)
        var movedChild = fixture.child
        movedChild.parentID = nil
        movedChild.modifiedAt = DomainFixtures.fixedDate.addingTimeInterval(20)

        try LibrarySyncMutation.updateFolder(movedChild).apply(to: &restored)

        XCTAssertNil(restored.folder(id: fixture.child.id)?.trashedAt)
        XCTAssertNil(restored.notebook(id: fixture.notebook.id)?.trashedAt)
    }

    func testStaleFolderSnapshotCannotReplaceNewerMetadataAfterExplicitRestore() throws {
        let oldParent = Folder(
            name: "Old parent",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        let newParent = Folder(
            name: "New parent",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        var stored = Folder(
            name: "Current name",
            parentID: newParent.id,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate.addingTimeInterval(20),
            isFavorite: true,
            tags: ["current"]
        )
        var library = LibraryState(folders: [oldParent, newParent, stored])
        try library.moveFolderToTrash(stored.id, at: DomainFixtures.fixedDate.addingTimeInterval(30))
        try LibrarySyncMutation.restoreFolder(stored.id).apply(to: &library)
        stored.name = "Stale name"
        stored.parentID = oldParent.id
        stored.modifiedAt = DomainFixtures.fixedDate.addingTimeInterval(10)
        stored.isFavorite = false
        stored.tags = ["stale"]
        stored.trashedAt = DomainFixtures.fixedDate.addingTimeInterval(30)

        try LibrarySyncMutation.updateFolder(stored).apply(to: &library)

        let restored = try XCTUnwrap(library.folder(id: stored.id))
        XCTAssertNil(restored.trashedAt)
        XCTAssertEqual(restored.name, "Current name")
        XCTAssertEqual(restored.parentID, newParent.id)
        XCTAssertTrue(restored.isFavorite)
        XCTAssertEqual(restored.tags, ["current"])
    }

    private func makeTree(includingSibling: Bool = false) throws -> TreeFixture {
        var library = LibraryState()
        let parent = try library.createFolder(named: "Parent", in: nil, at: DomainFixtures.fixedDate)
        let child = try library.createFolder(named: "Child", in: parent.id, at: DomainFixtures.fixedDate)
        let sibling = includingSibling
            ? try library.createFolder(named: "Sibling", in: parent.id, at: DomainFixtures.fixedDate)
            : nil
        let notebook = DomainFixtures.notebook()
        try library.addNotebook(notebook, to: child.id)
        return TreeFixture(library: library, parent: parent, child: child, sibling: sibling, notebook: notebook)
    }

    private func apply(_ mutations: [LibrarySyncMutation], to library: inout LibraryState) throws {
        for mutation in mutations { try mutation.apply(to: &library) }
    }
}

private struct TreeFixture {
    let library: LibraryState
    let parent: Folder
    let child: Folder
    let sibling: Folder?
    let notebook: Notebook
}
