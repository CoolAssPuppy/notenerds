import XCTest
@testable import NoteNerds

@MainActor
final class NotionEndToEndIntegrationTests: XCTestCase {
    func testRepeatedLibraryPublishDoesNotUploadAnUnchangedManifest() async throws {
        let destination = NotionDestination(
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222"
        )
        let manifestPageID = "33333333-3333-3333-3333-333333333333"
        let registry = NotionSyncRegistry(store: EndToEndStateStore(state: NotionSyncState(
            workspaceID: "workspace",
            destination: destination,
            manifestPageID: manifestPageID
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

        XCTAssertEqual(report.uploadedNotebookCount, 1)
        XCTAssertEqual(uploadedIDs, [second.id.rawValue.uuidString.lowercased()])
    }

    // swiftlint:disable:next function_body_length
    func testPublishThenRestoreRecreatesTheNotebookFolderAndAsset() async throws {
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
        let restoreService = NotionLibraryRestoreService(
            loader: NotionRemoteLibraryLoader(api: notion, registry: registry)
        )
        let candidates = try await restoreService.prepare(local: LibraryState())
        let restored = try restoreService.complete(
            local: LibraryState(),
            choices: Dictionary(uniqueKeysWithValues: candidates.map { ($0.notebookID, .useNotion) })
        )

        XCTAssertEqual(report.uploadedNotebookCount, 1)
        XCTAssertTrue(report.didUploadManifest)
        XCTAssertEqual(restored.folder(id: folder.id), folder)
        XCTAssertEqual(restored.notebook(id: notebook.id), notebook)
        XCTAssertEqual(restored.asset(id: assetID), asset)
    }
}

private actor EndToEndStateStore: NotionSyncStateStoring {
    private var state: NotionSyncState?
    init(state: NotionSyncState?) { self.state = state }
    func load() -> NotionSyncState? { state }
    func save(_ state: NotionSyncState) { self.state = state }
}

private actor LocalNotionService: NotionSyncAPI, NotionRestoreAPI {
    private let manifestPageID: String
    private var uploads: [String: Data] = [:]
    private var manifestUploadID: String?
    private var manifestUploadSequence = 0
    private var manifestRootID: String?
    private var notebookFiles: [String: (pageID: String, uploadID: String)] = [:]
    private var uploadSequence = 0
    private var rootSequence = 0

    init(manifestPageID: String) { self.manifestPageID = manifestPageID }

    func uploadFile(data: Data, filename: String, contentType: String) -> String {
        uploadSequence += 1
        let id = String(format: "AAAAAAAA-AAAA-AAAA-AAAA-%012d", uploadSequence)
        uploads[id] = data
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
        let pageID = String(format: "BBBBBBBB-BBBB-BBBB-BBBB-%012d", notebookFiles.count + 1)
        notebookFiles[snapshot.row.notebookID] = (pageID, files.nativeUploadID)
        return NotionPageBinding(pageID: pageID, url: nil)
    }

    func updateNotebookPage(
        pageID: String,
        snapshot: NotionNotebookSnapshot,
        files: NotionNotebookRemoteFiles
    ) -> NotionPageBinding {
        notebookFiles[snapshot.row.notebookID] = (pageID, files.nativeUploadID)
        return NotionPageBinding(pageID: pageID, url: nil)
    }

    func findManagedRootBlock(pageID: String, notebookID: String) -> String? { nil }

    func replaceManagedPage(
        pageID: String,
        oldRootID: String?,
        plan: NotionManagedPagePlan
    ) -> String {
        rootSequence += 1
        let rootID = String(format: "CCCCCCCC-CCCC-CCCC-CCCC-%012d", rootSequence)
        if pageID == manifestPageID { manifestRootID = rootID }
        return rootID
    }

    func listNativeNotebookFiles(dataSourceID: String) -> [NotionRemoteNotebookFile] {
        notebookFiles.sorted { $0.key < $1.key }.map { notebookID, value in
            NotionRemoteNotebookFile(
                pageID: value.pageID,
                notebookID: notebookID,
                url: URL(string: "https://local.notion/notebook/\(notebookID)")!
            )
        }
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
