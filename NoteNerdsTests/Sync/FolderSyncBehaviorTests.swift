import XCTest
@testable import NoteNerds

final class FolderSyncBehaviorTests: XCTestCase {
    func testLibraryMetadataSyncDoesNotReplaceNotebookContent() throws {
        var notebook = DomainFixtures.notebook(title: "Before")
        var library = LibraryState(notebooks: [notebook])
        notebook.title = "After"
        notebook.isFavorite = true
        let mutation = LibrarySyncMutation.updateNotebookMetadata(NotebookSyncMetadata(notebook: notebook))
        let change = try SyncChangeEncoder(deviceID: "device").change(
            for: mutation,
            notebookID: notebook.id,
            sequence: 3,
            timestamp: DomainFixtures.fixedDate
        )

        try SyncChangeEncoder.decodeLibraryMutation(change).apply(to: &library)

        XCTAssertEqual(library.notebook(id: notebook.id)?.title, "After")
        XCTAssertEqual(library.notebook(id: notebook.id)?.isFavorite, true)
        XCTAssertEqual(library.notebook(id: notebook.id)?.canvases, DomainFixtures.notebook().canvases)
    }

    func testFolderDeletionSyncUsesRecoverableTombstone() throws {
        var library = LibraryState()
        let folder = try library.createFolder(named: "Archive", in: nil, at: DomainFixtures.fixedDate)
        let mutation = LibrarySyncMutation.trashFolder(folder.id, date: DomainFixtures.fixedDate)

        try mutation.apply(to: &library)

        XCTAssertEqual(library.folder(id: folder.id)?.trashedAt, DomainFixtures.fixedDate)
    }

    func testActiveFolderUpdateCannotUndoDirectFolderTrash() throws {
        let trashDate = DomainFixtures.fixedDate.addingTimeInterval(30)
        var library = LibraryState()
        let folder = try library.createFolder(named: "Work", in: nil, at: DomainFixtures.fixedDate)
        var staleActiveUpdate = folder
        staleActiveUpdate.name = "Work renamed elsewhere"
        staleActiveUpdate.modifiedAt = DomainFixtures.fixedDate.addingTimeInterval(60)
        try library.moveFolderToTrash(folder.id, at: trashDate)

        try LibrarySyncMutation.updateFolder(staleActiveUpdate).apply(to: &library)

        XCTAssertEqual(library.folder(id: folder.id)?.name, "Work renamed elsewhere")
        XCTAssertEqual(library.folder(id: folder.id)?.trashedAt, trashDate)
    }

    func testActiveChildMovedUnderTrashedParentTrashesItsExistingSubtree() throws {
        let trashDate = DomainFixtures.fixedDate.addingTimeInterval(30)
        var library = LibraryState()
        let parent = try library.createFolder(named: "Parent", in: nil, at: DomainFixtures.fixedDate)
        let child = try library.createFolder(named: "Child", in: nil, at: DomainFixtures.fixedDate)
        let grandchild = try library.createFolder(named: "Grandchild", in: child.id, at: DomainFixtures.fixedDate)
        let greatGrandchild = try library.createFolder(
            named: "Great-grandchild",
            in: grandchild.id,
            at: DomainFixtures.fixedDate
        )
        let childNotebook = DomainFixtures.notebook(title: "Child notebook")
        let descendantNotebook = DomainFixtures.notebook(
            id: NotebookID(),
            title: "Descendant notebook"
        )
        try library.addNotebook(childNotebook, to: child.id)
        try library.addNotebook(descendantNotebook, to: greatGrandchild.id)
        try library.moveFolderToTrash(parent.id, at: trashDate)
        var activeChildUpdate = child
        activeChildUpdate.parentID = parent.id
        activeChildUpdate.modifiedAt = DomainFixtures.fixedDate.addingTimeInterval(60)

        try LibrarySyncMutation.updateFolder(activeChildUpdate).apply(to: &library)

        XCTAssertEqual(library.folder(id: child.id)?.trashedAt, trashDate)
        XCTAssertEqual(library.folder(id: grandchild.id)?.trashedAt, trashDate)
        XCTAssertEqual(library.folder(id: greatGrandchild.id)?.trashedAt, trashDate)
        XCTAssertEqual(library.notebook(id: childNotebook.id)?.trashedAt, trashDate)
        XCTAssertEqual(library.notebook(id: descendantNotebook.id)?.trashedAt, trashDate)
    }

    func testExplicitNotebookRestoreRestoresItsFolderChainOnAnotherDevice() throws {
        var library = LibraryState()
        let parent = try library.createFolder(named: "Parent", in: nil, at: DomainFixtures.fixedDate)
        let child = try library.createFolder(named: "Child", in: parent.id, at: DomainFixtures.fixedDate)
        let notebook = DomainFixtures.notebook()
        try library.addNotebook(notebook, to: child.id)
        try library.moveFolderToTrash(parent.id, at: DomainFixtures.fixedDate)
        try LibrarySyncMutation.restoreNotebook(notebook.id).apply(to: &library)
        library.emptyTrash()

        XCTAssertNotNil(library.folder(id: parent.id))
        XCTAssertNotNil(library.folder(id: child.id))
        XCTAssertNotNil(library.notebook(id: notebook.id))
    }

    func testActiveNotebookMetadataCannotUndoAConcurrentFolderTrash() throws {
        var original = LibraryState()
        let parent = try original.createFolder(named: "Parent", in: nil, at: DomainFixtures.fixedDate)
        let child = try original.createFolder(named: "Child", in: parent.id, at: DomainFixtures.fixedDate)
        let notebook = DomainFixtures.notebook()
        try original.addNotebook(notebook, to: child.id)
        var editedNotebook = try XCTUnwrap(original.notebook(id: notebook.id))
        editedNotebook.isFavorite = true
        let metadata = LibrarySyncMutation.updateNotebookMetadata(
            NotebookSyncMetadata(notebook: editedNotebook)
        )
        var firstDevice = original
        var secondDevice = original

        try firstDevice.moveFolderToTrash(parent.id, at: DomainFixtures.fixedDate)
        try metadata.apply(to: &firstDevice)
        try metadata.apply(to: &secondDevice)
        try LibrarySyncMutation.trashFolder(
            parent.id,
            date: DomainFixtures.fixedDate
        ).apply(to: &secondDevice)

        XCTAssertEqual(firstDevice, secondDevice)
        XCTAssertNotNil(firstDevice.notebook(id: notebook.id)?.trashedAt)
    }

    func testOlderAppNotebookRestoreClearsIndividualTrashWhenItsFolderIsActive() throws {
        var library = LibraryState()
        let parent = try library.createFolder(named: "Parent", in: nil, at: DomainFixtures.fixedDate)
        let notebook = DomainFixtures.notebook()
        try library.addNotebook(notebook, to: parent.id)
        library.moveNotebookToTrash(notebook.id, at: DomainFixtures.fixedDate)
        var restoredNotebook = try XCTUnwrap(library.notebook(id: notebook.id))
        restoredNotebook.trashedAt = nil

        try LibrarySyncMutation.updateNotebookMetadata(
            NotebookSyncMetadata(notebook: restoredNotebook)
        ).apply(to: &library)

        XCTAssertNil(library.notebook(id: notebook.id)?.trashedAt)
    }

    func testOlderAppNotebookRestoreCannotUndoTrashedFolder() throws {
        var library = LibraryState()
        let parent = try library.createFolder(named: "Parent", in: nil, at: DomainFixtures.fixedDate)
        let notebook = DomainFixtures.notebook()
        try library.addNotebook(notebook, to: parent.id)
        try library.moveFolderToTrash(parent.id, at: DomainFixtures.fixedDate)
        var restoredSnapshot = try XCTUnwrap(library.notebook(id: notebook.id))
        restoredSnapshot.trashedAt = nil

        try LibrarySyncMutation.updateNotebookMetadata(
            NotebookSyncMetadata(notebook: restoredSnapshot)
        ).apply(to: &library)

        XCTAssertEqual(library.notebook(id: notebook.id)?.trashedAt, DomainFixtures.fixedDate)
    }

    func testActiveNotebookMetadataEditCannotUndoDirectNotebookTrash() throws {
        let trashDate = DomainFixtures.fixedDate.addingTimeInterval(30)
        var library = LibraryState()
        let parent = try library.createFolder(named: "Parent", in: nil, at: DomainFixtures.fixedDate)
        let notebook = DomainFixtures.notebook()
        try library.addNotebook(notebook, to: parent.id)
        var staleActiveEdit = notebook
        staleActiveEdit.title = "Renamed elsewhere"
        staleActiveEdit.modifiedAt = DomainFixtures.fixedDate.addingTimeInterval(60)
        library.moveNotebookToTrash(notebook.id, at: trashDate)

        try LibrarySyncMutation.updateNotebookMetadata(
            NotebookSyncMetadata(notebook: staleActiveEdit)
        ).apply(to: &library)

        XCTAssertEqual(library.notebook(id: notebook.id)?.title, "Renamed elsewhere")
        XCTAssertEqual(library.notebook(id: notebook.id)?.trashedAt, trashDate)
    }

    func testTrashedParentWinsAConcurrentNotebookCreation() throws {
        var original = LibraryState()
        let parent = try original.createFolder(named: "Parent", in: nil, at: DomainFixtures.fixedDate)
        let child = try original.createFolder(named: "Child", in: parent.id, at: DomainFixtures.fixedDate)
        var notebook = DomainFixtures.notebook()
        notebook.parentFolderID = child.id
        let creation = LibrarySyncMutation.createNotebook(notebook)
        var firstDevice = original
        var secondDevice = original

        try firstDevice.moveFolderToTrash(parent.id, at: DomainFixtures.fixedDate)
        try creation.apply(to: &firstDevice)
        try creation.apply(to: &secondDevice)
        try LibrarySyncMutation.trashFolder(
            parent.id,
            date: DomainFixtures.fixedDate
        ).apply(to: &secondDevice)

        XCTAssertEqual(firstDevice, secondDevice)
        XCTAssertNotNil(firstDevice.notebook(id: notebook.id)?.trashedAt)
    }

    func testFolderIconSurvivesTheCloudChangePayload() throws {
        let folder = Folder(
            name: "Work",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate,
            icon: .emoji(try FolderEmoji("💼")),
            iconColor: FolderIconColor(red: 0.9, green: 0.3, blue: 0.1, alpha: 1)
        )
        let mutation = LibrarySyncMutation.updateFolder(folder)
        let change = try SyncChangeEncoder(deviceID: "device").change(
            for: mutation,
            notebookID: NotebookID(rawValue: folder.id.rawValue),
            sequence: 4,
            timestamp: DomainFixtures.fixedDate
        )
        var library = LibraryState()

        try SyncChangeEncoder.decodeLibraryMutation(change).apply(to: &library)

        XCTAssertEqual(library.folder(id: folder.id)?.icon, folder.icon)
        XCTAssertEqual(library.folder(id: folder.id)?.iconColor, folder.iconColor)
    }

    func testCustomFolderImageSurvivesTheCloudChangePayload() throws {
        let png = try FolderIconPNG(data: try XCTUnwrap(Data(base64Encoded: Self.onePixelPNG)))
        let folder = Folder(
            name: "Art",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate,
            icon: .customPNG(png)
        )
        let mutation = LibrarySyncMutation.updateFolder(folder)
        let change = try SyncChangeEncoder(deviceID: "device").change(
            for: mutation,
            notebookID: NotebookID(rawValue: folder.id.rawValue),
            sequence: 5,
            timestamp: DomainFixtures.fixedDate
        )
        var library = LibraryState()

        try SyncChangeEncoder.decodeLibraryMutation(change).apply(to: &library)

        XCTAssertEqual(library.folder(id: folder.id)?.icon, .customPNG(png))
    }

    func testOlderFolderUpdateCannotEraseAStoredAppearance() throws {
        let identifier = FolderID()
        let color = FolderIconColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        let customized = Folder(
            id: identifier,
            name: "Work",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate,
            icon: .systemSymbol(.briefcase),
            iconColor: color
        )
        let olderAppUpdate = Folder(
            id: identifier,
            name: "Renamed on older app",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate.addingTimeInterval(60)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        var encodedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoder.encode(olderAppUpdate)) as? [String: Any]
        )
        encodedObject.removeValue(forKey: "icon")
        encodedObject.removeValue(forKey: "iconColor")
        encodedObject.removeValue(forKey: "appearanceModifiedAt")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let decodedUpdate = try decoder.decode(
            Folder.self,
            from: JSONSerialization.data(withJSONObject: encodedObject)
        )
        var library = LibraryState(folders: [customized])

        try LibrarySyncMutation.updateFolder(decodedUpdate).apply(to: &library)

        XCTAssertEqual(library.folder(id: identifier)?.name, "Renamed on older app")
        XCTAssertEqual(library.folder(id: identifier)?.icon, .systemSymbol(.briefcase))
        XCTAssertEqual(library.folder(id: identifier)?.iconColor, color)
    }

    func testConcurrentFolderMovesCannotCreateACycle() throws {
        let firstID = FolderID(rawValue: try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        ))
        let secondID = FolderID(rawValue: try XCTUnwrap(
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")
        ))
        let first = Folder(
            id: firstID,
            name: "First",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        let second = Folder(
            id: secondID,
            name: "Second",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        var firstMove = first
        firstMove.parentID = second.id
        var secondMove = second
        secondMove.parentID = first.id
        var firstDevice = LibraryState(folders: [firstMove, second])
        var secondDevice = LibraryState(folders: [first, secondMove])

        try LibrarySyncMutation.updateFolder(secondMove).apply(to: &firstDevice)
        try LibrarySyncMutation.updateFolder(firstMove).apply(to: &secondDevice)

        XCTAssertEqual(firstDevice, secondDevice)
        XCTAssertEqual(firstDevice.folder(id: first.id)?.parentID, second.id)
        XCTAssertNil(firstDevice.folder(id: second.id)?.parentID)
    }

    func testTrashedParentWinsAConcurrentActiveChildUpdate() throws {
        var original = LibraryState()
        let parent = try original.createFolder(named: "Parent", in: nil, at: DomainFixtures.fixedDate)
        let child = try original.createFolder(named: "Child", in: parent.id, at: DomainFixtures.fixedDate)
        var editedChild = child
        editedChild.name = "Edited child"
        editedChild.modifiedAt = DomainFixtures.fixedDate.addingTimeInterval(60)
        var firstDevice = original
        var secondDevice = original

        try firstDevice.moveFolderToTrash(parent.id, at: DomainFixtures.fixedDate.addingTimeInterval(30))
        try LibrarySyncMutation.updateFolder(editedChild).apply(to: &firstDevice)
        try LibrarySyncMutation.updateFolder(editedChild).apply(to: &secondDevice)
        try LibrarySyncMutation.trashFolder(
            parent.id,
            date: DomainFixtures.fixedDate.addingTimeInterval(30)
        ).apply(to: &secondDevice)

        XCTAssertEqual(firstDevice, secondDevice)
        XCTAssertNotNil(firstDevice.folder(id: child.id)?.trashedAt)
        firstDevice.emptyTrash()
        XCTAssertNil(firstDevice.folder(id: parent.id))
        XCTAssertNil(firstDevice.folder(id: child.id))
    }

    func testOversizedFolderChangePayloadIsRejectedBeforeJSONDecoding() throws {
        let folder = Folder(
            name: "Work",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        let original = try SyncChangeEncoder(deviceID: "device").change(
            for: .updateFolder(folder),
            notebookID: NotebookID(rawValue: folder.id.rawValue),
            sequence: 6,
            timestamp: DomainFixtures.fixedDate
        )
        let oversized = DocumentChange(
            id: original.id,
            notebookID: original.notebookID,
            objectKey: original.objectKey,
            kind: original.kind,
            payload: original.payload + Data(
                repeating: 0x20,
                count: SyncChangeEncoder.maximumLibraryMutationPayloadByteCount + 1
            ),
            timestamp: original.timestamp,
            deviceID: original.deviceID,
            sequence: original.sequence
        )

        XCTAssertThrowsError(try SyncChangeEncoder.decodeLibraryMutation(oversized))
    }

    func testOversizedFolderChangeIsRejectedBeforeUpload() {
        let folder = Folder(
            name: String(
                repeating: "a",
                count: SyncChangeEncoder.maximumLibraryMutationPayloadByteCount + 1
            ),
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )

        XCTAssertThrowsError(
            try SyncChangeEncoder(deviceID: "device").change(
                for: .updateFolder(folder),
                notebookID: NotebookID(rawValue: folder.id.rawValue),
                sequence: 7,
                timestamp: DomainFixtures.fixedDate
            )
        )
    }

    func testLegacyFolderChangeLargerThanTheOldLimitStillRoundTrips() throws {
        let folder = Folder(
            name: String(repeating: "a", count: 200_000),
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )

        let change = try SyncChangeEncoder(deviceID: "device").change(
            for: .updateFolder(folder),
            notebookID: NotebookID(rawValue: folder.id.rawValue),
            sequence: 9,
            timestamp: DomainFixtures.fixedDate
        )

        XCTAssertEqual(try SyncChangeEncoder.decodeLibraryMutation(change), .updateFolder(folder))
    }

    func testLargeNotebookLibraryChangeIsNotLimitedToFolderPayloadSize() throws {
        var notebook = DomainFixtures.notebook()
        notebook.title = String(
            repeating: "a",
            count: SyncChangeEncoder.maximumLibraryMutationPayloadByteCount + 1
        )
        let change = try SyncChangeEncoder(deviceID: "device").change(
            for: .createNotebook(notebook),
            notebookID: notebook.id,
            sequence: 8,
            timestamp: DomainFixtures.fixedDate
        )

        XCTAssertGreaterThan(
            change.payload.count,
            SyncChangeEncoder.maximumLibraryMutationPayloadByteCount
        )
        XCTAssertEqual(
            try SyncChangeEncoder.decodeLibraryMutation(change),
            .createNotebook(notebook)
        )
    }

    private static let onePixelPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAFgwJ/l8xO7wAAAABJRU5ErkJggg=="

}
