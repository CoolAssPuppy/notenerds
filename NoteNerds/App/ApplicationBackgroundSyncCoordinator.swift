import Combine

@MainActor
final class ApplicationBackgroundSyncCoordinator: ObservableObject {
    typealias SyncAction = @MainActor () async -> Void

    private let backgroundTasks: ApplicationBackgroundTaskManaging
    private let sync: SyncAction
    private var activeSyncTask: Task<Void, Never>?
    private var activeBackgroundTaskID: ApplicationBackgroundTaskID?
    private var hasRequestedSyncDuringBackgroundPeriod = false

    var isSyncInProgress: Bool {
        activeSyncTask != nil
    }

    init(
        backgroundTasks: ApplicationBackgroundTaskManaging,
        sync: @escaping SyncAction
    ) {
        self.backgroundTasks = backgroundTasks
        self.sync = sync
    }

    func transition(to phase: ApplicationLifecyclePhase) {
        guard phase != .active else {
            hasRequestedSyncDuringBackgroundPeriod = false
            return
        }
        guard phase == .background,
              !hasRequestedSyncDuringBackgroundPeriod,
              activeSyncTask == nil else { return }
        hasRequestedSyncDuringBackgroundPeriod = true
        let backgroundTaskID = backgroundTasks.beginBackgroundTask { [weak self] in
            self?.expireSync()
        }
        activeBackgroundTaskID = backgroundTaskID
        activeSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await sync()
            guard !Task.isCancelled else { return }
            finishSync()
        }
    }

    func waitForSyncToFinish() async {
        await activeSyncTask?.value
    }

    private func finishSync() {
        activeSyncTask = nil
        endBackgroundTask()
    }

    private func expireSync() {
        activeSyncTask?.cancel()
        activeSyncTask = nil
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard let activeBackgroundTaskID else { return }
        self.activeBackgroundTaskID = nil
        backgroundTasks.endBackgroundTask(activeBackgroundTaskID)
    }
}
