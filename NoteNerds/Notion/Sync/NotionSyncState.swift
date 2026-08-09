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

struct NotionMeetingNotebookLink: Codable, Equatable, Sendable {
    let meetingBlockID: String
    let notebookID: String
    let notebookPageID: String
    let linkBlockID: String
    let createdAt: Date
    var wasRemovedByUser: Bool
}

struct NotionSyncState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    var workspaceID: String?
    var destination: NotionDestination?
    var manifestPageID: String?
    var manifestRootBlockID: String?
    var manifestContentHash: String?
    var bindings: [NotionNotebookBinding]
    var queue: [NotionSyncQueueItem]
    var meetingLinks: [NotionMeetingNotebookLink]

    init(
        schemaVersion: Int = currentSchemaVersion,
        workspaceID: String? = nil,
        destination: NotionDestination? = nil,
        manifestPageID: String? = nil,
        manifestRootBlockID: String? = nil,
        manifestContentHash: String? = nil,
        bindings: [NotionNotebookBinding] = [],
        queue: [NotionSyncQueueItem] = [],
        meetingLinks: [NotionMeetingNotebookLink] = []
    ) {
        self.schemaVersion = schemaVersion
        self.workspaceID = workspaceID
        self.destination = destination
        self.manifestPageID = manifestPageID
        self.manifestRootBlockID = manifestRootBlockID
        self.manifestContentHash = manifestContentHash
        self.bindings = bindings
        self.queue = queue
        self.meetingLinks = meetingLinks
    }

    func binding(notebookID: String) -> NotionNotebookBinding? {
        bindings.first { $0.notebookID == notebookID }
    }

    func meetingLink(
        meetingBlockID: String,
        notebookID: String
    ) -> NotionMeetingNotebookLink? {
        meetingLinks.first {
            $0.meetingBlockID == meetingBlockID && $0.notebookID == notebookID
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case workspaceID
        case destination
        case manifestPageID
        case manifestRootBlockID
        case manifestContentHash
        case bindings
        case queue
        case meetingLinks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard storedVersion == 1 || storedVersion == Self.currentSchemaVersion else {
            throw NotionSyncStateError.unsupportedSchema
        }
        schemaVersion = Self.currentSchemaVersion
        workspaceID = try container.decodeIfPresent(String.self, forKey: .workspaceID)
        destination = try container.decodeIfPresent(NotionDestination.self, forKey: .destination)
        manifestPageID = try container.decodeIfPresent(String.self, forKey: .manifestPageID)
        manifestRootBlockID = try container.decodeIfPresent(String.self, forKey: .manifestRootBlockID)
        manifestContentHash = try container.decodeIfPresent(String.self, forKey: .manifestContentHash)
        bindings = try container.decodeIfPresent([NotionNotebookBinding].self, forKey: .bindings) ?? []
        queue = try container.decodeIfPresent([NotionSyncQueueItem].self, forKey: .queue) ?? []
        meetingLinks = try container.decodeIfPresent(
            [NotionMeetingNotebookLink].self,
            forKey: .meetingLinks
        ) ?? []
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
