import Foundation

enum NotionSyncFailure: String, Codable, Equatable, Sendable {
    case rateLimited
    case serviceUnavailable
    case authentication
    case accessDenied
    case missingRemotePage
    case validation
    case persistent
}

struct NotionNotebookBinding: Codable, Equatable, Sendable {
    let notebookID: String
    let pageID: String
    let managedRootBlockID: String?
    let contentHash: String
    let syncedAt: Date
    let notionLastEditedAt: Date?
}

struct NotionSyncQueueItem: Codable, Equatable, Sendable {
    let notebookID: String
    let enqueuedAt: Date
    var attemptCount: Int
    var nextAttemptAt: Date?
    var lastFailure: NotionSyncFailure?
}

struct NotionSyncState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    var workspaceID: String?
    var destination: NotionDestination?
    var manifestPageID: String?
    var manifestRootBlockID: String?
    var manifestContentHash: String?
    var bindings: [NotionNotebookBinding]
    var queue: [NotionSyncQueueItem]

    init(
        schemaVersion: Int = currentSchemaVersion,
        workspaceID: String? = nil,
        destination: NotionDestination? = nil,
        manifestPageID: String? = nil,
        manifestRootBlockID: String? = nil,
        manifestContentHash: String? = nil,
        bindings: [NotionNotebookBinding] = [],
        queue: [NotionSyncQueueItem] = []
    ) {
        self.schemaVersion = schemaVersion
        self.workspaceID = workspaceID
        self.destination = destination
        self.manifestPageID = manifestPageID
        self.manifestRootBlockID = manifestRootBlockID
        self.manifestContentHash = manifestContentHash
        self.bindings = bindings
        self.queue = queue
    }

    func binding(notebookID: String) -> NotionNotebookBinding? {
        bindings.first { $0.notebookID == notebookID }
    }
}

enum NotionSyncStateError: Error, Equatable, Sendable {
    case fileTooLarge
    case unsupportedSchema
    case invalidState
}

protocol NotionSyncStateStoring: Sendable {
    func load() async throws -> NotionSyncState?
    func save(_ state: NotionSyncState) async throws
}
