import XCTest
@testable import NoteNerds

final class NotionRestoreCoordinatorBehaviorTests: XCTestCase {
    func testRestoreBuildsFoldersBeforeAddingExactNotebookAndAssets() throws {
        let folder = Folder.restoreFixture()
        var notebook = DomainFixtures.notebook()
        notebook.parentFolderID = folder.id
        let asset = DocumentAsset(id: AssetID(), data: Data("asset".utf8), contentType: "image/png")
        let remote = try restoreSnapshot(folders: [folder], notebooks: [(notebook, [asset])])

        let restored = try NotionRestoreCoordinator().restore(
            remote,
            into: LibraryState(),
            choices: [:]
        )

        XCTAssertEqual(restored.folder(id: folder.id), folder)
        XCTAssertEqual(restored.notebook(id: notebook.id), notebook)
        XCTAssertEqual(restored.asset(id: asset.id), asset)
    }

    func testExistingNotebookUsesTheExplicitConflictChoice() throws {
        var localNotebook = DomainFixtures.notebook(title: "Local")
        localNotebook.modifiedAt = DomainFixtures.fixedDate.addingTimeInterval(300)
        var remoteNotebook = localNotebook
        remoteNotebook.title = "Notion"
        remoteNotebook.modifiedAt = DomainFixtures.fixedDate.addingTimeInterval(600)
        let remote = try restoreSnapshot(folders: [], notebooks: [(remoteNotebook, [])])
        let local = LibraryState(notebooks: [localNotebook])

        let kept = try NotionRestoreCoordinator().restore(
            remote,
            into: local,
            choices: [localNotebook.id: .keepLocal]
        )
        let replaced = try NotionRestoreCoordinator().restore(
            remote,
            into: local,
            choices: [localNotebook.id: .useNotion]
        )

        XCTAssertEqual(kept.notebook(id: localNotebook.id)?.title, "Local")
        XCTAssertEqual(replaced.notebook(id: localNotebook.id)?.title, "Notion")
    }

    func testExistingNotebookCanImportTheNotionVersionAsANewCopy() throws {
        let localNotebook = DomainFixtures.notebook(title: "Local")
        var remoteNotebook = localNotebook
        remoteNotebook.title = "Notion"
        let remote = try restoreSnapshot(folders: [], notebooks: [(remoteNotebook, [])])
        let local = LibraryState(notebooks: [localNotebook])

        let restored = try NotionRestoreCoordinator(now: { DomainFixtures.fixedDate }).restore(
            remote,
            into: local,
            choices: [localNotebook.id: .importCopy]
        )
        let imported = try XCTUnwrap(restored.notebooks.first { $0.id != localNotebook.id })

        XCTAssertEqual(restored.notebook(id: localNotebook.id)?.title, "Local")
        XCTAssertEqual(imported.title, "Notion copy")
        XCTAssertNotEqual(imported.canvases.map(\.id), remoteNotebook.canvases.map(\.id))
    }

    func testRestoreKeepsNotebookAtRootWhenItsFolderManifestHasNotArrived() throws {
        var orphanedNotebook = DomainFixtures.notebook()
        orphanedNotebook.parentFolderID = FolderID()
        let rootNotebook = DomainFixtures.notebook(
            id: NotebookID(rawValue: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!),
            title: "Root note"
        )
        let remote = try restoreSnapshot(
            folders: [],
            notebooks: [(orphanedNotebook, []), (rootNotebook, [])]
        )

        let restored = try NotionRestoreCoordinator().restore(
            remote,
            into: LibraryState(),
            choices: [orphanedNotebook.id: .useNotion, rootNotebook.id: .useNotion]
        )

        XCTAssertNil(restored.notebook(id: orphanedNotebook.id)?.parentFolderID)
        XCTAssertEqual(
            restored.notebook(id: orphanedNotebook.id)?.canvases,
            orphanedNotebook.canvases
        )
        XCTAssertEqual(restored.notebook(id: rootNotebook.id), rootNotebook)
    }

    func testRestoreRecreatesInheritedTrashProvenance() throws {
        let root = Folder(
            name: "Root",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        let restoredSibling = Folder(
            name: "Restored",
            parentID: root.id,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        let inheritedChild = Folder(
            name: "Inherited",
            parentID: root.id,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        var notebook = DomainFixtures.notebook()
        notebook.parentFolderID = inheritedChild.id
        let trashDate = DomainFixtures.fixedDate.addingTimeInterval(90)
        var source = LibraryState(
            folders: [root, restoredSibling, inheritedChild],
            notebooks: [notebook]
        )
        try source.moveFolderToTrash(root.id, at: trashDate)
        try source.restoreFolder(restoredSibling.id)
        let archivedNotebook = try XCTUnwrap(source.notebook(id: notebook.id))
        let remote = try restoreSnapshot(library: source, notebooks: [(archivedNotebook, [])])

        let restored = try NotionRestoreCoordinator().restore(
            remote,
            into: LibraryState(),
            choices: [notebook.id: .useNotion]
        )

        XCTAssertEqual(restored.folder(id: inheritedChild.id)?.inheritedTrashDate, trashDate)
        XCTAssertEqual(restored.inheritedTrashDate(forNotebook: notebook.id), trashDate)
    }

    func testExplicitNotionRestoreRecreatesPermanentlyDeletedItems() throws {
        let folder = Folder.restoreFixture()
        var notebook = DomainFixtures.notebook()
        notebook.parentFolderID = folder.id
        var local = LibraryState()
        try local.permanentlyDeleteFolder(folder.id)
        local.permanentlyDeleteNotebook(notebook.id)
        let remote = try restoreSnapshot(folders: [folder], notebooks: [(notebook, [])])

        let restored = try NotionRestoreCoordinator().restore(
            remote,
            into: local,
            choices: [notebook.id: .useNotion]
        )

        XCTAssertEqual(restored.folder(id: folder.id), folder)
        XCTAssertEqual(restored.notebook(id: notebook.id), notebook)
    }

    func testExistingFolderRecoversNewerAppearanceFromNotion() throws {
        let remoteFolder = Folder.restoreFixture()
        let localFolder = Folder(
            id: remoteFolder.id,
            name: "Local name",
            parentID: nil,
            createdAt: remoteFolder.createdAt,
            modifiedAt: remoteFolder.modifiedAt.addingTimeInterval(60)
        )
        let remote = try restoreSnapshot(folders: [remoteFolder], notebooks: [])

        let restored = try NotionRestoreCoordinator().restore(
            remote,
            into: LibraryState(folders: [localFolder]),
            choices: [:]
        )

        XCTAssertEqual(restored.folder(id: localFolder.id)?.name, "Local name")
        XCTAssertEqual(restored.folder(id: localFolder.id)?.icon, remoteFolder.icon)
        XCTAssertEqual(restored.folder(id: localFolder.id)?.iconColor, remoteFolder.iconColor)
    }

    func testRestoreRejectsAnArchiveThatIsNotListedInTheManifestDatabase() throws {
        let notebook = DomainFixtures.notebook()
        let manifest = NotionLibraryManifest(
            library: LibraryState(),
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222",
            generatedAt: DomainFixtures.fixedDate
        )
        let archive = try NotionTransportArchive().encode(
            package: NativeNotebookPackage(schemaVersion: .current, notebook: notebook),
            assets: [],
            exportedAt: DomainFixtures.fixedDate
        )
        let snapshot = NotionRemoteLibrarySnapshot(
            manifestData: try NotionLibraryManifestCodec.encode(manifest),
            databaseID: "33333333-3333-3333-3333-333333333333",
            archives: [archive]
        )

        XCTAssertThrowsError(
            try NotionRestoreCoordinator().restore(snapshot, into: LibraryState(), choices: [:])
        ) { error in
            XCTAssertEqual(error as? NotionRestoreError, .databaseMismatch)
        }
    }

    private func restoreSnapshot(
        folders: [Folder],
        notebooks: [(Notebook, [DocumentAsset])]
    ) throws -> NotionRemoteLibrarySnapshot {
        try restoreSnapshot(library: LibraryState(folders: folders), notebooks: notebooks)
    }

    private func restoreSnapshot(
        library: LibraryState,
        notebooks: [(Notebook, [DocumentAsset])]
    ) throws -> NotionRemoteLibrarySnapshot {
        let databaseID = "11111111-1111-1111-1111-111111111111"
        let manifest = NotionLibraryManifest(
            library: library,
            databaseID: databaseID,
            dataSourceID: "22222222-2222-2222-2222-222222222222",
            generatedAt: DomainFixtures.fixedDate
        )
        let archives = try notebooks.map { notebook, assets in
            try NotionTransportArchive().encode(
                package: NativeNotebookPackage(schemaVersion: .current, notebook: notebook),
                assets: assets,
                exportedAt: DomainFixtures.fixedDate
            )
        }
        return NotionRemoteLibrarySnapshot(
            manifestData: try NotionLibraryManifestCodec.encode(manifest),
            databaseID: databaseID,
            archives: archives
        )
    }
}

private extension Folder {
    static func restoreFixture() -> Folder {
        Folder(
            id: FolderID(rawValue: UUID(uuidString: "AAAAAAAA-1111-1111-1111-111111111111")!),
            name: "Projects",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate,
            icon: .systemSymbol(.briefcase),
            iconColor: FolderIconColor(red: 0.55, green: 0.3, blue: 0.9, alpha: 1)
        )
    }
}
