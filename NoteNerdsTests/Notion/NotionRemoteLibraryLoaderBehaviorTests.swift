import XCTest
@testable import NoteNerds

final class NotionRemoteLibraryLoaderBehaviorTests: XCTestCase {
    func testLoaderUsesSavedDestinationAndDiscoversMissingManifestRoot() async throws {
        let destination = NotionDestination(
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222"
        )
        let manifestPageID = "33333333-3333-3333-3333-333333333333"
        let registry = NotionSyncRegistry(
            store: LoaderStateStore(state: NotionSyncState(
                destination: destination,
                manifestPageID: manifestPageID
            ))
        )
        let notebook = DomainFixtures.notebook()
        let archive = try NotionTransportArchive().encode(
            package: NativeNotebookPackage(schemaVersion: .current, notebook: notebook),
            assets: [],
            exportedAt: DomainFixtures.fixedDate
        )
        let manifest = NotionLibraryManifest(
            library: LibraryState(),
            databaseID: destination.databaseID,
            dataSourceID: destination.dataSourceID,
            generatedAt: DomainFixtures.fixedDate
        )
        let api = LoaderRestoreAPI(
            manifestData: try NotionLibraryManifestCodec.encode(manifest),
            archive: archive,
            notebookID: notebook.id.rawValue.uuidString.lowercased()
        )

        let remote = try await NotionRemoteLibraryLoader(api: api, registry: registry).load()
        let calls = await api.calls

        XCTAssertEqual(remote.databaseID, destination.databaseID)
        XCTAssertEqual(remote.archives, [archive])
        XCTAssertEqual(calls.first, "find-root:\(manifestPageID)")
        XCTAssertEqual(calls.filter { $0.hasPrefix("download:") }.count, 2)
    }

    func testLoaderRejectsArchiveWhoseNotebookIDDoesNotMatchItsRow() async throws {
        let destination = NotionDestination(
            databaseID: "11111111-1111-1111-1111-111111111111",
            dataSourceID: "22222222-2222-2222-2222-222222222222"
        )
        let registry = NotionSyncRegistry(
            store: LoaderStateStore(state: NotionSyncState(
                destination: destination,
                manifestPageID: "33333333-3333-3333-3333-333333333333",
                manifestRootBlockID: "44444444-4444-4444-4444-444444444444"
            ))
        )
        let archive = try NotionTransportArchive().encode(
            package: NativeNotebookPackage(schemaVersion: .current, notebook: DomainFixtures.notebook()),
            assets: [],
            exportedAt: DomainFixtures.fixedDate
        )
        let manifest = NotionLibraryManifest(
            library: LibraryState(),
            databaseID: destination.databaseID,
            dataSourceID: destination.dataSourceID,
            generatedAt: DomainFixtures.fixedDate
        )
        let api = LoaderRestoreAPI(
            manifestData: try NotionLibraryManifestCodec.encode(manifest),
            archive: archive,
            notebookID: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        )

        do {
            _ = try await NotionRemoteLibraryLoader(api: api, registry: registry).load()
            XCTFail("Expected the mismatched row to fail")
        } catch {
            XCTAssertEqual(error as? NotionRestoreError, .notebookIDMismatch)
        }
    }
}

private actor LoaderStateStore: NotionSyncStateStoring {
    private var state: NotionSyncState?
    init(state: NotionSyncState?) { self.state = state }
    func load() -> NotionSyncState? { state }
    func save(_ state: NotionSyncState) { self.state = state }
}

private actor LoaderRestoreAPI: NotionRestoreAPI {
    private let manifestData: Data
    private let archive: Data
    private let notebookID: String
    private(set) var calls: [String] = []

    init(manifestData: Data, archive: Data, notebookID: String) {
        self.manifestData = manifestData
        self.archive = archive
        self.notebookID = notebookID
    }

    func listNativeNotebookFiles(dataSourceID: String) -> [NotionRemoteNotebookFile] {
        calls.append("list:\(dataSourceID)")
        return [NotionRemoteNotebookFile(
            pageID: "55555555-5555-5555-5555-555555555555",
            notebookID: notebookID.lowercased(),
            url: URL(string: "https://files.example/notebook")!
        )]
    }

    func findLibraryManifestRootBlock(pageID: String) -> String? {
        calls.append("find-root:\(pageID)")
        return "44444444-4444-4444-4444-444444444444"
    }

    func findManagedFile(rootBlockID: String) -> URL {
        calls.append("find-file:\(rootBlockID)")
        return URL(string: "https://files.example/manifest")!
    }

    func downloadFile(from url: URL, maximumByteCount: Int) -> Data {
        calls.append("download:\(url.lastPathComponent)")
        return url.lastPathComponent == "manifest" ? manifestData : archive
    }
}
