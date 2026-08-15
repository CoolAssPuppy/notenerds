import XCTest
@testable import NoteNerds

final class SyncOutboxPersistBehaviorTests: XCTestCase {
    func testRapidFollowUpEnqueuesShareOneOutboxWrite() async throws {
        let store = CountingSyncStateStore()
        let engine = SyncEngine(provider: InMemorySyncProvider(), stateStore: store)
        let first = DocumentChange.fixture(objectKey: "first", sequence: 1)
        let second = DocumentChange.fixture(objectKey: "second", sequence: 2)
        let third = DocumentChange.fixture(objectKey: "third", sequence: 3)

        await engine.enqueue(first)
        let afterFirst = await store.saveCount
        XCTAssertEqual(afterFirst, 1)

        await engine.enqueue(second)
        await engine.enqueue(third)
        let duringBurst = await store.saveCount
        XCTAssertEqual(duringBurst, 1)

        try await Task.sleep(for: .milliseconds(300))
        let afterQuiet = await store.saveCount
        let snapshot = await store.load()
        XCTAssertEqual(afterQuiet, 2)
        XCTAssertEqual(snapshot?.pendingChanges, [first, second, third])
    }
}

private actor CountingSyncStateStore: SyncStateStore {
    private var snapshot: SyncEngineSnapshot?
    private(set) var saveCount = 0

    func load() -> SyncEngineSnapshot? { snapshot }

    func save(_ snapshot: SyncEngineSnapshot) {
        self.snapshot = snapshot
        saveCount += 1
    }
}
