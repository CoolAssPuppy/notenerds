import XCTest
@testable import NoteNerds

@MainActor
final class BackgroundSyncCoordinatorTests: XCTestCase {
    func testInactiveDoesNotStartNotionSyncAndBackgroundDoes() async {
        let syncStarted = expectation(description: "Notion sync started")
        let syncGate = BackgroundSyncGate()
        let backgroundTasks = BackgroundSyncTaskManagerSpy()
        let coordinator = ApplicationBackgroundSyncCoordinator(
            backgroundTasks: backgroundTasks,
            sync: {
                syncStarted.fulfill()
                await syncGate.wait()
            }
        )

        coordinator.transition(to: .inactive)
        await Task.yield()
        XCTAssertEqual(backgroundTasks.beginCount, 0)

        coordinator.transition(to: .background)
        await fulfillment(of: [syncStarted], timeout: 1)
        XCTAssertEqual(backgroundTasks.beginCount, 1)
        XCTAssertTrue(coordinator.isSyncInProgress)

        syncGate.open()
        await coordinator.waitForSyncToFinish()
        coordinator.transition(to: .background)

        XCTAssertEqual(backgroundTasks.endedIDs.count, 1)
        XCTAssertEqual(backgroundTasks.beginCount, 1)
        XCTAssertFalse(coordinator.isSyncInProgress)
    }

    func testRepeatedBackgroundTransitionsStartOneSync() async {
        let syncGate = BackgroundSyncGate()
        let syncStarted = expectation(description: "Notion sync started")
        let backgroundTasks = BackgroundSyncTaskManagerSpy()
        let coordinator = ApplicationBackgroundSyncCoordinator(
            backgroundTasks: backgroundTasks,
            sync: {
                syncStarted.fulfill()
                await syncGate.wait()
            }
        )

        coordinator.transition(to: .background)
        coordinator.transition(to: .background)
        await fulfillment(of: [syncStarted], timeout: 1)

        XCTAssertEqual(backgroundTasks.beginCount, 1)
        syncGate.open()
        await coordinator.waitForSyncToFinish()
        XCTAssertEqual(backgroundTasks.endedIDs.count, 1)
    }
}

@MainActor
private final class BackgroundSyncTaskManagerSpy: ApplicationBackgroundTaskManaging {
    private(set) var beginCount = 0
    private(set) var endedIDs: [ApplicationBackgroundTaskID] = []

    func beginBackgroundTask(
        expirationHandler: @escaping @MainActor () -> Void
    ) -> ApplicationBackgroundTaskID? {
        beginCount += 1
        return ApplicationBackgroundTaskID(rawValue: beginCount)
    }

    func endBackgroundTask(_ id: ApplicationBackgroundTaskID) {
        endedIDs.append(id)
    }
}

@MainActor
private final class BackgroundSyncGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}
