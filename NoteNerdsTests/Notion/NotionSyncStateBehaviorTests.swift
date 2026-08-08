import XCTest
@testable import NoteNerds

final class NotionSyncStateBehaviorTests: XCTestCase {
    func testDurableStateRoundTripsDestinationBindingsAndQueueWithoutNotebookContent() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalNotionSyncStateStore(directoryURL: directory)
        let state = NotionSyncState(
            workspaceID: "workspace-id",
            destination: NotionDestination(
                databaseID: "11111111-1111-1111-1111-111111111111",
                dataSourceID: "22222222-2222-2222-2222-222222222222"
            ),
            manifestPageID: "33333333-3333-3333-3333-333333333333",
            bindings: [
                NotionNotebookBinding(
                    notebookID: "44444444-4444-4444-4444-444444444444",
                    pageID: "55555555-5555-5555-5555-555555555555",
                    managedRootBlockID: "66666666-6666-6666-6666-666666666666",
                    contentHash: String(repeating: "a", count: 64),
                    syncedAt: Date(timeIntervalSince1970: 100),
                    notionLastEditedAt: Date(timeIntervalSince1970: 90)
                )
            ],
            queue: [
                NotionSyncQueueItem(
                    notebookID: "44444444-4444-4444-4444-444444444444",
                    enqueuedAt: Date(timeIntervalSince1970: 101),
                    attemptCount: 2,
                    nextAttemptAt: Date(timeIntervalSince1970: 120),
                    lastFailure: .rateLimited
                )
            ]
        )

        try await store.save(state)
        let restored = try await store.load()
        let fileURL = directory.appending(path: "notion-sync-state.plist")
        let serialized = try Data(contentsOf: fileURL)

        XCTAssertEqual(restored, state)
        XCTAssertNil(serialized.range(of: Data("notebook text".utf8)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testRegistryCoalescesNotebookWorkAndPersistsEveryMutation() async throws {
        let store = InMemoryNotionSyncStateStore()
        let registry = NotionSyncRegistry(store: store, now: { Date(timeIntervalSince1970: 200) })
        let firstID = "77777777-7777-7777-7777-777777777777"
        let secondID = "88888888-8888-8888-8888-888888888888"

        try await registry.enqueue(notebookID: firstID)
        try await registry.enqueue(notebookID: secondID)
        try await registry.enqueue(notebookID: firstID)
        var state = try await registry.snapshot()

        XCTAssertEqual(state.queue.map(\.notebookID), [firstID, secondID])
        XCTAssertEqual(state.queue[0].attemptCount, 0)

        try await registry.recordFailure(
            notebookID: firstID,
            failure: .serviceUnavailable,
            retryAt: Date(timeIntervalSince1970: 220)
        )
        state = try await registry.snapshot()
        XCTAssertEqual(state.queue[0].attemptCount, 1)
        XCTAssertEqual(state.queue[0].lastFailure, .serviceUnavailable)

        let binding = NotionNotebookBinding(
            notebookID: firstID,
            pageID: "99999999-9999-9999-9999-999999999999",
            managedRootBlockID: nil,
            contentHash: String(repeating: "b", count: 64),
            syncedAt: Date(timeIntervalSince1970: 230),
            notionLastEditedAt: nil
        )
        try await registry.recordSuccess(binding)
        state = try await registry.snapshot()
        let saveCount = await store.saveCount

        XCTAssertEqual(state.queue.map(\.notebookID), [secondID])
        XCTAssertEqual(state.binding(notebookID: firstID), binding)
        XCTAssertEqual(saveCount, 4)
    }

    func testRegistrySkipsAnUnchangedNotebookInTheSameDestination() async throws {
        let notebookID = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        let destination = NotionDestination(
            databaseID: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB",
            dataSourceID: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
        )
        let binding = NotionNotebookBinding(
            notebookID: notebookID,
            pageID: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD",
            managedRootBlockID: nil,
            contentHash: String(repeating: "c", count: 64),
            syncedAt: Date(timeIntervalSince1970: 300),
            notionLastEditedAt: nil
        )
        let store = InMemoryNotionSyncStateStore(
            state: NotionSyncState(destination: destination, bindings: [binding])
        )
        let registry = NotionSyncRegistry(store: store)

        let unchangedNeedsSync = try await registry.needsSync(
            notebookID: notebookID,
            contentHash: binding.contentHash,
            destination: destination
        )
        let changedNeedsSync = try await registry.needsSync(
            notebookID: notebookID,
            contentHash: String(repeating: "d", count: 64),
            destination: destination
        )

        XCTAssertFalse(unchangedNeedsSync)
        XCTAssertTrue(changedNeedsSync)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "NoteNerds-Notion-State-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}

private actor InMemoryNotionSyncStateStore: NotionSyncStateStoring {
    private var state: NotionSyncState?
    private(set) var saveCount = 0

    init(state: NotionSyncState? = nil) {
        self.state = state
    }

    func load() -> NotionSyncState? {
        state
    }

    func save(_ state: NotionSyncState) {
        self.state = state
        saveCount += 1
    }
}
