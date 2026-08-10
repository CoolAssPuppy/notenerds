import XCTest
@testable import NoteNerds

final class LibraryBehaviorTests: XCTestCase {
    func testFoldersMayNestAndNotebooksMayRemainAtRoot() throws {
        var library = LibraryState()
        let projects = try library.createFolder(named: "Projects", in: nil, at: DomainFixtures.fixedDate)
        let client = try library.createFolder(named: "Client", in: projects.id, at: DomainFixtures.fixedDate)
        let project = try library.createFolder(named: "Project", in: client.id, at: DomainFixtures.fixedDate)
        let rootNotebook = DomainFixtures.notebook()

        try library.addNotebook(rootNotebook, to: nil)

        XCTAssertEqual(library.folder(id: client.id)?.parentID, projects.id)
        XCTAssertEqual(library.folder(id: project.id)?.parentID, client.id)
        XCTAssertEqual(library.notebook(id: rootNotebook.id)?.parentFolderID, nil)
    }

    func testDeletingNonemptyFolderMovesHierarchyToTrashAndRestoreRecoversIt() throws {
        var library = LibraryState()
        let parent = try library.createFolder(named: "Parent", in: nil, at: DomainFixtures.fixedDate)
        let child = try library.createFolder(named: "Child", in: parent.id, at: DomainFixtures.fixedDate)
        let notebook = DomainFixtures.notebook()
        try library.addNotebook(notebook, to: child.id)

        try library.moveFolderToTrash(parent.id, at: DomainFixtures.fixedDate)

        XCTAssertEqual(library.folder(id: parent.id)?.trashedAt, DomainFixtures.fixedDate)
        XCTAssertEqual(library.folder(id: child.id)?.trashedAt, DomainFixtures.fixedDate)
        XCTAssertEqual(library.notebook(id: notebook.id)?.trashedAt, DomainFixtures.fixedDate)

        try library.restoreFolder(parent.id)

        XCTAssertNil(library.folder(id: parent.id)?.trashedAt)
        XCTAssertNil(library.folder(id: child.id)?.trashedAt)
        XCTAssertNil(library.notebook(id: notebook.id)?.trashedAt)
    }

    func testRestoringAChildKeepsItsParentChainAfterEmptyTrash() throws {
        var library = LibraryState()
        let parent = try library.createFolder(named: "Parent", in: nil, at: DomainFixtures.fixedDate)
        let child = try library.createFolder(named: "Child", in: parent.id, at: DomainFixtures.fixedDate)
        let sibling = try library.createFolder(named: "Sibling", in: parent.id, at: DomainFixtures.fixedDate)
        let notebook = DomainFixtures.notebook()
        let unrelatedNotebook = DomainFixtures.notebook(id: NotebookID(), title: "Unrelated")
        try library.addNotebook(notebook, to: child.id)
        try library.addNotebook(unrelatedNotebook, to: parent.id)
        try library.moveFolderToTrash(parent.id, at: DomainFixtures.fixedDate)

        try library.restoreFolder(child.id)
        library.emptyTrash()

        let restoredParent = try XCTUnwrap(library.folder(id: parent.id))
        let restoredChild = try XCTUnwrap(library.folder(id: child.id))
        let restoredNotebook = try XCTUnwrap(library.notebook(id: notebook.id))
        XCTAssertNil(restoredParent.trashedAt)
        XCTAssertNil(restoredChild.trashedAt)
        XCTAssertNil(restoredNotebook.trashedAt)
        XCTAssertNil(library.folder(id: sibling.id))
        XCTAssertNil(library.notebook(id: unrelatedNotebook.id))
    }

    func testRestoringANotebookKeepsItsFolderChainAfterEmptyTrash() throws {
        var library = LibraryState()
        let parent = try library.createFolder(named: "Parent", in: nil, at: DomainFixtures.fixedDate)
        let child = try library.createFolder(named: "Child", in: parent.id, at: DomainFixtures.fixedDate)
        let notebook = DomainFixtures.notebook()
        try library.addNotebook(notebook, to: child.id)
        try library.moveFolderToTrash(parent.id, at: DomainFixtures.fixedDate)

        library.restoreNotebook(notebook.id)
        library.emptyTrash()

        let restoredParent = try XCTUnwrap(library.folder(id: parent.id))
        let restoredChild = try XCTUnwrap(library.folder(id: child.id))
        let restoredNotebook = try XCTUnwrap(library.notebook(id: notebook.id))
        XCTAssertNil(restoredParent.trashedAt)
        XCTAssertNil(restoredChild.trashedAt)
        XCTAssertNil(restoredNotebook.trashedAt)
        XCTAssertEqual(restoredNotebook.parentFolderID, child.id)
    }

    func testRecentsUseUserOpenDateRatherThanSyncChanges() throws {
        var library = LibraryState()
        let older = DomainFixtures.notebook(title: "Older")
        let newer = Notebook(
            title: "Newer",
            canvases: [Canvas(title: "Canvas 1")],
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate.addingTimeInterval(300),
            lastOpenedAt: DomainFixtures.fixedDate.addingTimeInterval(100)
        )
        try library.addNotebook(older, to: nil)
        try library.addNotebook(newer, to: nil)

        XCTAssertEqual(library.notebooks(sortedBy: .recentlyOpened).map(\.title), ["Newer", "Older"])
    }

    func testNameSortUsesLocalizedCaseInsensitiveOrder() throws {
        var library = LibraryState()
        try library.addNotebook(DomainFixtures.notebook(title: "zebra"), to: nil)
        try library.addNotebook(Notebook(title: "Alpha", canvases: [Canvas(title: "Canvas 1")]), to: nil)

        XCTAssertEqual(library.notebooks(sortedBy: .nameAscending).map(\.title), ["Alpha", "zebra"])
        XCTAssertEqual(library.notebooks(sortedBy: .nameDescending).map(\.title), ["zebra", "Alpha"])
    }

    func testFolderCardsUseThePreferredLibrarySort() throws {
        var library = LibraryState()
        _ = try library.createFolder(named: "zebra", in: nil, at: DomainFixtures.fixedDate)
        _ = try library.createFolder(named: "Alpha", in: nil, at: DomainFixtures.fixedDate)

        XCTAssertEqual(library.folders(sortedBy: .nameAscending).map(\.name), ["Alpha", "zebra"])
        XCTAssertEqual(library.folders(sortedBy: .nameDescending).map(\.name), ["zebra", "Alpha"])
    }

    func testMyNotebooksIncludesRootAndFolderNotebooksByRecentEditTime() throws {
        var library = LibraryState()
        let folder = try library.createFolder(named: "Projects", in: nil, at: DomainFixtures.fixedDate)
        let root = Notebook(
            title: "Root",
            canvases: [Canvas(title: "Canvas 1")],
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate.addingTimeInterval(60)
        )
        let filed = Notebook(
            title: "Filed",
            canvases: [Canvas(title: "Canvas 1")],
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate.addingTimeInterval(120)
        )
        try library.addNotebook(root, to: nil)
        try library.addNotebook(filed, to: folder.id)

        XCTAssertEqual(
            library.notebooks(in: nil, sortedBy: .recentlyModified).map(\.title),
            ["Filed", "Root"]
        )
        XCTAssertEqual(
            library.notebooks(in: folder.id, sortedBy: .recentlyModified).map(\.title),
            ["Filed"]
        )
    }

    func testOldestEditTimeSortsFromOldestToNewest() throws {
        var library = LibraryState()
        let oldest = DomainFixtures.notebook(title: "Oldest")
        let newest = Notebook(
            title: "Newest",
            canvases: [Canvas(title: "Canvas 1")],
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate.addingTimeInterval(300)
        )
        try library.addNotebook(newest, to: nil)
        try library.addNotebook(oldest, to: nil)

        XCTAssertEqual(library.notebooks(sortedBy: .oldestModified).map(\.title), ["Oldest", "Newest"])
    }
}
