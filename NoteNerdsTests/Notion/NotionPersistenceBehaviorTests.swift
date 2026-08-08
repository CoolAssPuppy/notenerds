import XCTest
@testable import NoteNerds

final class NotionPersistenceBehaviorTests: XCTestCase {
    func testFolderPathUsesEveryParentAndNamesTheLibraryRoot() throws {
        let work = Folder.fixture(name: "Work")
        let clients = Folder.fixture(name: "Clients", parentID: work.id)
        let acme = Folder.fixture(name: "Acme", parentID: clients.id)
        let library = LibraryState(folders: [acme, work, clients])

        XCTAssertEqual(
            try NotionFolderPathResolver.path(for: acme.id, in: library),
            "Work / Clients / Acme"
        )
        XCTAssertEqual(
            try NotionFolderPathResolver.path(for: nil, in: library),
            "My Notebooks"
        )
    }

    func testFolderPathRejectsMissingParentsAndCycles() {
        let missingParent = Folder.fixture(name: "Orphan", parentID: FolderID())
        let firstID = FolderID()
        let secondID = FolderID()
        let first = Folder.fixture(id: firstID, name: "First", parentID: secondID)
        let second = Folder.fixture(id: secondID, name: "Second", parentID: firstID)

        XCTAssertThrowsError(
            try NotionFolderPathResolver.path(
                for: missingParent.id,
                in: LibraryState(folders: [missingParent])
            )
        ) { error in
            XCTAssertEqual(error as? NotionFolderPathError, .missingFolder(missingParent.parentID!))
        }
        XCTAssertThrowsError(
            try NotionFolderPathResolver.path(
                for: firstID,
                in: LibraryState(folders: [first, second])
            )
        ) { error in
            XCTAssertEqual(error as? NotionFolderPathError, .cycle(firstID))
        }
    }

    func testLibraryManifestPreservesEmptyNestedAndTrashedFolderMetadata() throws {
        let root = Folder.fixture(
            name: "Projects",
            isFavorite: true,
            tags: ["active"]
        )
        let empty = Folder.fixture(name: "Empty", parentID: root.id)
        let trashed = Folder.fixture(
            name: "Old",
            parentID: root.id,
            trashedAt: DomainFixtures.fixedDate.addingTimeInterval(60)
        )
        let library = LibraryState(folders: [trashed, empty, root])
        let manifest = NotionLibraryManifest(
            library: library,
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222",
            generatedAt: DomainFixtures.fixedDate
        )

        let restored = try NotionLibraryManifestCodec.decode(
            NotionLibraryManifestCodec.encode(manifest)
        )

        XCTAssertEqual(restored, manifest)
        let expectedIDs = [root.id, empty.id, trashed.id].sorted {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }
        XCTAssertEqual(restored.folders.map(\.id), expectedIDs)
        XCTAssertEqual(restored.folders.first(where: { $0.id == root.id })?.tags, ["active"])
        XCTAssertEqual(restored.folders.first(where: { $0.id == root.id })?.isFavorite, true)
        XCTAssertEqual(restored.folders.first(where: { $0.id == empty.id })?.parentID, root.id)
        XCTAssertEqual(
            restored.folders.first(where: { $0.id == trashed.id })?.trashedAt,
            DomainFixtures.fixedDate.addingTimeInterval(60)
        )
    }

    func testLibraryManifestEncodingIsStableAcrossFolderInsertionOrder() throws {
        let first = Folder.fixture(name: "First")
        let second = Folder.fixture(name: "Second")
        let firstManifest = NotionLibraryManifest(
            library: LibraryState(folders: [first, second]),
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222",
            generatedAt: DomainFixtures.fixedDate
        )
        let secondManifest = NotionLibraryManifest(
            library: LibraryState(folders: [second, first]),
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222",
            generatedAt: DomainFixtures.fixedDate
        )

        XCTAssertEqual(
            try NotionLibraryManifestCodec.encode(firstManifest),
            try NotionLibraryManifestCodec.encode(secondManifest)
        )
    }

    func testLibraryManifestRejectsNewerSchemasInvalidDestinationsAndDuplicateFolders() throws {
        let folder = Folder.fixture(name: "Projects")
        let manifest = NotionLibraryManifest(
            library: LibraryState(folders: [folder]),
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222",
            generatedAt: DomainFixtures.fixedDate
        )
        let encoded = try NotionLibraryManifestCodec.encode(manifest)
        let original = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var newer = original
        newer["schemaVersion"] = 2
        var invalidDestination = original
        invalidDestination["databaseID"] = "not-a-database-id"
        var duplicateFolders = original
        let folders = try XCTUnwrap(original["folders"] as? [[String: Any]])
        duplicateFolders["folders"] = folders + folders

        XCTAssertThrowsError(try decodeManifest(newer)) { error in
            XCTAssertEqual(error as? NotionLibraryManifestError, .unsupportedSchema(2))
        }
        XCTAssertThrowsError(try decodeManifest(invalidDestination)) { error in
            XCTAssertEqual(error as? NotionLibraryManifestError, .invalidDestination)
        }
        XCTAssertThrowsError(try decodeManifest(duplicateFolders)) { error in
            XCTAssertEqual(error as? NotionLibraryManifestError, .duplicateFolder(folder.id))
        }
    }

    private func decodeManifest(_ object: [String: Any]) throws -> NotionLibraryManifest {
        try NotionLibraryManifestCodec.decode(JSONSerialization.data(withJSONObject: object))
    }
}

private extension Folder {
    static func fixture(
        id: FolderID = FolderID(),
        name: String,
        parentID: FolderID? = nil,
        isFavorite: Bool = false,
        tags: Set<String> = [],
        trashedAt: Date? = nil
    ) -> Folder {
        Folder(
            id: id,
            name: name,
            parentID: parentID,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate.addingTimeInterval(30),
            isFavorite: isFavorite,
            tags: tags,
            trashedAt: trashedAt
        )
    }
}
