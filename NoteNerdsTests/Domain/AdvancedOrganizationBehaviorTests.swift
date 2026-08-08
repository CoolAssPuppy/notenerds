import XCTest
@testable import NoteNerds

final class AdvancedOrganizationBehaviorTests: XCTestCase {
    func testFolderCannotMoveInsideItsOwnDescendant() throws {
        var library = LibraryState()
        let parent = try library.createFolder(named: "Parent", in: nil, at: DomainFixtures.fixedDate)
        let child = try library.createFolder(named: "Child", in: parent.id, at: DomainFixtures.fixedDate)

        XCTAssertThrowsError(try library.moveFolder(parent.id, to: child.id, at: DomainFixtures.fixedDate)) { error in
            XCTAssertEqual(error as? LibraryError, .folderCycle)
        }
        XCTAssertNil(library.folder(id: parent.id)?.parentID)
    }

    func testDuplicateNotebookPreservesContentWithFreshIdentifiers() throws {
        let original = DomainFixtures.notebook()

        let duplicate = original.duplicated(at: DomainFixtures.fixedDate)

        XCTAssertNotEqual(duplicate.id, original.id)
        XCTAssertNotEqual(duplicate.canvases[0].id, original.canvases[0].id)
        XCTAssertNotEqual(duplicate.canvases[0].layers[0].id, original.canvases[0].layers[0].id)
        XCTAssertNotEqual(
            duplicate.canvases[0].layers[0].objects[0].id,
            original.canvases[0].layers[0].objects[0].id
        )
        XCTAssertEqual(duplicate.title, "Research copy")
    }

    func testCanvasOperationsCreateDuplicateReorderAndDelete() throws {
        var notebook = DomainFixtures.notebook()
        let originalCanvasID = notebook.canvases[0].id
        let duplicateID = try notebook.duplicateCanvas(originalCanvasID, at: DomainFixtures.fixedDate)
        notebook.addCanvas(named: "Third", at: DomainFixtures.fixedDate)

        try notebook.moveCanvas(from: 2, to: 0)
        try notebook.deleteCanvas(duplicateID)

        XCTAssertEqual(notebook.canvases.map(\.title), ["Third", "Canvas 1"])
        XCTAssertFalse(notebook.canvases.contains { $0.id == duplicateID })
    }

    func testLayerOperationsPreserveExplicitOrderAndVisibility() throws {
        var canvas = DomainFixtures.notebook().canvases[0]
        let second = canvas.addLayer(named: "Ink")

        try canvas.setLayerVisibility(second.id, isVisible: false)
        try canvas.renameLayer(second.id, to: "Hidden ink")
        try canvas.moveLayer(from: 1, to: 0)

        XCTAssertEqual(canvas.layers.map(\.name), ["Hidden ink", "Notes"])
        XCTAssertFalse(canvas.layers[0].isVisible)
    }

    func testDuplicatingNotebookAddsIndependentCopyToLibrary() throws {
        let original = DomainFixtures.notebook()
        var library = LibraryState(notebooks: [original])

        let duplicateID = try library.duplicateNotebook(original.id, at: DomainFixtures.fixedDate)
        let duplicate = try XCTUnwrap(library.notebook(id: duplicateID))

        XCTAssertEqual(duplicate.title, "Research copy")
        XCTAssertNotEqual(duplicate.id, original.id)
        XCTAssertNotEqual(duplicate.canvases[0].id, original.canvases[0].id)
    }

    func testPermanentFolderDeletionRemovesItsRecoverableHierarchy() throws {
        var library = LibraryState()
        let parent = try library.createFolder(named: "Parent", in: nil, at: DomainFixtures.fixedDate)
        let child = try library.createFolder(named: "Child", in: parent.id, at: DomainFixtures.fixedDate)
        let notebook = DomainFixtures.notebook()
        try library.addNotebook(notebook, to: child.id)
        try library.moveFolderToTrash(parent.id, at: DomainFixtures.fixedDate)

        try library.permanentlyDeleteFolder(parent.id)

        XCTAssertNil(library.folder(id: parent.id))
        XCTAssertNil(library.folder(id: child.id))
        XCTAssertNil(library.notebook(id: notebook.id))
    }

    func testEmptyTrashLeavesActiveItemsUntouched() {
        let active = DomainFixtures.notebook(title: "Active")
        var trashed = DomainFixtures.notebook(id: NotebookID(), title: "Trashed")
        trashed.trashedAt = DomainFixtures.fixedDate
        var library = LibraryState(notebooks: [active, trashed])

        library.emptyTrash()

        XCTAssertNotNil(library.notebook(id: active.id))
        XCTAssertNil(library.notebook(id: trashed.id))
    }

    func testMultipleFoldersAndNotebooksMoveTogether() throws {
        var library = LibraryState()
        let destination = try library.createFolder(named: "Destination", in: nil, at: DomainFixtures.fixedDate)
        let folder = try library.createFolder(named: "Plans", in: nil, at: DomainFixtures.fixedDate)
        let notebook = DomainFixtures.notebook()
        try library.addNotebook(notebook, to: nil)

        try library.moveItems(
            [.folder(folder.id), .notebook(notebook.id)],
            to: destination.id,
            at: DomainFixtures.fixedDate
        )

        XCTAssertEqual(library.folder(id: folder.id)?.parentID, destination.id)
        XCTAssertEqual(library.notebook(id: notebook.id)?.parentFolderID, destination.id)
    }

    func testMultipleTrashedItemsRestoreTogether() throws {
        var library = LibraryState()
        let folder = try library.createFolder(named: "Archive", in: nil, at: DomainFixtures.fixedDate)
        let notebook = DomainFixtures.notebook()
        try library.addNotebook(notebook, to: nil)
        try library.moveItemsToTrash([.folder(folder.id), .notebook(notebook.id)], at: DomainFixtures.fixedDate)

        try library.restoreItems([.folder(folder.id), .notebook(notebook.id)])

        XCTAssertNil(library.folder(id: folder.id)?.trashedAt)
        XCTAssertNil(library.notebook(id: notebook.id)?.trashedAt)
    }

    func testInvalidMultipleItemMoveDoesNotMoveAnyItem() throws {
        var library = LibraryState()
        let parent = try library.createFolder(named: "Parent", in: nil, at: DomainFixtures.fixedDate)
        let child = try library.createFolder(named: "Child", in: parent.id, at: DomainFixtures.fixedDate)
        let notebook = DomainFixtures.notebook()
        try library.addNotebook(notebook, to: nil)

        XCTAssertThrowsError(try library.moveItems(
            [.notebook(notebook.id), .folder(parent.id)],
            to: child.id,
            at: DomainFixtures.fixedDate
        ))
        XCTAssertNil(library.notebook(id: notebook.id)?.parentFolderID)
        XCTAssertNil(library.folder(id: parent.id)?.parentID)
    }

    func testFolderTagsSupportMultipleHierarchyLabels() throws {
        var library = LibraryState()
        let folder = try library.createFolder(named: "Research", in: nil, at: DomainFixtures.fixedDate)

        try library.addTag("work", to: folder.id, at: DomainFixtures.fixedDate)
        try library.addTag("priority", to: folder.id, at: DomainFixtures.fixedDate)

        XCTAssertEqual(library.folder(id: folder.id)?.tags, ["work", "priority"])
    }
}
