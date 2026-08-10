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
            tags: ["active"],
            icon: .systemSymbol(.briefcase),
            iconColor: FolderIconColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1)
        )
        let empty = Folder.fixture(name: "Empty", parentID: root.id)
        let trashed = Folder.fixture(
            name: "Old",
            parentID: root.id,
            trashedAt: DomainFixtures.fixedDate.addingTimeInterval(60)
        )
        let png = try FolderIconPNG(data: try XCTUnwrap(Data(base64Encoded: Self.onePixelPNG)))
        let art = Folder.fixture(name: "Art", icon: .customPNG(png))
        let library = LibraryState(folders: [trashed, empty, root, art])
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
        let expectedIDs = [root.id, empty.id, trashed.id, art.id].sorted {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }
        XCTAssertEqual(restored.folders.map(\.id), expectedIDs)
        XCTAssertEqual(restored.folders.first(where: { $0.id == root.id })?.tags, ["active"])
        XCTAssertEqual(restored.folders.first(where: { $0.id == root.id })?.isFavorite, true)
        XCTAssertEqual(restored.folders.first(where: { $0.id == root.id })?.icon, root.icon)
        XCTAssertEqual(restored.folders.first(where: { $0.id == root.id })?.iconColor, root.iconColor)
        XCTAssertEqual(restored.folders.first(where: { $0.id == empty.id })?.parentID, root.id)
        XCTAssertEqual(restored.folders.first(where: { $0.id == art.id })?.icon, .customPNG(png))
        XCTAssertEqual(
            restored.folders.first(where: { $0.id == trashed.id })?.trashedAt,
            DomainFixtures.fixedDate.addingTimeInterval(60)
        )
    }

    func testLibraryManifestPreservesInheritedTrashProvenance() throws {
        let root = Folder.fixture(name: "Root")
        let restoredSibling = Folder.fixture(name: "Restored", parentID: root.id)
        let inheritedChild = Folder.fixture(name: "Inherited", parentID: root.id)
        var secondNotebook = DomainFixtures.notebook()
        secondNotebook.parentFolderID = inheritedChild.id
        var firstNotebook = DomainFixtures.notebook(
            id: NotebookID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        )
        firstNotebook.parentFolderID = inheritedChild.id
        let trashDate = DomainFixtures.fixedDate.addingTimeInterval(90)
        var library = LibraryState(
            folders: [root, restoredSibling, inheritedChild],
            notebooks: [secondNotebook, firstNotebook]
        )
        try library.moveFolderToTrash(root.id, at: trashDate)
        try library.restoreFolder(restoredSibling.id)
        let manifest = NotionLibraryManifest(
            library: library,
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222",
            generatedAt: DomainFixtures.fixedDate
        )

        let restored = try NotionLibraryManifestCodec.decode(
            NotionLibraryManifestCodec.encode(manifest)
        )

        XCTAssertEqual(
            restored.folders.first(where: { $0.id == inheritedChild.id })?.folder.inheritedTrashDate,
            trashDate
        )
        XCTAssertEqual(
            restored.notebookTrashProvenance.map(\.notebookID),
            [firstNotebook.id, secondNotebook.id]
        )
        XCTAssertEqual(restored.notebookTrashProvenance.map(\.inheritedTrashDate), [trashDate, trashDate])
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

    func testLibraryManifestRejectsInvalidFolderAppearanceAndOversizedOutput() throws {
        let folder = Folder.fixture(name: "Projects")
        let manifest = NotionLibraryManifest(
            library: LibraryState(folders: [folder]),
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222",
            generatedAt: DomainFixtures.fixedDate
        )
        let encoded = try NotionLibraryManifestCodec.encode(manifest)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var folders = try XCTUnwrap(object["folders"] as? [[String: Any]])
        folders[0]["icon"] = ["unknown": [:]]
        object["folders"] = folders

        XCTAssertThrowsError(try decodeManifest(object))

        folders[0]["icon"] = NSNull()
        object["folders"] = folders

        XCTAssertThrowsError(try decodeManifest(object))

        let oversizedFolder = Folder.fixture(
            name: String(repeating: "a", count: NotionLibraryManifestCodec.maximumByteCount)
        )
        let oversizedManifest = NotionLibraryManifest(
            library: LibraryState(folders: [oversizedFolder]),
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222",
            generatedAt: DomainFixtures.fixedDate
        )
        XCTAssertThrowsError(try NotionLibraryManifestCodec.encode(oversizedManifest)) { error in
            XCTAssertEqual(error as? NotionLibraryManifestError, .manifestTooLarge)
        }
    }

    func testLegacyLibraryManifestUsesTheStandardFolderAppearance() throws {
        let folder = Folder.fixture(
            name: "Projects",
            icon: .systemSymbol(.briefcase),
            iconColor: FolderIconColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        )
        let manifest = NotionLibraryManifest(
            library: LibraryState(folders: [folder]),
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222",
            generatedAt: DomainFixtures.fixedDate
        )
        let encoded = try NotionLibraryManifestCodec.encode(manifest)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var folders = try XCTUnwrap(object["folders"] as? [[String: Any]])
        folders[0].removeValue(forKey: "icon")
        folders[0].removeValue(forKey: "iconColor")
        folders[0].removeValue(forKey: "appearanceModifiedAt")
        folders[0].removeValue(forKey: "inheritedTrashDate")
        object["folders"] = folders
        object.removeValue(forKey: "notebookTrashProvenance")

        let restored = try decodeManifest(object)

        XCTAssertEqual(restored.folders.first?.icon, .standard)
        XCTAssertNil(restored.folders.first?.iconColor)
        XCTAssertNil(restored.folders.first?.folder.inheritedTrashDate)
        XCTAssertTrue(restored.notebookTrashProvenance.isEmpty)
    }

    private func decodeManifest(_ object: [String: Any]) throws -> NotionLibraryManifest {
        try NotionLibraryManifestCodec.decode(JSONSerialization.data(withJSONObject: object))
    }

    private static let onePixelPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/l8xO7wAAAABJRU5ErkJggg=="
}

private extension Folder {
    static func fixture(
        id: FolderID = FolderID(),
        name: String,
        parentID: FolderID? = nil,
        isFavorite: Bool = false,
        tags: Set<String> = [],
        trashedAt: Date? = nil,
        icon: FolderIcon = .systemSymbol(.folder),
        iconColor: FolderIconColor? = nil
    ) -> Folder {
        Folder(
            id: id,
            name: name,
            parentID: parentID,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate.addingTimeInterval(30),
            isFavorite: isFavorite,
            tags: tags,
            trashedAt: trashedAt,
            icon: icon,
            iconColor: iconColor
        )
    }
}
