import XCTest
@testable import NoteNerds

@MainActor
final class FolderCreationBehaviorTests: XCTestCase {
    func testFolderCreationStopsAfterOneChildLevel() throws {
        let model = makeModel()

        model.createFolder()

        let topLevel = try XCTUnwrap(model.library.folders.first)
        XCTAssertNil(topLevel.parentID)

        model.openFolder(topLevel.id)
        model.createFolder()

        let child = try XCTUnwrap(model.library.folders.first { $0.parentID == topLevel.id })
        let folderIDsBeforeThirdCreation = Set(model.library.folders.map(\.id))

        model.openFolder(child.id)
        model.createFolder()

        XCTAssertEqual(Set(model.library.folders.map(\.id)), folderIDsBeforeThirdCreation)
    }

    func testFolderMovesCannotCreateASecondChildLevel() throws {
        let model = makeModel()
        let firstRoot = try model.library.createFolder(
            named: "First root",
            in: nil,
            at: DomainFixtures.fixedDate
        )
        let firstChild = try model.library.createFolder(
            named: "First child",
            in: firstRoot.id,
            at: DomainFixtures.fixedDate
        )
        let secondRoot = try model.library.createFolder(
            named: "Second root",
            in: nil,
            at: DomainFixtures.fixedDate
        )
        let secondChild = try model.library.createFolder(
            named: "Second child",
            in: secondRoot.id,
            at: DomainFixtures.fixedDate
        )

        model.moveFolder(firstChild.id, to: secondChild.id)
        model.moveFolder(firstRoot.id, to: secondRoot.id)

        XCTAssertEqual(model.library.folder(id: firstChild.id)?.parentID, firstRoot.id)
        XCTAssertNil(model.library.folder(id: firstRoot.id)?.parentID)
    }

    func testNotebookCanMoveIntoAChildFolder() throws {
        let model = makeModel()
        let root = try model.library.createFolder(named: "Root", in: nil, at: DomainFixtures.fixedDate)
        let child = try model.library.createFolder(
            named: "Child",
            in: root.id,
            at: DomainFixtures.fixedDate
        )
        let notebook = DomainFixtures.notebook()
        try model.library.addNotebook(notebook, to: nil)

        model.moveNotebook(notebook.id, to: child.id)

        XCTAssertEqual(model.library.notebook(id: notebook.id)?.parentFolderID, child.id)
    }

    func testEmptyFoldersCanMoveUnderAndBetweenTopLevelFolders() throws {
        let model = makeModel()
        let firstRoot = try model.library.createFolder(
            named: "First root",
            in: nil,
            at: DomainFixtures.fixedDate
        )
        let secondRoot = try model.library.createFolder(
            named: "Second root",
            in: nil,
            at: DomainFixtures.fixedDate
        )
        let thirdRoot = try model.library.createFolder(
            named: "Third root",
            in: nil,
            at: DomainFixtures.fixedDate
        )

        model.moveFolder(firstRoot.id, to: secondRoot.id)
        XCTAssertEqual(model.library.folder(id: firstRoot.id)?.parentID, secondRoot.id)

        model.moveFolder(firstRoot.id, to: thirdRoot.id)
        XCTAssertEqual(model.library.folder(id: firstRoot.id)?.parentID, thirdRoot.id)
    }

    func testMoveDestinationsApplyTheFolderDepthRule() throws {
        let model = makeModel()
        let firstRoot = try model.library.createFolder(
            named: "First root",
            in: nil,
            at: DomainFixtures.fixedDate
        )
        let child = try model.library.createFolder(
            named: "Child",
            in: firstRoot.id,
            at: DomainFixtures.fixedDate
        )
        let secondRoot = try model.library.createFolder(
            named: "Second root",
            in: nil,
            at: DomainFixtures.fixedDate
        )
        let notebook = DomainFixtures.notebook()
        try model.library.addNotebook(notebook, to: nil)

        let notebookDestinations = Set(
            model.availableMoveDestinations(for: [.notebook(notebook.id)]).map(\.id)
        )
        let childDestinations = Set(
            model.availableMoveDestinations(for: [.folder(child.id)]).map(\.id)
        )
        let parentDestinations = model.availableMoveDestinations(for: [.folder(firstRoot.id)])

        XCTAssertEqual(notebookDestinations, [firstRoot.id, child.id, secondRoot.id])
        XCTAssertEqual(childDestinations, [firstRoot.id, secondRoot.id])
        XCTAssertTrue(parentDestinations.isEmpty)
    }

    func testDeletingTheOpenFolderReturnsToItsActiveParent() throws {
        let model = makeModel()
        let root = try model.library.createFolder(
            named: "Root",
            in: nil,
            at: DomainFixtures.fixedDate
        )
        let child = try model.library.createFolder(
            named: "Child",
            in: root.id,
            at: DomainFixtures.fixedDate
        )
        model.openFolder(child.id)

        model.deleteFolder(child.id)
        model.createFolder()

        XCTAssertEqual(model.currentFolderID, root.id)
        XCTAssertEqual(
            model.library.folders.filter { $0.parentID == root.id && $0.trashedAt == nil }.count,
            1
        )
    }

    func testNotebookCreationNeverUsesATrashedCurrentFolder() throws {
        let model = makeModel()
        let root = try model.library.createFolder(
            named: "Root",
            in: nil,
            at: DomainFixtures.fixedDate
        )
        model.openFolder(root.id)

        model.deleteFolder(root.id)
        model.createNotebook()

        XCTAssertNil(model.currentFolderID)
        XCTAssertEqual(model.library.notebooks.count, 1)
        XCTAssertNil(model.library.notebooks.first?.parentFolderID)

        model.openFolder(root.id)
        let notebookIDsBeforeCreation = Set(model.library.notebooks.map(\.id))
        model.createNotebook()

        XCTAssertFalse(model.canCreateNotebook)
        XCTAssertEqual(Set(model.library.notebooks.map(\.id)), notebookIDsBeforeCreation)

        model.openFolder(FolderID())
        model.createNotebook()

        XCTAssertFalse(model.canCreateNotebook)
        XCTAssertEqual(Set(model.library.notebooks.map(\.id)), notebookIDsBeforeCreation)
    }

    func testRemoteFolderDeletionLeavesTheOpenFolder() async throws {
        let provider = InMemorySyncProvider()
        let model = AppModel(
            repository: LocalLibraryRepository(
                fileURL: FileManager.default.temporaryDirectory
                    .appending(path: UUID().uuidString)
                    .appending(path: "library.json")
            ),
            syncProvider: provider,
            deviceID: "receiving-device",
            automaticallyRestore: false
        )
        let folder = try model.library.createFolder(
            named: "Work",
            in: nil,
            at: DomainFixtures.fixedDate
        )
        model.openFolder(folder.id)
        let remoteChange = try SyncChangeEncoder(deviceID: "remote-device").change(
            for: .deleteFolder(folder.id),
            notebookID: NotebookID(rawValue: folder.id.rawValue),
            sequence: 1,
            timestamp: DomainFixtures.fixedDate.addingTimeInterval(60)
        )
        try await provider.push([remoteChange])

        await model.synchronize()

        XCTAssertNil(model.currentFolderID)
        XCTAssertNil(model.library.folder(id: folder.id))
        XCTAssertTrue(model.canCreateNotebook)
    }

    func testNotebookCreationSyncsItsSelectedFolder() async throws {
        let provider = InMemorySyncProvider()
        let model = AppModel(
            repository: LocalLibraryRepository(
                fileURL: FileManager.default.temporaryDirectory
                    .appending(path: UUID().uuidString)
                    .appending(path: "library.json")
            ),
            syncProvider: provider,
            deviceID: "creating-device",
            automaticallyRestore: false
        )
        let folder = try model.library.createFolder(
            named: "Work",
            in: nil,
            at: DomainFixtures.fixedDate
        )
        model.openFolder(folder.id)

        model.createNotebook()

        var changes: [DocumentChange] = []
        for _ in 0..<100 where changes.isEmpty {
            await Task.yield()
            changes = try await provider.pull(since: nil).changes
        }
        let creation = try XCTUnwrap(changes.lazy.compactMap { change -> Notebook? in
            guard let mutation = try? SyncChangeEncoder.decodeLibraryMutation(change),
                  case let .createNotebook(notebook) = mutation else { return nil }
            return notebook
        }.first)
        XCTAssertEqual(creation.parentFolderID, folder.id)
    }

    private func makeModel() -> AppModel {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString)
            .appending(path: "library.json")
        return AppModel(
            repository: LocalLibraryRepository(fileURL: fileURL),
            automaticallyRestore: false
        )
    }
}
