import Foundation

actor InMemorySyncProvider: SyncProvider {
    nonisolated let identifier = "memory"
    private var changesByID: [ChangeID: DocumentChange] = [:]
    private var assetsByID: [AssetID: Data] = [:]

    func start() async throws {}

    func push(_ changes: [DocumentChange]) async throws {
        for change in changes {
            changesByID[change.id] = change
        }
    }

    func pull(since cursor: SyncCursor?) async throws -> SyncBatch {
        let minimumSequence = cursor?.sequence ?? Int.min
        let changes = changesByID.values
            .filter { $0.sequence > minimumSequence }
            .sorted { $0.sequence < $1.sequence }
        return SyncBatch(
            changes: changes,
            cursor: changes.last.map { SyncCursor(sequence: $0.sequence) } ?? cursor
        )
    }

    func uploadAsset(_ asset: DocumentAsset) async throws {
        assetsByID[asset.id] = asset.data
    }

    func fetchAsset(_ id: AssetID) async throws -> Data {
        guard let data = assetsByID[id] else { throw CocoaError(.fileNoSuchFile) }
        return data
    }
}
