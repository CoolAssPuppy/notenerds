import Foundation

struct NotionPublishReport: Equatable, Sendable {
    let uploadedNotebookCount: Int
    let skippedNotebookCount: Int
    let didUploadManifest: Bool
    let deletedNotebookCount: Int

    init(
        uploadedNotebookCount: Int,
        skippedNotebookCount: Int,
        didUploadManifest: Bool,
        deletedNotebookCount: Int = 0
    ) {
        self.uploadedNotebookCount = uploadedNotebookCount
        self.skippedNotebookCount = skippedNotebookCount
        self.didUploadManifest = didUploadManifest
        self.deletedNotebookCount = deletedNotebookCount
    }
}

enum NotionPublishError: Error, Equatable, Sendable {
    case notebookNotFound
}

@MainActor
protocol NotionLibraryPublishing: AnyObject {
    func publish(
        _ library: LibraryState,
        notebookID: NotebookID?
    ) async throws -> NotionPublishReport
}

extension NotionLibraryPublishing {
    func publish(_ library: LibraryState) async throws -> NotionPublishReport {
        try await publish(library, notebookID: nil)
    }
}

@MainActor
final class NotionLibraryPublisher: NotionLibraryPublishing {
    private let api: any NotionSyncAPI
    private let registry: NotionSyncRegistry
    private let notebookCoordinator: NotionSyncCoordinator
    private let manifestCoordinator: NotionManifestSyncCoordinator
    private let payloadBuilder: NotionNotebookPayloadBuilder
    private let now: @Sendable () -> Date
    private let meetingLinkCoordinator: (any NotionMeetingLinkCoordinating)?

    init(
        api: any NotionSyncAPI,
        registry: NotionSyncRegistry,
        meetingLinkCoordinator: (any NotionMeetingLinkCoordinating)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.api = api
        self.registry = registry
        notebookCoordinator = NotionSyncCoordinator(api: api, registry: registry, now: now)
        manifestCoordinator = NotionManifestSyncCoordinator(api: api, registry: registry)
        payloadBuilder = NotionNotebookPayloadBuilder()
        self.meetingLinkCoordinator = meetingLinkCoordinator
        self.now = now
    }

    func publish(
        _ library: LibraryState,
        notebookID: NotebookID?
    ) async throws -> NotionPublishReport {
        let state = try await registry.snapshot()
        guard let destination = state.destination else { throw NotionOAuthError.noConnection }
        let generatedAt = now()
        let manifest = NotionLibraryManifest(
            library: library,
            databaseID: destination.databaseID,
            dataSourceID: destination.dataSourceID,
            generatedAt: generatedAt
        )
        let manifestData = try NotionLibraryManifestCodec.encode(manifest)
        let manifestHash = try NotionLibraryManifestCodec.contentHash(manifest)
        let deletedCount = if notebookID == nil {
            try await reconcileDeletedNotebooks(in: library, state: state)
        } else {
            0
        }

        var uploadedCount = 0
        var skippedCount = 0
        let notebooks = try notebooks(in: library, selectedID: notebookID)
        for notebook in notebooks.sorted(by: notebookOrder) {
            let payload = try await payloadBuilder.build(
                notebook: notebook,
                library: library,
                exportedAt: generatedAt
            )
            switch try await notebookCoordinator.sync(payload, to: destination) {
            case .uploaded: uploadedCount += 1
            case .skippedUnchanged: skippedCount += 1
            }
        }
        let manifestResult = try await manifestCoordinator.sync(
            manifestData,
            contentHash: manifestHash
        )
        return NotionPublishReport(
            uploadedNotebookCount: uploadedCount,
            skippedNotebookCount: skippedCount,
            didUploadManifest: manifestResult != .skippedUnchanged,
            deletedNotebookCount: deletedCount
        )
    }

    private func reconcileDeletedNotebooks(
        in library: LibraryState,
        state: NotionSyncState
    ) async throws -> Int {
        let localNotebookIDs = Set(
            library.notebooks.map { $0.id.rawValue.uuidString.lowercased() }
        )
        let missingBindings = state.bindings.filter {
            !localNotebookIDs.contains($0.notebookID)
        }
        for binding in missingBindings {
            try await meetingLinkCoordinator?.removeLinks(notebookID: binding.notebookID)
            do {
                try await api.trashNotebookPage(pageID: binding.pageID)
            } catch NotionAPIError.httpStatus(404) {
                // The Notion page is already gone, so local sync state can be cleared.
            }
            try await registry.recordDeletion(notebookID: binding.notebookID)
        }

        let boundIDs = Set(missingBindings.map(\.notebookID))
        let staleQueuedIDs = Set(state.queue.map(\.notebookID)).subtracting(localNotebookIDs)
        for notebookID in staleQueuedIDs.subtracting(boundIDs) {
            try await registry.recordDeletion(notebookID: notebookID)
        }
        return missingBindings.count
    }

    private func notebookOrder(_ first: Notebook, _ second: Notebook) -> Bool {
        first.id.rawValue.uuidString < second.id.rawValue.uuidString
    }

    private func notebooks(
        in library: LibraryState,
        selectedID: NotebookID?
    ) throws -> [Notebook] {
        guard let selectedID else { return library.notebooks }
        guard let notebook = library.notebook(id: selectedID) else {
            throw NotionPublishError.notebookNotFound
        }
        return [notebook]
    }
}
