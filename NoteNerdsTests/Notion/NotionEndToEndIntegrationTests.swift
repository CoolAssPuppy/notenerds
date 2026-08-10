import XCTest
@testable import NoteNerds

@MainActor
final class NotionEndToEndIntegrationTests: XCTestCase {
    func testNotebookReferenceIsPublishedBeforeTheFolderManifest() async throws {
        let destination = NotionDestination(
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222"
        )
        let registry = NotionSyncRegistry(store: EndToEndStateStore(state: NotionSyncState(
            workspaceID: "workspace",
            destination: destination,
            manifestPageID: "33333333-3333-3333-3333-333333333333"
        )))
        let notion = LocalNotionService(manifestPageID: "33333333-3333-3333-3333-333333333333")

        _ = try await NotionLibraryPublisher(api: notion, registry: registry)
            .publish(LibraryState(notebooks: [DomainFixtures.notebook()]))

        let events = await notion.publicationEvents()
        XCTAssertEqual(events, ["notebook", "manifest"])
    }

    func testNotebookDeletionIsPublishedBeforeTheFolderManifest() async throws {
        let destination = NotionDestination(
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222"
        )
        let registry = NotionSyncRegistry(store: EndToEndStateStore(state: NotionSyncState(
            workspaceID: "workspace",
            destination: destination,
            manifestPageID: "33333333-3333-3333-3333-333333333333",
            bindings: [NotionNotebookBinding(
                notebookID: "dddddddd-dddd-dddd-dddd-dddddddddddd",
                pageID: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE",
                managedRootBlockID: nil,
                contentHash: String(repeating: "a", count: 64),
                syncedAt: DomainFixtures.fixedDate,
                notionLastEditedAt: nil
            )]
        )))
        let notion = LocalNotionService(manifestPageID: "33333333-3333-3333-3333-333333333333")

        _ = try await NotionLibraryPublisher(api: notion, registry: registry)
            .publish(LibraryState())

        let events = await notion.publicationEvents()
        XCTAssertEqual(events, ["deletion", "manifest"])
    }

    func testRepeatedLibraryPublishDoesNotUploadAnUnchangedManifest() async throws {
        let destination = NotionDestination(
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222"
        )
        let manifestPageID = "33333333-3333-3333-3333-333333333333"
        let registry = NotionSyncRegistry(store: EndToEndStateStore(state: NotionSyncState(
            workspaceID: "workspace",
            destination: destination,
            manifestPageID: manifestPageID,
            bindings: [NotionNotebookBinding(
                notebookID: "ffffffff-ffff-ffff-ffff-ffffffffffff",
                pageID: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD",
                managedRootBlockID: nil,
                contentHash: String(repeating: "a", count: 64),
                syncedAt: DomainFixtures.fixedDate,
                notionLastEditedAt: nil
            )]
        )))
        let notion = LocalNotionService(manifestPageID: manifestPageID)
        let dates = SequenceDateProvider([
            DomainFixtures.fixedDate,
            DomainFixtures.fixedDate.addingTimeInterval(60)
        ])
        let publisher = NotionLibraryPublisher(
            api: notion,
            registry: registry,
            now: dates.next
        )

        let first = try await publisher.publish(LibraryState())
        let second = try await publisher.publish(LibraryState())
        let manifestUploadCount = await notion.manifestUploadCount()

        XCTAssertTrue(first.didUploadManifest)
        XCTAssertFalse(second.didUploadManifest)
        XCTAssertEqual(manifestUploadCount, 1)
    }

    func testNotebookActionPublishesOnlyTheSelectedNotebook() async throws {
        let destination = NotionDestination(
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222"
        )
        let manifestPageID = "33333333-3333-3333-3333-333333333333"
        let first = DomainFixtures.notebook()
        let second = DomainFixtures.notebook(
            id: NotebookID(rawValue: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!),
            title: "Selected"
        )
        let library = LibraryState(notebooks: [first, second])
        let registry = NotionSyncRegistry(store: EndToEndStateStore(state: NotionSyncState(
            workspaceID: "workspace",
            destination: destination,
            manifestPageID: manifestPageID
        )))
        let notion = LocalNotionService(manifestPageID: manifestPageID)
        let publisher = NotionLibraryPublisher(api: notion, registry: registry)

        let report = try await publisher.publish(library, notebookID: second.id)
        let uploadedIDs = await notion.uploadedNotebookIDs()
        let trashedPageIDs = await notion.trashedNotebookPageIDs()

        XCTAssertEqual(report.uploadedNotebookCount, 1)
        XCTAssertEqual(uploadedIDs, [second.id.rawValue.uuidString.lowercased()])
        XCTAssertTrue(trashedPageIDs.isEmpty)
    }

    func testFullPublishTrashesBoundPageForNotebookMissingAfterEmptyTrash() async throws {
        let notebookID = "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD".lowercased()
        let pageID = "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE"
        let meetingLinks = DeletionMeetingCoordinator()
        let destination = NotionDestination(
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222"
        )
        let registry = NotionSyncRegistry(store: EndToEndStateStore(state: NotionSyncState(
            workspaceID: "workspace",
            destination: destination,
            manifestPageID: "33333333-3333-3333-3333-333333333333",
            bindings: [NotionNotebookBinding(
                notebookID: notebookID,
                pageID: pageID,
                managedRootBlockID: nil,
                contentHash: String(repeating: "a", count: 64),
                syncedAt: DomainFixtures.fixedDate,
                notionLastEditedAt: nil
            )],
            queue: [NotionSyncQueueItem(
                notebookID: notebookID,
                enqueuedAt: DomainFixtures.fixedDate,
                attemptCount: 2,
                nextAttemptAt: DomainFixtures.fixedDate.addingTimeInterval(60),
                lastFailure: .serviceUnavailable
            )]
        )))
        let notion = LocalNotionService(manifestPageID: "33333333-3333-3333-3333-333333333333")

        let report = try await NotionLibraryPublisher(
            api: notion,
            registry: registry,
            meetingLinkCoordinator: meetingLinks
        )
            .publish(LibraryState())
        let state = try await registry.snapshot()
        let trashedPageIDs = await notion.trashedNotebookPageIDs()
        let cleanedNotebookIDs = await meetingLinks.cleanedNotebookIDs

        XCTAssertEqual(report.deletedNotebookCount, 1)
        XCTAssertEqual(trashedPageIDs, [pageID])
        XCTAssertEqual(cleanedNotebookIDs, [notebookID])
        XCTAssertNil(state.binding(notebookID: notebookID))
        XCTAssertTrue(state.queue.isEmpty)
    }

    func testFullPublishKeepsBoundPageWhileNotebookRemainsInAppTrash() async throws {
        var notebook = DomainFixtures.notebook()
        notebook.trashedAt = DomainFixtures.fixedDate
        let notebookID = notebook.id.rawValue.uuidString.lowercased()
        let pageID = "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE"
        let destination = NotionDestination(
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222"
        )
        let registry = NotionSyncRegistry(store: EndToEndStateStore(state: NotionSyncState(
            workspaceID: "workspace",
            destination: destination,
            manifestPageID: "33333333-3333-3333-3333-333333333333",
            bindings: [NotionNotebookBinding(
                notebookID: notebookID,
                pageID: pageID,
                managedRootBlockID: nil,
                contentHash: String(repeating: "a", count: 64),
                syncedAt: DomainFixtures.fixedDate,
                notionLastEditedAt: nil
            )]
        )))
        let notion = LocalNotionService(manifestPageID: "33333333-3333-3333-3333-333333333333")

        let report = try await NotionLibraryPublisher(api: notion, registry: registry)
            .publish(LibraryState(notebooks: [notebook]))
        let state = try await registry.snapshot()
        let trashedPageIDs = await notion.trashedNotebookPageIDs()

        XCTAssertEqual(report.deletedNotebookCount, 0)
        XCTAssertTrue(trashedPageIDs.isEmpty)
        XCTAssertNotNil(state.binding(notebookID: notebookID))
    }

    func testPublishCreatesAReferenceWithoutCopyingTheNotebookOrAssetToNotion() async throws {
        let destination = NotionDestination(
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222"
        )
        let manifestPageID = "33333333-3333-3333-3333-333333333333"
        let folder = Folder(
            id: FolderID(rawValue: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!),
            name: "Projects",
            parentID: nil,
            createdAt: DomainFixtures.fixedDate,
            modifiedAt: DomainFixtures.fixedDate
        )
        let assetID = AssetID(rawValue: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!)
        var notebook = DomainFixtures.notebook()
        notebook.parentFolderID = folder.id
        let layerID = notebook.canvases[0].layers[0].id
        notebook.canvases[0].layers[0].objects.append(
            .image(ImageObject(
                id: ObjectID(),
                layerID: layerID,
                assetID: assetID,
                frame: CanvasRect(x: 50, y: 50, width: 100, height: 100),
                rotation: 0
            ))
        )
        let asset = DocumentAsset(id: assetID, data: Data("original asset".utf8), contentType: "image/png")
        var source = LibraryState(folders: [folder], notebooks: [notebook])
        source.storeAsset(asset)
        let registry = NotionSyncRegistry(store: EndToEndStateStore(state: NotionSyncState(
            workspaceID: "workspace",
            destination: destination,
            manifestPageID: manifestPageID
        )))
        let notion = LocalNotionService(manifestPageID: manifestPageID)

        let report = try await NotionLibraryPublisher(
            api: notion,
            registry: registry,
            now: { DomainFixtures.fixedDate }
        ).publish(source)
        let filenames = await notion.uploadedFilenames()

        XCTAssertEqual(report.uploadedNotebookCount, 1)
        XCTAssertTrue(report.didUploadManifest)
        XCTAssertEqual(filenames.filter { $0.hasSuffix(".png") }.count, notebook.canvases.count)
        XCTAssertTrue(filenames.contains("library-manifest.json"))
        XCTAssertFalse(filenames.contains { $0.hasSuffix(".notenerds.json") })
        XCTAssertFalse(filenames.contains { $0.hasSuffix(".pdf") })
    }
}

private actor DeletionMeetingCoordinator: NotionMeetingLinkCoordinating {
    private(set) var cleanedNotebookIDs: [String] = []

    func check(notebookID: String) -> NotionMeetingLinkResult { .noActiveMeeting }
    func link(meetingID: String, notebookID: String) -> NotionMeetingLinkResult { .noActiveMeeting }
    func removeLinks(notebookID: String) { cleanedNotebookIDs.append(notebookID) }
}

private actor EndToEndStateStore: NotionSyncStateStoring {
    private var state: NotionSyncState?
    init(state: NotionSyncState?) { self.state = state }
    func load() -> NotionSyncState? { state }
    func save(_ state: NotionSyncState) { self.state = state }
}

private actor LocalNotionService: NotionSyncAPI, NotionRestoreAPI {
    private struct NotebookFileRecord {
        let pageID: String
        let uploadID: String
        let contentHash: String
    }

    private let manifestPageID: String
    private var uploads: [String: Data] = [:]
    private var uploadedFileNames: [String] = []
    private var manifestUploadID: String?
    private var manifestUploadSequence = 0
    private var manifestRootID: String?
    private var notebookFiles: [String: NotebookFileRecord] = [:]
    private var trashedPageIDs: [String] = []
    private var uploadSequence = 0
    private var rootSequence = 0
    private var events: [String] = []

    init(manifestPageID: String) { self.manifestPageID = manifestPageID }

    func uploadFile(data: Data, filename: String, contentType: String) -> String {
        uploadSequence += 1
        let id = String(format: "AAAAAAAA-AAAA-AAAA-AAAA-%012d", uploadSequence)
        uploads[id] = data
        uploadedFileNames.append(filename)
        if filename == "library-manifest.json" {
            manifestUploadID = id
            manifestUploadSequence += 1
        }
        return id
    }

    func findNotebookPage(dataSourceID: String, notebookID: String) -> NotionPageBinding? {
        notebookFiles[notebookID].map { NotionPageBinding(pageID: $0.pageID, url: nil) }
    }

    func createNotebookPage(
        dataSourceID: String,
        snapshot: NotionNotebookSnapshot,
        files: NotionNotebookRemoteFiles
    ) -> NotionPageBinding {
        events.append("notebook")
        let pageID = String(format: "BBBBBBBB-BBBB-BBBB-BBBB-%012d", notebookFiles.count + 1)
        notebookFiles[snapshot.row.notebookID] = NotebookFileRecord(
            pageID: pageID,
            uploadID: files.nativeUploadID ?? "",
            contentHash: snapshot.row.contentHash
        )
        return NotionPageBinding(pageID: pageID, url: nil)
    }

    func updateNotebookPage(
        pageID: String,
        snapshot: NotionNotebookSnapshot,
        files: NotionNotebookRemoteFiles
    ) -> NotionPageBinding {
        events.append("notebook")
        notebookFiles[snapshot.row.notebookID] = NotebookFileRecord(
            pageID: pageID,
            uploadID: files.nativeUploadID ?? "",
            contentHash: snapshot.row.contentHash
        )
        return NotionPageBinding(pageID: pageID, url: nil)
    }

    func findManagedRootBlock(pageID: String, notebookID: String) -> String? { nil }

    func trashNotebookPage(pageID: String) {
        events.append("deletion")
        trashedPageIDs.append(pageID)
        notebookFiles = notebookFiles.filter { $0.value.pageID != pageID }
    }

    func replaceManagedPage(
        pageID: String,
        oldRootID: String?,
        plan: NotionManagedPagePlan
    ) -> String {
        rootSequence += 1
        let rootID = String(format: "CCCCCCCC-CCCC-CCCC-CCCC-%012d", rootSequence)
        if pageID == manifestPageID {
            manifestRootID = rootID
            events.append("manifest")
        }
        return rootID
    }

    func listNativeNotebookFiles(dataSourceID: String) -> [NotionRemoteNotebookFile] {
        notebookFiles.sorted { $0.key < $1.key }.map { notebookID, value in
            NotionRemoteNotebookFile(
                pageID: value.pageID,
                notebookID: notebookID,
                contentHash: value.contentHash,
                url: URL(string: "https://local.notion/notebook/\(notebookID)")!
            )
        }
    }

    func fetchNativeNotebookFile(pageID: String) throws -> NotionRemoteNotebookFile {
        guard let entry = notebookFiles.first(where: { $0.value.pageID == pageID }) else {
            throw NotionAPIError.invalidResponse
        }
        return NotionRemoteNotebookFile(
            pageID: pageID,
            notebookID: entry.key,
            contentHash: entry.value.contentHash,
            url: URL(string: "https://local.notion/notebook/\(entry.key)")!
        )
    }

    func findLibraryManifestRootBlock(pageID: String) -> String? { manifestRootID }

    func findManagedFile(rootBlockID: String) -> URL {
        URL(string: "https://local.notion/manifest")!
    }

    func downloadFile(from url: URL, maximumByteCount: Int) throws -> Data {
        let uploadID: String?
        if url.lastPathComponent == "manifest" {
            uploadID = manifestUploadID
        } else {
            uploadID = notebookFiles[url.lastPathComponent]?.uploadID
        }
        guard let uploadID, let data = uploads[uploadID], data.count <= maximumByteCount else {
            throw NotionAPIError.invalidResponse
        }
        return data
    }

    func uploadedNotebookIDs() -> [String] {
        notebookFiles.keys.sorted()
    }

    func manifestUploadCount() -> Int {
        manifestUploadSequence
    }

    func uploadedFilenames() -> [String] {
        uploadedFileNames
    }

    func trashedNotebookPageIDs() -> [String] {
        trashedPageIDs
    }

    func publicationEvents() -> [String] {
        events
    }
}

private final class SequenceDateProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var dates: [Date]

    init(_ dates: [Date]) {
        self.dates = dates
    }

    func next() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return dates.removeFirst()
    }
}
