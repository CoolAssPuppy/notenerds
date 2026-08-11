import XCTest
@testable import NoteNerds

@MainActor
final class BackgroundSaveCoordinatorBehaviorTests: XCTestCase {
    func testInactiveThenBackgroundUsesOneTaskAndFlushesBeforeCheckpoint() async {
        let events = BackgroundSaveEventRecorder()
        let flushGate = BackgroundSaveGate()
        let flushStarted = expectation(description: "flush started")
        let backgroundTasks = BackgroundTaskManagerSpy(events: events)
        let coordinator = ApplicationBackgroundSaveCoordinator(
            backgroundTasks: backgroundTasks,
            flushPendingSnapshots: {
                events.record("flush")
                flushStarted.fulfill()
                await flushGate.wait()
            },
            checkpointDocuments: { events.record("checkpoint") }
        )

        coordinator.transition(to: .inactive)
        await fulfillment(of: [flushStarted], timeout: 1)
        coordinator.transition(to: .background)
        flushGate.open()
        await coordinator.waitForSaveToFinish()

        XCTAssertEqual(backgroundTasks.beginCount, 1)
        XCTAssertEqual(backgroundTasks.endedIDs.count, 1)
        XCTAssertEqual(events.values, ["begin", "flush", "checkpoint", "end"])
    }

    func testRepeatedBackgroundTransitionDoesNotDuplicateAnActiveSave() async {
        let flushGate = BackgroundSaveGate()
        let flushStarted = expectation(description: "flush started")
        let backgroundTasks = BackgroundTaskManagerSpy()
        let coordinator = ApplicationBackgroundSaveCoordinator(
            backgroundTasks: backgroundTasks,
            flushPendingSnapshots: {
                flushStarted.fulfill()
                await flushGate.wait()
            },
            checkpointDocuments: {}
        )

        coordinator.transition(to: .inactive)
        await fulfillment(of: [flushStarted], timeout: 1)
        coordinator.transition(to: .background)
        coordinator.transition(to: .background)

        XCTAssertEqual(backgroundTasks.beginCount, 1)
        flushGate.open()
        await coordinator.waitForSaveToFinish()
        XCTAssertEqual(backgroundTasks.endedIDs.count, 1)
    }

    func testBackgroundAfterCompletedInactiveSaveWaitsForANewActiveCycle() async {
        let events = BackgroundSaveEventRecorder()
        let backgroundTasks = BackgroundTaskManagerSpy()
        let coordinator = ApplicationBackgroundSaveCoordinator(
            backgroundTasks: backgroundTasks,
            flushPendingSnapshots: { events.record("flush") },
            checkpointDocuments: { events.record("checkpoint") }
        )

        coordinator.transition(to: .inactive)
        await coordinator.waitForSaveToFinish()
        coordinator.transition(to: .background)

        XCTAssertEqual(backgroundTasks.beginCount, 1)
        XCTAssertEqual(events.values.filter { $0 == "checkpoint" }.count, 1)

        coordinator.transition(to: .active)
        coordinator.transition(to: .inactive)
        await coordinator.waitForSaveToFinish()
        XCTAssertEqual(backgroundTasks.beginCount, 2)
        XCTAssertEqual(events.values.filter { $0 == "checkpoint" }.count, 2)
    }

    func testNewInactivePeriodDuringSaveRunsAnotherPassForItsSnapshot() async {
        let events = BackgroundSaveEventRecorder()
        let snapshot = BackgroundSnapshot(value: "first")
        let firstCheckpointStarted = expectation(description: "first checkpoint started")
        let checkpointGate = BackgroundSaveGate()
        let backgroundTasks = BackgroundTaskManagerSpy()
        let coordinator = ApplicationBackgroundSaveCoordinator(
            backgroundTasks: backgroundTasks,
            flushPendingSnapshots: { events.record("flush:\(snapshot.value)") },
            checkpointDocuments: {
                events.record("checkpoint")
                if events.count(of: "checkpoint") == 1 {
                    firstCheckpointStarted.fulfill()
                    await checkpointGate.wait()
                }
            }
        )

        coordinator.transition(to: .inactive)
        await fulfillment(of: [firstCheckpointStarted], timeout: 1)
        coordinator.transition(to: .active)
        snapshot.value = "second"
        coordinator.transition(to: .inactive)
        checkpointGate.open()
        await coordinator.waitForSaveToFinish()

        XCTAssertEqual(events.values, ["flush:first", "checkpoint", "flush:second", "checkpoint"])
        XCTAssertEqual(backgroundTasks.beginCount, 1)
        XCTAssertEqual(backgroundTasks.endedIDs.count, 1)
    }

    func testExpirationEndsTheTaskSkipsCheckpointAndAllowsTheNextSave() async {
        let flushGate = BackgroundSaveGate()
        let flushStarted = expectation(description: "flush started")
        let events = BackgroundSaveEventRecorder()
        let backgroundTasks = BackgroundTaskManagerSpy(events: events)
        let coordinator = ApplicationBackgroundSaveCoordinator(
            backgroundTasks: backgroundTasks,
            flushPendingSnapshots: {
                events.record("flush")
                if events.count(of: "flush") == 1 {
                    flushStarted.fulfill()
                }
                await flushGate.wait()
            },
            checkpointDocuments: { events.record("checkpoint") }
        )

        coordinator.transition(to: .inactive)
        await fulfillment(of: [flushStarted], timeout: 1)
        coordinator.transition(to: .active)
        coordinator.transition(to: .inactive)
        backgroundTasks.expireCurrentTask()

        XCTAssertFalse(coordinator.isSaveInProgress)
        XCTAssertEqual(backgroundTasks.endedIDs.count, 1)
        flushGate.open()
        for _ in 0..<3 { await Task.yield() }
        XCTAssertFalse(events.values.contains("checkpoint"))

        coordinator.transition(to: .active)
        coordinator.transition(to: .inactive)
        await coordinator.waitForSaveToFinish()
        XCTAssertEqual(backgroundTasks.beginCount, 2)
        XCTAssertEqual(backgroundTasks.endedIDs.count, 2)
        XCTAssertEqual(events.values.filter { $0 == "checkpoint" }.count, 1)
    }
}

@MainActor
private final class BackgroundTaskManagerSpy: ApplicationBackgroundTaskManaging {
    private let events: BackgroundSaveEventRecorder?
    private var expirationHandler: (@MainActor () -> Void)?
    private(set) var beginCount = 0
    private(set) var endedIDs: [ApplicationBackgroundTaskID] = []

    init(events: BackgroundSaveEventRecorder? = nil) {
        self.events = events
    }

    func beginBackgroundTask(
        expirationHandler: @escaping @MainActor () -> Void
    ) -> ApplicationBackgroundTaskID? {
        beginCount += 1
        self.expirationHandler = expirationHandler
        events?.record("begin")
        return ApplicationBackgroundTaskID(rawValue: beginCount)
    }

    func endBackgroundTask(_ id: ApplicationBackgroundTaskID) {
        endedIDs.append(id)
        expirationHandler = nil
        events?.record("end")
    }

    func expireCurrentTask() {
        expirationHandler?()
    }
}

@MainActor
private final class BackgroundSaveEventRecorder {
    private(set) var values: [String] = []

    func record(_ value: String) {
        values.append(value)
    }

    func count(of value: String) -> Int {
        values.filter { $0 == value }.count
    }
}

@MainActor
private final class BackgroundSnapshot {
    var value: String

    init(value: String) {
        self.value = value
    }
}

@MainActor
private final class BackgroundSaveGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}
