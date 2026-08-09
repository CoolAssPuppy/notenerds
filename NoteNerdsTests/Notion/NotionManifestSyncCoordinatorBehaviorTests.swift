import XCTest
@testable import NoteNerds

final class NotionManifestSyncTests: XCTestCase {
    func testManifestSyncUploadsAndReplacesOnlyItsManagedSection() async throws {
        let pageID = "11111111-1111-1111-1111-111111111111"
        let oldRootID = "22222222-2222-2222-2222-222222222222"
        let newRootID = "33333333-3333-3333-3333-333333333333"
        let state = NotionSyncState(
            manifestPageID: pageID,
            manifestRootBlockID: oldRootID,
            manifestContentHash: String(repeating: "0", count: 64)
        )
        let store = ManifestStateStore(state: state)
        let registry = NotionSyncRegistry(store: store)
        let api = ManifestSyncAPI(rootID: newRootID)
        let coordinator = NotionManifestSyncCoordinator(api: api, registry: registry)
        let data = Data("manifest".utf8)

        let result = try await coordinator.sync(data)
        let updated = try await registry.snapshot()
        let calls = await api.calls

        XCTAssertEqual(result, .uploaded(pageID: pageID))
        XCTAssertEqual(calls, ["upload:library-manifest.json", "replace:\(pageID):\(oldRootID)"])
        XCTAssertEqual(updated.manifestRootBlockID, newRootID)
        XCTAssertEqual(updated.manifestContentHash, NotionContentHasher.sha256Hex(of: data))
    }

    func testUnchangedManifestMakesNoNotionRequest() async throws {
        let data = Data("manifest".utf8)
        let state = NotionSyncState(
            manifestPageID: "44444444-4444-4444-4444-444444444444",
            manifestContentHash: NotionContentHasher.sha256Hex(of: data)
        )
        let registry = NotionSyncRegistry(store: ManifestStateStore(state: state))
        let api = ManifestSyncAPI(rootID: "55555555-5555-5555-5555-555555555555")
        let coordinator = NotionManifestSyncCoordinator(api: api, registry: registry)

        let result = try await coordinator.sync(data)
        let calls = await api.calls

        XCTAssertEqual(result, .skippedUnchanged)
        XCTAssertEqual(calls, [])
    }

    func testManifestSyncRequiresConfiguredPage() async {
        let coordinator = NotionManifestSyncCoordinator(
            api: ManifestSyncAPI(rootID: "66666666-6666-6666-6666-666666666666"),
            registry: NotionSyncRegistry(store: ManifestStateStore(state: NotionSyncState()))
        )

        do {
            _ = try await coordinator.sync(Data("manifest".utf8))
            XCTFail("Expected a missing manifest page to fail")
        } catch {
            XCTAssertEqual(error as? NotionOAuthError, .noConnection)
        }
    }
}

private actor ManifestStateStore: NotionSyncStateStoring {
    private var state: NotionSyncState?
    init(state: NotionSyncState?) { self.state = state }
    func load() -> NotionSyncState? { state }
    func save(_ state: NotionSyncState) { self.state = state }
}

private actor ManifestSyncAPI: NotionSyncAPI {
    private(set) var calls: [String] = []
    private let rootID: String

    init(rootID: String) { self.rootID = rootID }

    func uploadFile(data: Data, filename: String, contentType: String) -> String {
        calls.append("upload:\(filename)")
        return "77777777-7777-7777-7777-777777777777"
    }

    func replaceManagedPage(
        pageID: String,
        oldRootID: String?,
        plan: NotionManagedPagePlan
    ) -> String {
        calls.append("replace:\(pageID):\(oldRootID ?? "none")")
        return rootID
    }

    func findNotebookPage(dataSourceID: String, notebookID: String) -> NotionPageBinding? { nil }
    func createNotebookPage(
        dataSourceID: String,
        snapshot: NotionNotebookSnapshot,
        files: NotionNotebookRemoteFiles
    ) -> NotionPageBinding { fatalError("Unused") }
    func updateNotebookPage(
        pageID: String,
        snapshot: NotionNotebookSnapshot,
        files: NotionNotebookRemoteFiles
    ) -> NotionPageBinding { fatalError("Unused") }
    func trashNotebookPage(pageID: String) { fatalError("Unused") }
    func findManagedRootBlock(pageID: String, notebookID: String) -> String? { nil }
}
