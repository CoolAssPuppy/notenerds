import Foundation

enum SyncState: Equatable, Sendable {
    case idle
    case synchronizing
    case waitingToRetry
}

actor SyncEngine {
    private let provider: any SyncProvider
    private let stateStore: (any SyncStateStore)?
    private(set) var pendingChanges: [DocumentChange] = []
    private(set) var pendingAssets: [AssetID: DocumentAsset] = [:]
    private(set) var receivedChanges: [DocumentChange] = []
    private(set) var state = SyncState.idle
    private(set) var lastFailure: SyncProviderFailure?
    private var cursor: SyncCursor?
    private var didRestoreState = false

    init(provider: any SyncProvider, stateStore: (any SyncStateStore)? = nil) {
        self.provider = provider
        self.stateStore = stateStore
    }

    func enqueue(_ change: DocumentChange) async {
        await restoreStateIfNeeded()
        guard !pendingChanges.contains(where: { $0.id == change.id }) else { return }
        pendingChanges.append(change)
        await persistState()
    }

    func enqueue(_ asset: DocumentAsset) async {
        await restoreStateIfNeeded()
        pendingAssets[asset.id] = asset
        await persistState()
    }

    func synchronize() async {
        await restoreStateIfNeeded()
        state = .synchronizing
        do {
            try await provider.start()
            for asset in Array(pendingAssets.values) {
                try await provider.uploadAsset(asset)
                pendingAssets[asset.id] = nil
            }
            if !pendingChanges.isEmpty {
                try await provider.push(pendingChanges)
                pendingChanges.removeAll(keepingCapacity: true)
            }
            let batch = try await provider.pull(since: cursor)
            let knownIDs = Set(receivedChanges.map(\.id))
            receivedChanges.append(contentsOf: batch.changes.filter { !knownIDs.contains($0.id) })
            receivedChanges.sort {
                if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
                if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
                return $0.deviceID < $1.deviceID
            }
            cursor = batch.cursor
            lastFailure = nil
            state = .idle
            await persistState()
        } catch let failure as SyncProviderFailure {
            lastFailure = failure
            state = .waitingToRetry
        } catch {
            lastFailure = .serviceUnavailable
            state = .waitingToRetry
        }
    }

    func drainReceivedChanges() -> [DocumentChange] {
        defer { receivedChanges = [] }
        return receivedChanges
    }

    func receivedChangesSnapshot() -> [DocumentChange] {
        receivedChanges
    }

    func acknowledgeReceivedChanges(_ identifiers: Set<ChangeID>) async {
        receivedChanges.removeAll { identifiers.contains($0.id) }
        await persistState()
    }

    func fetchAsset(_ id: AssetID) async throws -> Data {
        try await provider.fetchAsset(id)
    }

    private func restoreStateIfNeeded() async {
        guard !didRestoreState else { return }
        didRestoreState = true
        let snapshot: SyncEngineSnapshot?
        do {
            snapshot = try await stateStore?.load()
        } catch {
            lastFailure = .persistent
            state = .waitingToRetry
            return
        }
        guard let snapshot else { return }
        let knownChangeIDs = Set(pendingChanges.map(\.id))
        pendingChanges.insert(contentsOf: snapshot.pendingChanges.filter { !knownChangeIDs.contains($0.id) }, at: 0)
        for asset in snapshot.pendingAssets { pendingAssets[asset.id] = asset }
        receivedChanges = snapshot.receivedChanges
        cursor = snapshot.cursor
    }

    private func persistState() async {
        let snapshot = SyncEngineSnapshot(
            pendingChanges: pendingChanges,
            pendingAssets: Array(pendingAssets.values),
            receivedChanges: receivedChanges,
            cursor: cursor
        )
        do {
            try await stateStore?.save(snapshot)
        } catch {
            lastFailure = .persistent
            state = .waitingToRetry
        }
    }
}

struct SyncEngineSnapshot: Codable, Equatable, Sendable {
    let pendingChanges: [DocumentChange]
    let pendingAssets: [DocumentAsset]
    let receivedChanges: [DocumentChange]
    let cursor: SyncCursor?
}

protocol SyncStateStore: Sendable {
    func load() async throws -> SyncEngineSnapshot?
    func save(_ snapshot: SyncEngineSnapshot) async throws
}

actor InMemorySyncStateStore: SyncStateStore {
    private var snapshot: SyncEngineSnapshot?

    func load() -> SyncEngineSnapshot? { snapshot }
    func save(_ snapshot: SyncEngineSnapshot) { self.snapshot = snapshot }
}
