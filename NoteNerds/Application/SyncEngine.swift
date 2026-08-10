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
    private var pendingChangeIDs: Set<ChangeID> = []
    private(set) var pendingAssets: [AssetID: DocumentAsset] = [:]
    private(set) var receivedChanges: [DocumentChange] = []
    private var receivedChangeIDs: Set<ChangeID> = []
    private(set) var state = SyncState.idle
    private(set) var lastFailure: SyncProviderFailure?
    private var cursor: SyncCursor?
    private var didRestoreState = false
    private var shouldSynchronizeAgain = false
    private var receivedChangeIDsPendingSave: Set<ChangeID> = []
    private var locallyAppliedChangeIDs: Set<ChangeID> = []
    private var locallyAppliedChangeIDsPendingRemoval: Set<ChangeID> = []

    init(provider: any SyncProvider, stateStore: (any SyncStateStore)? = nil) {
        self.provider = provider
        self.stateStore = stateStore
    }

    func enqueue(_ change: DocumentChange, wasAppliedLocally: Bool = true) async {
        await restoreStateIfNeeded()
        let didInsertChange = pendingChangeIDs.insert(change.id).inserted
        if didInsertChange {
            pendingChanges.append(change)
        }
        let didInsertLocalMarker = wasAppliedLocally
            && locallyAppliedChangeIDs.insert(change.id).inserted
        guard didInsertChange || didInsertLocalMarker else { return }
        await persistState()
    }

    func enqueue(_ asset: DocumentAsset) async {
        await restoreStateIfNeeded()
        pendingAssets[asset.id] = asset
        await persistState()
    }

    func synchronize() async {
        await restoreStateIfNeeded()
        guard state != .synchronizing else {
            shouldSynchronizeAgain = true
            return
        }
        state = .synchronizing
        do {
            try await provider.start()
            repeat {
                shouldSynchronizeAgain = false
                try await uploadPendingAssets()
                try await pushPendingChanges()
                try await pullRemoteChanges()
            } while shouldSynchronizeAgain || !pendingAssets.isEmpty || !pendingChanges.isEmpty
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

    private func uploadPendingAssets() async throws {
        for asset in Array(pendingAssets.values) {
            try await provider.uploadAsset(asset)
            guard pendingAssets[asset.id] == asset else { continue }
            pendingAssets[asset.id] = nil
        }
    }

    private func pushPendingChanges() async throws {
        let changes = pendingChanges
        guard !changes.isEmpty else { return }
        try await provider.push(changes)
        let uploadedIDs = Set(changes.map(\.id))
        pendingChanges.removeAll { uploadedIDs.contains($0.id) }
        pendingChangeIDs.subtract(uploadedIDs)
    }

    private func pullRemoteChanges() async throws {
        let batch = try await provider.pull(since: cursor)
        let newChanges = batch.changes.filter { receivedChangeIDs.insert($0.id).inserted }
        receivedChanges.append(contentsOf: newChanges)
        receivedChanges.sort {
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return $0.deviceID < $1.deviceID
        }
        cursor = batch.cursor
    }

    func drainReceivedChanges() -> [DocumentChange] {
        defer {
            receivedChanges = []
            receivedChangeIDs.removeAll(keepingCapacity: true)
        }
        return receivedChanges
    }

    func receivedChangesSnapshot() -> [DocumentChange] {
        receivedChanges
    }

    func locallyAppliedChangeIDsSnapshot() async -> Set<ChangeID> {
        await restoreStateIfNeeded()
        return locallyAppliedChangeIDs
    }

    func acknowledgeReceivedChanges(_ identifiers: Set<ChangeID>) async -> Bool {
        let acknowledgedIDs = receivedChangeIDs.intersection(identifiers)
        guard !acknowledgedIDs.isEmpty else { return true }
        guard stateStore != nil else {
            receivedChanges.removeAll { acknowledgedIDs.contains($0.id) }
            receivedChangeIDs.subtract(acknowledgedIDs)
            locallyAppliedChangeIDs.subtract(acknowledgedIDs)
            return false
        }
        receivedChangeIDsPendingSave.formUnion(acknowledgedIDs)
        locallyAppliedChangeIDsPendingRemoval.formUnion(acknowledgedIDs)
        let didPersist = await persistState()
        if didPersist {
            receivedChanges.removeAll { acknowledgedIDs.contains($0.id) }
            receivedChangeIDs.subtract(acknowledgedIDs)
            locallyAppliedChangeIDs.subtract(acknowledgedIDs)
        }
        receivedChangeIDsPendingSave.subtract(acknowledgedIDs)
        locallyAppliedChangeIDsPendingRemoval.subtract(acknowledgedIDs)
        return didPersist
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
        pendingChangeIDs.formUnion(pendingChanges.map(\.id))
        let restoredChanges = snapshot.pendingChanges.filter {
            pendingChangeIDs.insert($0.id).inserted
        }
        pendingChanges.insert(contentsOf: restoredChanges, at: 0)
        for asset in snapshot.pendingAssets { pendingAssets[asset.id] = asset }
        receivedChanges = snapshot.receivedChanges.filter {
            receivedChangeIDs.insert($0.id).inserted
        }
        locallyAppliedChangeIDs.formUnion(snapshot.locallyAppliedChangeIDs)
        cursor = snapshot.cursor
    }

    @discardableResult
    private func persistState() async -> Bool {
        guard let stateStore else { return true }
        let snapshot = SyncEngineSnapshot(
            pendingChanges: pendingChanges,
            pendingAssets: Array(pendingAssets.values),
            receivedChanges: receivedChanges.filter {
                !receivedChangeIDsPendingSave.contains($0.id)
            },
            cursor: cursor,
            locallyAppliedChangeIDs: Array(
                locallyAppliedChangeIDs.subtracting(locallyAppliedChangeIDsPendingRemoval)
            )
        )
        do {
            try await stateStore.save(snapshot)
            return true
        } catch {
            lastFailure = .persistent
            state = .waitingToRetry
            return false
        }
    }
}

struct SyncEngineSnapshot: Codable, Equatable, Sendable {
    let pendingChanges: [DocumentChange]
    let pendingAssets: [DocumentAsset]
    let receivedChanges: [DocumentChange]
    let cursor: SyncCursor?
    let locallyAppliedChangeIDs: [ChangeID]

    init(
        pendingChanges: [DocumentChange],
        pendingAssets: [DocumentAsset],
        receivedChanges: [DocumentChange],
        cursor: SyncCursor?,
        locallyAppliedChangeIDs: [ChangeID] = []
    ) {
        self.pendingChanges = pendingChanges
        self.pendingAssets = pendingAssets
        self.receivedChanges = receivedChanges
        self.cursor = cursor
        self.locallyAppliedChangeIDs = Self.sortedChangeIDs(locallyAppliedChangeIDs)
    }

    private enum CodingKeys: String, CodingKey {
        case pendingChanges
        case pendingAssets
        case receivedChanges
        case cursor
        case locallyAppliedChangeIDs
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            pendingChanges: try container.decode([DocumentChange].self, forKey: .pendingChanges),
            pendingAssets: try container.decode([DocumentAsset].self, forKey: .pendingAssets),
            receivedChanges: try container.decode([DocumentChange].self, forKey: .receivedChanges),
            cursor: try container.decodeIfPresent(SyncCursor.self, forKey: .cursor),
            locallyAppliedChangeIDs: try container.decodeIfPresent(
                [ChangeID].self,
                forKey: .locallyAppliedChangeIDs
            ) ?? []
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pendingChanges, forKey: .pendingChanges)
        try container.encode(pendingAssets, forKey: .pendingAssets)
        try container.encode(receivedChanges, forKey: .receivedChanges)
        try container.encodeIfPresent(cursor, forKey: .cursor)
        try container.encode(Self.sortedChangeIDs(locallyAppliedChangeIDs), forKey: .locallyAppliedChangeIDs)
    }

    private static func sortedChangeIDs(_ identifiers: [ChangeID]) -> [ChangeID] {
        Array(Set(identifiers)).sorted {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }
    }
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
