import XCTest
@testable import NoteNerds

@MainActor
final class FolderRestoreCompatibilityBehaviorTests: XCTestCase {
    func testNotebookRestoreKeepsUnrelatedTrashOnCurrentAndBuild14Apps() async throws {
        let provider = InMemorySyncProvider()
        let model = makeSyncedModel(provider: provider)
        let fixture = try makeFixture(in: model)
        var currentAppLibrary = model.library
        var build14Library = model.library

        model.restore(fixture.targetNotebook.id)

        let mutations = try await syncMutations(from: provider, minimumCount: 4)
        assertNotebookRestoreMutations(mutations, fixture: fixture)
        try apply(mutations, to: &currentAppLibrary, and: &build14Library)
        for (appVersion, library) in restoredLibraries(currentAppLibrary, build14Library) {
            assertNotebookRestoreScope(library, fixture: fixture, appVersion: appVersion)
        }
    }

    func testChildFolderRestoreKeepsUnrelatedTrashOnCurrentAndBuild14Apps() async throws {
        let provider = InMemorySyncProvider()
        let model = makeSyncedModel(provider: provider)
        let fixture = try makeFixture(in: model)
        var currentAppLibrary = model.library
        var build14Library = model.library

        model.restoreFolder(fixture.child.id)

        let mutations = try await syncMutations(from: provider, minimumCount: 2)
        assertFolderRestoreMutations(mutations, fixture: fixture)
        try apply(mutations, to: &currentAppLibrary, and: &build14Library)
        for (appVersion, library) in restoredLibraries(currentAppLibrary, build14Library) {
            assertFolderRestoreScope(library, fixture: fixture, appVersion: appVersion)
        }
    }

    private func makeFixture(in model: AppModel) throws -> RestoreScopeFixture {
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
        let sibling = try model.library.createFolder(
            named: "Sibling folder",
            in: parent.id,
            at: DomainFixtures.fixedDate
        )
        let fixture = RestoreScopeFixture(parent: parent, child: child, sibling: sibling)
        try model.library.addNotebook(fixture.targetNotebook, to: child.id)
        try model.library.addNotebook(fixture.childSiblingNotebook, to: child.id)
        try model.library.addNotebook(fixture.parentNotebook, to: parent.id)
        try model.library.addNotebook(fixture.nestedSiblingNotebook, to: sibling.id)
        try model.library.moveFolderToTrash(parent.id, at: DomainFixtures.fixedDate)
        return fixture
    }

    private func assertNotebookRestoreMutations(
        _ mutations: [LibrarySyncMutation],
        fixture: RestoreScopeFixture
    ) {
        XCTAssertTrue(mutations.contains(.restoreNotebook(fixture.targetNotebook.id)))
        XCTAssertTrue(mutations.contains { mutation in
            guard case let .updateNotebookMetadata(metadata) = mutation else { return false }
            return metadata.id == fixture.targetNotebook.id && metadata.trashedAt == nil
        })
        for folderID in [fixture.parent.id, fixture.child.id] {
            XCTAssertTrue(mutations.contains { mutation in
                guard case let .updateFolder(folder) = mutation else { return false }
                return folder.id == folderID && folder.trashedAt == nil
            })
        }
    }

    private func assertFolderRestoreMutations(
        _ mutations: [LibrarySyncMutation],
        fixture: RestoreScopeFixture
    ) {
        XCTAssertTrue(mutations.contains(.restoreFolder(fixture.child.id)))
        XCTAssertFalse(mutations.contains(.restoreFolder(fixture.parent.id)))
        XCTAssertTrue(mutations.contains { mutation in
            guard case let .updateFolder(folder) = mutation else { return false }
            return folder.id == fixture.parent.id && folder.trashedAt == nil
        })
    }

    private func assertNotebookRestoreScope(
        _ library: LibraryState,
        fixture: RestoreScopeFixture,
        appVersion: String
    ) {
        XCTAssertNil(library.folder(id: fixture.parent.id)?.trashedAt, appVersion)
        XCTAssertNil(library.folder(id: fixture.child.id)?.trashedAt, appVersion)
        XCTAssertNil(library.notebook(id: fixture.targetNotebook.id)?.trashedAt, appVersion)
        XCTAssertNotNil(library.folder(id: fixture.sibling.id)?.trashedAt, appVersion)
        XCTAssertNotNil(library.notebook(id: fixture.childSiblingNotebook.id)?.trashedAt, appVersion)
        XCTAssertNotNil(library.notebook(id: fixture.parentNotebook.id)?.trashedAt, appVersion)
        XCTAssertNotNil(library.notebook(id: fixture.nestedSiblingNotebook.id)?.trashedAt, appVersion)
    }

    private func assertFolderRestoreScope(
        _ library: LibraryState,
        fixture: RestoreScopeFixture,
        appVersion: String
    ) {
        XCTAssertNil(library.folder(id: fixture.parent.id)?.trashedAt, appVersion)
        XCTAssertNil(library.folder(id: fixture.child.id)?.trashedAt, appVersion)
        XCTAssertNil(library.notebook(id: fixture.targetNotebook.id)?.trashedAt, appVersion)
        XCTAssertNil(library.notebook(id: fixture.childSiblingNotebook.id)?.trashedAt, appVersion)
        XCTAssertNotNil(library.folder(id: fixture.sibling.id)?.trashedAt, appVersion)
        XCTAssertNotNil(library.notebook(id: fixture.parentNotebook.id)?.trashedAt, appVersion)
        XCTAssertNotNil(library.notebook(id: fixture.nestedSiblingNotebook.id)?.trashedAt, appVersion)
    }

    private func apply(
        _ mutations: [LibrarySyncMutation],
        to currentAppLibrary: inout LibraryState,
        and build14Library: inout LibraryState
    ) throws {
        for mutation in mutations {
            try mutation.apply(to: &currentAppLibrary)
            try applyAsBuild14(mutation, to: &build14Library)
        }
    }

    private func restoredLibraries(
        _ currentAppLibrary: LibraryState,
        _ build14Library: LibraryState
    ) -> [(String, LibraryState)] {
        [("current", currentAppLibrary), ("build 14", build14Library)]
    }

    private func makeSyncedModel(provider: InMemorySyncProvider) -> AppModel {
        AppModel(
            repository: LocalLibraryRepository(
                fileURL: FileManager.default.temporaryDirectory
                    .appending(path: UUID().uuidString)
                    .appending(path: "library.json")
            ),
            syncProvider: provider,
            deviceID: "restoring-device",
            automaticallyRestore: false
        )
    }

    private func syncMutations(
        from provider: InMemorySyncProvider,
        minimumCount: Int
    ) async throws -> [LibrarySyncMutation] {
        var changes: [DocumentChange] = []
        for _ in 0..<100 where changes.count < minimumCount {
            await Task.yield()
            changes = try await provider.pull(since: nil).changes
        }
        XCTAssertGreaterThanOrEqual(changes.count, minimumCount)
        return try changes.map(SyncChangeEncoder.decodeLibraryMutation)
    }

    private func applyAsBuild14(
        _ mutation: LibrarySyncMutation,
        to library: inout LibraryState
    ) throws {
        switch mutation {
        case let .createFolder(folder), let .updateFolder(folder):
            library.updateFolder(folder)
        case let .trashFolder(id, date):
            try library.moveFolderToTrash(id, at: date)
        case let .restoreFolder(id):
            try restoreFolderAsBuild14(id, in: &library)
        case let .deleteFolder(id):
            try library.permanentlyDeleteFolder(id)
        case let .createNotebook(notebook):
            guard library.notebook(id: notebook.id) == nil else { return }
            try library.addNotebook(notebook, to: notebook.parentFolderID)
        case let .updateNotebookMetadata(metadata):
            applyMetadataAsBuild14(metadata, to: &library)
        case .restoreNotebook:
            return
        case let .deleteNotebook(id):
            library.permanentlyDeleteNotebook(id)
        }
    }

    private func applyMetadataAsBuild14(
        _ metadata: NotebookSyncMetadata,
        to library: inout LibraryState
    ) {
        guard var notebook = library.notebook(id: metadata.id) else { return }
        notebook.title = metadata.title
        notebook.parentFolderID = metadata.parentFolderID
        notebook.modifiedAt = metadata.modifiedAt
        notebook.lastOpenedAt = metadata.lastOpenedAt
        notebook.isFavorite = metadata.isFavorite
        notebook.tags = metadata.tags
        notebook.trashedAt = metadata.trashedAt
        library.updateNotebook(notebook)
    }

    private func restoreFolderAsBuild14(
        _ id: FolderID,
        in library: inout LibraryState
    ) throws {
        guard library.folder(id: id) != nil else { throw LibraryError.folderNotFound }
        let restoredFolderIDs = descendantFolderIDs(startingAt: id, in: library)
        for folderID in restoredFolderIDs {
            guard var folder = library.folder(id: folderID) else { continue }
            folder.trashedAt = nil
            library.updateFolder(folder)
        }
        for storedNotebook in library.notebooks {
            guard let parentID = storedNotebook.parentFolderID,
                  restoredFolderIDs.contains(parentID) else { continue }
            var notebook = storedNotebook
            notebook.trashedAt = nil
            library.updateNotebook(notebook)
        }
    }

    private func descendantFolderIDs(
        startingAt id: FolderID,
        in library: LibraryState
    ) -> Set<FolderID> {
        var folderIDs: Set<FolderID> = [id]
        var previousCount = 0
        while folderIDs.count != previousCount {
            previousCount = folderIDs.count
            for folder in library.folders {
                guard let parentID = folder.parentID, folderIDs.contains(parentID) else { continue }
                folderIDs.insert(folder.id)
            }
        }
        return folderIDs
    }
}

private struct RestoreScopeFixture {
    let parent: Folder
    let child: Folder
    let sibling: Folder
    let targetNotebook = DomainFixtures.notebook(title: "Target notebook")
    let childSiblingNotebook = DomainFixtures.notebook(id: NotebookID(), title: "Child sibling")
    let parentNotebook = DomainFixtures.notebook(id: NotebookID(), title: "Parent notebook")
    let nestedSiblingNotebook = DomainFixtures.notebook(id: NotebookID(), title: "Nested sibling")
}
