import Foundation

enum DocumentChangeKind: String, Codable, Sendable {
    case upsert
    case delete
}

struct DocumentChange: Codable, Hashable, Sendable {
    let id: ChangeID
    let notebookID: NotebookID
    let objectKey: String
    let kind: DocumentChangeKind
    let payload: Data
    let timestamp: Date
    let deviceID: String
    let sequence: Int
}

struct SyncCursor: Codable, Hashable, Sendable {
    let sequence: Int
}

struct SyncBatch: Codable, Equatable, Sendable {
    let changes: [DocumentChange]
    let cursor: SyncCursor?
}

struct DocumentAsset: Codable, Hashable, Sendable {
    let id: AssetID
    let data: Data
    let contentType: String
}

enum SyncProviderFailure: Error, Equatable, Sendable {
    case accountUnavailable
    case quotaExceeded
    case serviceUnavailable
    case persistent

    var userMessage: String {
        switch self {
        case .accountUnavailable:
            "Sign in to iCloud to sync. Changes remain saved on this iPad."
        case .quotaExceeded:
            "iCloud storage is full. Changes remain saved on this iPad."
        case .serviceUnavailable:
            "iCloud is temporarily unavailable. Sync will retry automatically."
        case .persistent:
            "iCloud sync needs attention. Changes remain saved on this iPad."
        }
    }
}

protocol SyncProvider: Sendable {
    var identifier: String { get }

    func start() async throws
    func push(_ changes: [DocumentChange]) async throws
    func pull(since cursor: SyncCursor?) async throws -> SyncBatch
    func uploadAsset(_ asset: DocumentAsset) async throws
    func fetchAsset(_ id: AssetID) async throws -> Data
}

enum SyncPushBatcher {
    static func batches<Element>(_ elements: [Element], maximumCount: Int) -> [[Element]] {
        precondition(maximumCount > 0)
        return stride(from: 0, to: elements.count, by: maximumCount).map { start in
            Array(elements[start..<min(start + maximumCount, elements.count)])
        }
    }
}

enum SyncConflictResolver {
    static func resolve(local: [DocumentChange], remote: [DocumentChange]) -> [DocumentChange] {
        var resolvedByObject: [String: DocumentChange] = [:]
        var objectOrder: [String] = []
        for change in local + remote {
            if resolvedByObject[change.objectKey] == nil {
                objectOrder.append(change.objectKey)
            }
            if let existing = resolvedByObject[change.objectKey] {
                resolvedByObject[change.objectKey] = winner(existing, change)
            } else {
                resolvedByObject[change.objectKey] = change
            }
        }
        return objectOrder.compactMap { resolvedByObject[$0] }
    }

    private static func winner(_ first: DocumentChange, _ second: DocumentChange) -> DocumentChange {
        if first.timestamp != second.timestamp {
            return first.timestamp > second.timestamp ? first : second
        }
        if first.deviceID != second.deviceID {
            return first.deviceID > second.deviceID ? first : second
        }
        return first.sequence > second.sequence ? first : second
    }
}
