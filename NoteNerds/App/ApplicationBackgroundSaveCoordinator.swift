import Combine
import UIKit

struct ApplicationBackgroundTaskID: Hashable, Sendable {
    let rawValue: Int
}

@MainActor
protocol ApplicationBackgroundTaskManaging: AnyObject {
    func beginBackgroundTask(
        expirationHandler: @escaping @MainActor () -> Void
    ) -> ApplicationBackgroundTaskID?

    func endBackgroundTask(_ id: ApplicationBackgroundTaskID)
}

enum ApplicationLifecyclePhase: Sendable {
    case active
    case inactive
    case background
}

@MainActor
final class ApplicationBackgroundSaveCoordinator: ObservableObject {
    typealias SaveAction = @MainActor () async -> Void

    private let backgroundTasks: ApplicationBackgroundTaskManaging
    private let flushPendingSnapshots: SaveAction
    private let checkpointDocuments: SaveAction
    private var activeSaveID: UUID?
    private var activeSaveTask: Task<Void, Never>?
    private var activeBackgroundTaskID: ApplicationBackgroundTaskID?
    private var hasRequestedSaveDuringInactivePeriod = false
    private var isSavePassPending = false

    var isSaveInProgress: Bool {
        activeSaveID != nil
    }

    init(
        backgroundTasks: ApplicationBackgroundTaskManaging,
        flushPendingSnapshots: @escaping SaveAction,
        checkpointDocuments: @escaping SaveAction
    ) {
        self.backgroundTasks = backgroundTasks
        self.flushPendingSnapshots = flushPendingSnapshots
        self.checkpointDocuments = checkpointDocuments
    }

    func transition(to phase: ApplicationLifecyclePhase) {
        guard phase != .active else {
            hasRequestedSaveDuringInactivePeriod = false
            return
        }
        guard !hasRequestedSaveDuringInactivePeriod else { return }
        hasRequestedSaveDuringInactivePeriod = true
        startSaveIfNeeded()
    }

    func waitForSaveToFinish() async {
        await activeSaveTask?.value
    }

    private func startSaveIfNeeded() {
        guard activeSaveID == nil else {
            isSavePassPending = true
            return
        }
        let saveID = UUID()
        activeSaveID = saveID
        let backgroundTaskID = backgroundTasks.beginBackgroundTask { [weak self] in
            self?.expireSave(id: saveID)
        }
        guard activeSaveID == saveID else {
            if let backgroundTaskID {
                backgroundTasks.endBackgroundTask(backgroundTaskID)
            }
            return
        }
        activeBackgroundTaskID = backgroundTaskID
        activeSaveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await performSavePasses(id: saveID)
        }
    }

    private func performSavePasses(id: UUID) async {
        repeat {
            await flushPendingSnapshots()
            guard !Task.isCancelled else { return }
            await checkpointDocuments()
            guard !Task.isCancelled else { return }
            guard isSavePassPending else { break }
            isSavePassPending = false
        } while true
        finishSave(id: id)
    }

    private func finishSave(id: UUID) {
        guard activeSaveID == id else { return }
        isSavePassPending = false
        activeSaveID = nil
        activeSaveTask = nil
        endBackgroundTask()
    }

    private func expireSave(id: UUID) {
        guard activeSaveID == id else { return }
        activeSaveTask?.cancel()
        isSavePassPending = false
        activeSaveID = nil
        activeSaveTask = nil
        endBackgroundTask()
    }

    private func endBackgroundTask() {
        guard let activeBackgroundTaskID else { return }
        self.activeBackgroundTaskID = nil
        backgroundTasks.endBackgroundTask(activeBackgroundTaskID)
    }
}

@MainActor
final class UIApplicationBackgroundTaskManager: ApplicationBackgroundTaskManaging {
    private let application: UIApplication
    private let taskName: String
    private var nextID = 0
    private var systemIDs: [ApplicationBackgroundTaskID: UIBackgroundTaskIdentifier] = [:]

    init(application: UIApplication = .shared, taskName: String = "Save notes") {
        self.application = application
        self.taskName = taskName
    }

    func beginBackgroundTask(
        expirationHandler: @escaping @MainActor () -> Void
    ) -> ApplicationBackgroundTaskID? {
        let systemID = application.beginBackgroundTask(
            withName: taskName,
            expirationHandler: expirationHandler
        )
        guard systemID != .invalid else { return nil }
        nextID += 1
        let id = ApplicationBackgroundTaskID(rawValue: nextID)
        systemIDs[id] = systemID
        return id
    }

    func endBackgroundTask(_ id: ApplicationBackgroundTaskID) {
        guard let systemID = systemIDs.removeValue(forKey: id) else { return }
        application.endBackgroundTask(systemID)
    }
}
