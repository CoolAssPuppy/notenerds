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
        let databaseID = "11111111-1111-1111-1111-111111111111"
        let manifest = NotionLibraryManifest(
            library: LibraryState(folders: folders),
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
            modifiedAt: DomainFixtures.fixedDate
        )
    }
}
