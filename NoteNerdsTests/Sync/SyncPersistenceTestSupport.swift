import Foundation
@testable import NoteNerds

actor PausingInitialLoadSyncStateStore: SyncStateStore {
    private var snapshot: SyncEngineSnapshot?
    private var hasStartedLoading = false
    private var loadContinuation: CheckedContinuation<Void, Never>?
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []
    private var hasResumedLoad = false
    private(set) var savedPendingCounts: [Int] = []

    func load() async -> SyncEngineSnapshot? {
        guard !hasStartedLoading else { return snapshot }
        hasStartedLoading = true
        loadWaiters.forEach { $0.resume() }
        loadWaiters.removeAll()
        await withCheckedContinuation { loadContinuation = $0 }
        return snapshot
    }

    func save(_ snapshot: SyncEngineSnapshot) {
        self.snapshot = snapshot
        savedPendingCounts.append(snapshot.pendingChanges.count)
    }

    func waitUntilLoadStarted() async {
        guard !hasStartedLoading else { return }
        await withCheckedContinuation { loadWaiters.append($0) }
    }

    func resumeLoad() {
        hasResumedLoad = true
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func hasResumed() -> Bool {
        hasResumedLoad
    }
}

actor CheckpointCompletionProbe {
    private var didFinish = false
    private(set) var didFinishAfterOutboxSave = false

    func finish(afterOutboxSave: Bool) {
        didFinish = true
        didFinishAfterOutboxSave = afterOutboxSave
    }

    func isFinished() -> Bool {
        didFinish
    }
}
