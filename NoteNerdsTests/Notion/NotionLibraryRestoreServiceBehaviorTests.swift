import XCTest
@testable import NoteNerds

@MainActor
final class NotionLibraryRestoreServiceBehaviorTests: XCTestCase {
    func testPrepareMarksMissingAndNewerNotionCopiesForRestore() async throws {
        var localNotebook = DomainFixtures.notebook(title: "Local")
        localNotebook.modifiedAt = DomainFixtures.fixedDate
        var newer = localNotebook
        newer.title = "Newer in Notion"
        newer.modifiedAt = DomainFixtures.fixedDate.addingTimeInterval(60)
        let missing = DomainFixtures.notebook(id: NotebookID(), title: "Missing")
        let snapshot = try remoteSnapshot(notebooks: [newer, missing])
        let service = NotionLibraryRestoreService(loader: FixedRemoteLoader(snapshot: snapshot))

        let candidates = try await service.prepare(local: LibraryState(notebooks: [localNotebook]))

        XCTAssertEqual(candidates.map(\.notebookID), [localNotebook.id, missing.id])
        XCTAssertEqual(candidates.map(\.isSelectedByDefault), [true, true])
        XCTAssertEqual(candidates.map(\.reason), [.newerInNotion, .missingLocally])
    }

    func testCompleteRestoreAppliesOnlySelectedConflictsAndAlwaysAddsMissingNotebooks() async throws {
        let localNotebook = DomainFixtures.notebook(title: "Keep local")
        var remoteNotebook = localNotebook
        remoteNotebook.title = "Notion copy"
        let missing = DomainFixtures.notebook(id: NotebookID(), title: "Missing")
        let snapshot = try remoteSnapshot(notebooks: [remoteNotebook, missing])
        let service = NotionLibraryRestoreService(loader: FixedRemoteLoader(snapshot: snapshot))
        let local = LibraryState(notebooks: [localNotebook])
        _ = try await service.prepare(local: local)

        let restored = try service.complete(local: local, choices: [
            localNotebook.id: .keepLocal,
            missing.id: .useNotion
        ])

        XCTAssertEqual(restored.notebook(id: localNotebook.id)?.title, "Keep local")
        XCTAssertEqual(restored.notebook(id: missing.id)?.title, "Missing")
    }

    private func remoteSnapshot(notebooks: [Notebook]) throws -> NotionRemoteLibrarySnapshot {
        let databaseID = "11111111-1111-1111-1111-111111111111"
        let manifest = NotionLibraryManifest(
            library: LibraryState(),
            databaseID: databaseID,
            dataSourceID: "22222222-2222-2222-2222-222222222222",
            generatedAt: DomainFixtures.fixedDate
        )
        return NotionRemoteLibrarySnapshot(
            manifestData: try NotionLibraryManifestCodec.encode(manifest),
            databaseID: databaseID,
            archives: try notebooks.map {
                try NotionTransportArchive().encode(
                    package: NativeNotebookPackage(schemaVersion: .current, notebook: $0),
                    assets: [],
                    exportedAt: DomainFixtures.fixedDate
                )
            }
        )
    }
}

private actor FixedRemoteLoader: NotionRemoteLibraryLoading {
    private let snapshot: NotionRemoteLibrarySnapshot
    init(snapshot: NotionRemoteLibrarySnapshot) { self.snapshot = snapshot }
    func load() -> NotionRemoteLibrarySnapshot { snapshot }
}
