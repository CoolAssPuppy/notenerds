import Foundation

actor NotionSyncRegistry {
    private let store: any NotionSyncStateStoring
    private let now: @Sendable () -> Date
    private var state = NotionSyncState()
    private var hasLoaded = false

    init(
        store: any NotionSyncStateStoring,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.now = now
    }

    func snapshot() async throws -> NotionSyncState {
        try await restoreIfNeeded()
        return state
    }

    func enqueue(notebookID: String) async throws {
        try Self.validateNotebookID(notebookID)
        try await restoreIfNeeded()
        guard !state.queue.contains(where: { $0.notebookID == notebookID }) else { return }
        state.queue.append(
            NotionSyncQueueItem(
                notebookID: notebookID,
                enqueuedAt: now(),
                attemptCount: 0,
                nextAttemptAt: nil,
                lastFailure: nil
            )
        )
        try await store.save(state)
    }

    func recordFailure(
        notebookID: String,
        failure: NotionSyncFailure,
        retryAt: Date?
    ) async throws {
        try Self.validateNotebookID(notebookID)
        try await restoreIfNeeded()
        if let index = state.queue.firstIndex(where: { $0.notebookID == notebookID }) {
            state.queue[index].attemptCount += 1
            state.queue[index].nextAttemptAt = retryAt
            state.queue[index].lastFailure = failure
        } else {
            state.queue.append(
                NotionSyncQueueItem(
                    notebookID: notebookID,
                    enqueuedAt: now(),
                    attemptCount: 1,
                    nextAttemptAt: retryAt,
                    lastFailure: failure
                )
            )
        }
        try await store.save(state)
    }

    func recordSuccess(_ binding: NotionNotebookBinding) async throws {
        try Self.validateNotebookID(binding.notebookID)
        try await restoreIfNeeded()
        state.bindings.removeAll { $0.notebookID == binding.notebookID }
        state.bindings.append(binding)
        state.bindings.sort { $0.notebookID < $1.notebookID }
        state.queue.removeAll { $0.notebookID == binding.notebookID }
        try await store.save(state)
    }

    func removeBinding(notebookID: String) async throws {
        try Self.validateNotebookID(notebookID)
        try await restoreIfNeeded()
        state.bindings.removeAll { $0.notebookID == notebookID }
        try await store.save(state)
    }

    func recordDeletion(notebookID: String) async throws {
        try Self.validateNotebookID(notebookID)
        try await restoreIfNeeded()
        state.bindings.removeAll { $0.notebookID == notebookID }
        state.queue.removeAll { $0.notebookID == notebookID }
        state.meetingLinks.removeAll { $0.notebookID == notebookID }
        try await store.save(state)
    }

    func recordMeetingLink(_ link: NotionMeetingNotebookLink) async throws {
        try Self.validateNotebookID(link.notebookID)
        try Self.validateIdentifier(link.meetingBlockID)
        try Self.validateIdentifier(link.notebookPageID)
        try Self.validateIdentifier(link.linkBlockID)
        try await restoreIfNeeded()
        state.meetingLinks.removeAll {
            $0.meetingBlockID == link.meetingBlockID && $0.notebookID == link.notebookID
        }
        state.meetingLinks.append(link)
        state.meetingLinks.sort {
            ($0.meetingBlockID, $0.notebookID) < ($1.meetingBlockID, $1.notebookID)
        }
        try await store.save(state)
    }

    func markMeetingLinkRemoved(
        meetingBlockID: String,
        notebookID: String
    ) async throws {
        try Self.validateNotebookID(notebookID)
        try Self.validateIdentifier(meetingBlockID)
        try await restoreIfNeeded()
        guard let index = state.meetingLinks.firstIndex(where: {
            $0.meetingBlockID == meetingBlockID && $0.notebookID == notebookID
        }) else { return }
        state.meetingLinks[index].wasRemovedByUser = true
        try await store.save(state)
    }

    func removeMeetingLinks(notebookID: String) async throws {
        try Self.validateNotebookID(notebookID)
        try await restoreIfNeeded()
        state.meetingLinks.removeAll { $0.notebookID == notebookID }
        try await store.save(state)
    }

    func needsSync(
        notebookID: String,
        contentHash: String,
        destination: NotionDestination
    ) async throws -> Bool {
        try Self.validateNotebookID(notebookID)
        try await restoreIfNeeded()
        guard state.destination == destination,
              let binding = state.binding(notebookID: notebookID) else {
            return true
        }
        return binding.contentHash != contentHash
    }

    func setDestination(
        workspaceID: String,
        destination: NotionDestination,
        manifestPageID: String?
    ) async throws {
        try await restoreIfNeeded()
        let didChange = state.workspaceID != workspaceID || state.destination != destination
        state.workspaceID = workspaceID
        state.destination = destination
        state.manifestPageID = manifestPageID
        if didChange {
            state.bindings.removeAll()
            state.meetingLinks.removeAll()
            state.manifestRootBlockID = nil
            state.manifestContentHash = nil
        }
        try await store.save(state)
    }

    func reset() async throws {
        let emptyState = NotionSyncState()
        try await store.save(emptyState)
        state = emptyState
        hasLoaded = true
    }

    func recordManifestSuccess(rootBlockID: String, contentHash: String) async throws {
        guard UUID(uuidString: rootBlockID) != nil, contentHash.count == 64 else {
            throw NotionSyncStateError.invalidState
        }
        try await restoreIfNeeded()
        state.manifestRootBlockID = rootBlockID
        state.manifestContentHash = contentHash
        try await store.save(state)
    }

    private func restoreIfNeeded() async throws {
        guard !hasLoaded else { return }
        state = try await store.load() ?? NotionSyncState()
        hasLoaded = true
    }

    private static func validateNotebookID(_ id: String) throws {
        guard UUID(uuidString: id) != nil else { throw NotionAPIError.invalidIdentifier }
    }

    private static func validateIdentifier(_ id: String) throws {
        guard UUID(uuidString: id) != nil else { throw NotionAPIError.invalidIdentifier }
    }
}
