import XCTest
@testable import NoteNerds

final class NotionSyncCoordinatorBehaviorTests: XCTestCase {
    func testFirstSyncUploadsAllRepresentationsAndCreatesOneNotebookRow() async throws {
        let store = CoordinatorStateStore(state: NotionSyncState(destination: destination))
        let registry = NotionSyncRegistry(store: store)
        let api = RecordingNotionSyncAPI()
        let coordinator = NotionSyncCoordinator(api: api, registry: registry)
        let payload = notebookPayload()

        let result = try await coordinator.sync(payload, to: destination)
        let events = await api.events
        let state = try await registry.snapshot()

        XCTAssertEqual(result, .uploaded(pageID: Self.pageID))
        XCTAssertEqual(events.filter { $0.hasPrefix("upload:") }.count, 4)
        XCTAssertTrue(events.contains("find:\(payload.snapshot.row.notebookID)"))
        XCTAssertTrue(events.contains("create:\(payload.snapshot.row.notebookID)"))
        XCTAssertFalse(events.contains(where: { $0.hasPrefix("update:") }))
        XCTAssertTrue(events.contains("replace:\(Self.pageID):none"))
        XCTAssertEqual(state.queue, [])
        XCTAssertEqual(state.binding(notebookID: payload.snapshot.row.notebookID)?.pageID, Self.pageID)
        XCTAssertEqual(
            state.binding(notebookID: payload.snapshot.row.notebookID)?.managedRootBlockID,
            Self.managedRootID
        )
    }

    func testRepeatedSyncWithSameHashMakesNoNotionRequest() async throws {
        let payload = notebookPayload()
        let binding = NotionNotebookBinding(
            notebookID: payload.snapshot.row.notebookID,
            pageID: Self.pageID,
            managedRootBlockID: Self.managedRootID,
            contentHash: payload.snapshot.row.contentHash,
            syncedAt: DomainFixtures.fixedDate,
            notionLastEditedAt: nil
        )
        let store = CoordinatorStateStore(
            state: NotionSyncState(destination: destination, bindings: [binding])
        )
        let api = RecordingNotionSyncAPI()
        let coordinator = NotionSyncCoordinator(
            api: api,
            registry: NotionSyncRegistry(store: store)
        )

        let result = try await coordinator.sync(payload, to: destination)
        let events = await api.events

        XCTAssertEqual(result, .skippedUnchanged)
        XCTAssertTrue(events.isEmpty)
    }

    func testChangedNotebookUpdatesBoundPageAndReplacesBoundManagedSection() async throws {
        let payload = notebookPayload()
        let binding = NotionNotebookBinding(
            notebookID: payload.snapshot.row.notebookID,
            pageID: Self.pageID,
            managedRootBlockID: "56565656-5656-5656-5656-565656565656",
            contentHash: String(repeating: "0", count: 64),
            syncedAt: DomainFixtures.fixedDate,
            notionLastEditedAt: nil
        )
        let store = CoordinatorStateStore(
            state: NotionSyncState(destination: destination, bindings: [binding])
        )
        let api = RecordingNotionSyncAPI()
        let coordinator = NotionSyncCoordinator(
            api: api,
            registry: NotionSyncRegistry(store: store)
        )

        _ = try await coordinator.sync(payload, to: destination)
        let events = await api.events

        XCTAssertTrue(events.contains("update:\(Self.pageID)"))
        XCTAssertTrue(events.contains("replace:\(Self.pageID):\(binding.managedRootBlockID!)"))
        XCTAssertFalse(events.contains(where: { $0.hasPrefix("find:") }))
        XCTAssertFalse(events.contains(where: { $0.hasPrefix("create:") }))
    }

    func testFailedUpsertRemainsQueuedWithActionableFailure() async throws {
        let payload = notebookPayload()
        let store = CoordinatorStateStore(state: NotionSyncState(destination: destination))
        let registry = NotionSyncRegistry(store: store)
        let api = RecordingNotionSyncAPI(failure: .httpStatus(403))
        let coordinator = NotionSyncCoordinator(api: api, registry: registry)

        do {
            _ = try await coordinator.sync(payload, to: destination)
            XCTFail("Expected the Notion request to fail")
        } catch {
            XCTAssertEqual(error as? NotionAPIError, .httpStatus(403))
        }
        let state = try await registry.snapshot()
        let queued = try XCTUnwrap(state.queue.first)
        XCTAssertEqual(queued.notebookID, payload.snapshot.row.notebookID)
        XCTAssertEqual(queued.attemptCount, 1)
        XCTAssertEqual(queued.lastFailure, .accessDenied)
    }

    func testRetryableFailurePersistsTheNextBoundedAttemptDate() async throws {
        let payload = notebookPayload()
        let registry = NotionSyncRegistry(store: CoordinatorStateStore(
            state: NotionSyncState(destination: destination)
        ))
        let coordinator = NotionSyncCoordinator(
            api: RecordingNotionSyncAPI(failure: .httpStatus(503)),
            registry: registry,
            now: { Date(timeIntervalSince1970: 100) },
            retryJitter: { _ in 0.5 }
        )

        _ = try? await coordinator.sync(payload, to: destination)
        let state = try await registry.snapshot()
        let queued = try XCTUnwrap(state.queue.first)

        XCTAssertEqual(queued.nextAttemptAt, Date(timeIntervalSince1970: 101.5))
        XCTAssertEqual(queued.lastFailure, .serviceUnavailable)
    }

    func testMissingBoundPageClearsStaleBindingBeforeUserRetries() async throws {
        let payload = notebookPayload()
        let binding = NotionNotebookBinding(
            notebookID: payload.snapshot.row.notebookID,
            pageID: Self.pageID,
            managedRootBlockID: Self.managedRootID,
            contentHash: String(repeating: "0", count: 64),
            syncedAt: DomainFixtures.fixedDate,
            notionLastEditedAt: nil
        )
        let registry = NotionSyncRegistry(store: CoordinatorStateStore(
            state: NotionSyncState(destination: destination, bindings: [binding])
        ))
        let coordinator = NotionSyncCoordinator(
            api: RecordingNotionSyncAPI(failure: .httpStatus(404)),
            registry: registry
        )

        _ = try? await coordinator.sync(payload, to: destination)
        let state = try await registry.snapshot()

        XCTAssertNil(state.binding(notebookID: payload.snapshot.row.notebookID))
        XCTAssertEqual(state.queue.first?.lastFailure, .missingRemotePage)
        XCTAssertNil(state.queue.first?.nextAttemptAt)
    }

    fileprivate static let pageID = "12121212-1212-1212-1212-121212121212"
    fileprivate static let managedRootID = "34343434-3434-3434-3434-343434343434"

    private var destination: NotionDestination {
        NotionDestination(
            databaseID: "78787878-7878-7878-7878-787878787878",
            dataSourceID: "90909090-9090-9090-9090-909090909090"
        )
    }

    private func notebookPayload() -> NotionNotebookPayload {
        let notebookID = "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB"
        let canvasA = NotionCanvasSnapshot(
            canvasID: "CDCDCDCD-CDCD-CDCD-CDCD-CDCDCDCDCDCD",
            title: "First",
            paperType: .blankWhite,
            layerCount: 1,
            typedText: ["One"],
            recognizedHandwriting: [],
            embeddedPDFText: []
        )
        let canvasB = NotionCanvasSnapshot(
            canvasID: "EFEFEFEF-EFEF-EFEF-EFEF-EFEFEFEFEFEF",
            title: "Second",
            paperType: .gridSmall,
            layerCount: 2,
            typedText: ["Two"],
            recognizedHandwriting: [],
            embeddedPDFText: []
        )
        return NotionNotebookPayload(
            snapshot: NotionNotebookSnapshot(
                row: NotionNotebookRow(
                    name: "Project Atlas",
                    folderPath: "Projects",
                    folderID: "10101010-1010-1010-1010-101010101010",
                    notebookID: notebookID,
                    modifiedAt: DomainFixtures.fixedDate,
                    canvasCount: 2,
                    tags: [],
                    isFavorite: false,
                    schemaVersion: 4,
                    contentHash: String(repeating: "e", count: 64),
                    syncStatus: .complete,
                    trashedAt: nil
                ),
                canvases: [canvasA, canvasB]
            ),
            nativeArchive: Data("native".utf8),
            pdf: Data("pdf".utf8),
            previews: [
                canvasA.canvasID: Data("preview-a".utf8),
                canvasB.canvasID: Data("preview-b".utf8)
            ]
        )
    }
}

private actor CoordinatorStateStore: NotionSyncStateStoring {
    private var state: NotionSyncState?

    init(state: NotionSyncState?) {
        self.state = state
    }

    func load() -> NotionSyncState? { state }
    func save(_ state: NotionSyncState) { self.state = state }
}

private actor RecordingNotionSyncAPI: NotionSyncAPI {
    private(set) var events: [String] = []
    private var uploadNumber = 0
    private let failure: NotionAPIError?

    init(failure: NotionAPIError? = nil) {
        self.failure = failure
    }

    func uploadFile(data: Data, filename: String, contentType: String) throws -> String {
        if let failure { throw failure }
        uploadNumber += 1
        events.append("upload:\(filename)")
        return String(format: "00000000-0000-0000-0000-%012d", uploadNumber)
    }

    func findNotebookPage(dataSourceID: String, notebookID: String) -> NotionPageBinding? {
        events.append("find:\(notebookID)")
        return nil
    }

    func createNotebookPage(
        dataSourceID: String,
        snapshot: NotionNotebookSnapshot,
        files: NotionNotebookRemoteFiles
    ) -> NotionPageBinding {
        events.append("create:\(snapshot.row.notebookID)")
        return NotionPageBinding(pageID: NotionSyncCoordinatorBehaviorTests.pageID, url: nil)
    }

    func updateNotebookPage(
        pageID: String,
        snapshot: NotionNotebookSnapshot,
        files: NotionNotebookRemoteFiles
    ) -> NotionPageBinding {
        events.append("update:\(pageID)")
        return NotionPageBinding(pageID: pageID, url: nil)
    }

    func findManagedRootBlock(pageID: String, notebookID: String) -> String? {
        events.append("managed-root:\(pageID)")
        return nil
    }

    func replaceManagedPage(
        pageID: String,
        oldRootID: String?,
        plan: NotionManagedPagePlan
    ) -> String {
        events.append("replace:\(pageID):\(oldRootID ?? "none")")
        return NotionSyncCoordinatorBehaviorTests.managedRootID
    }
}
