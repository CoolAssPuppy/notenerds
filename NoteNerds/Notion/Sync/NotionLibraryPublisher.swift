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
    func reconcile(
        _ library: LibraryState,
        notebookID: NotebookID?
    ) async throws -> NotionPublishReport
}

extension NotionLibraryPublishing {
    func publish(_ library: LibraryState) async throws -> NotionPublishReport {
        try await publish(library, notebookID: nil)
    }

    func reconcile(
        _ library: LibraryState,
        notebookID: NotebookID?
    ) async throws -> NotionPublishReport {
        try await publish(library, notebookID: notebookID)
    }
}

@MainActor
final class NotionLibraryPublisher: NotionLibraryPublishing {
    private let registry: NotionSyncRegistry
    private let notebookCoordinator: NotionSyncCoordinator
    private let manifestCoordinator: NotionManifestSyncCoordinator
    private let payloadBuilder: NotionNotebookPayloadBuilder
    private let now: @Sendable () -> Date

    init(
        api: any NotionSyncAPI,
        registry: NotionSyncRegistry,
        meetingLinkCoordinator _: (any NotionMeetingLinkCoordinating)? = nil,
        payloadBuilder: NotionNotebookPayloadBuilder = NotionNotebookPayloadBuilder(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.registry = registry
        notebookCoordinator = NotionSyncCoordinator(api: api, registry: registry, now: now)
        manifestCoordinator = NotionManifestSyncCoordinator(api: api, registry: registry)
        self.payloadBuilder = payloadBuilder
        self.now = now
    }

    func publish(
        _ library: LibraryState,
        notebookID: NotebookID?
    ) async throws -> NotionPublishReport {
        try await publish(
            library,
            notebookID: notebookID,
            forceRemoteReconciliation: false
        )
    }

    func reconcile(
        _ library: LibraryState,
        notebookID: NotebookID?
    ) async throws -> NotionPublishReport {
        try await publish(
            library,
            notebookID: notebookID,
            forceRemoteReconciliation: true
        )
    }

    private func publish(
        _ library: LibraryState,
        notebookID: NotebookID?,
        forceRemoteReconciliation: Bool
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

        let counts = try await publishNotebooks(
            in: library,
            selectedID: notebookID,
            destination: destination,
            generatedAt: generatedAt,
            forceRemoteReconciliation: forceRemoteReconciliation
        )
        let manifestResult = try await manifestCoordinator.sync(
            manifestData,
            contentHash: manifestHash
        )
        return NotionPublishReport(
            uploadedNotebookCount: counts.uploaded,
            skippedNotebookCount: counts.skipped,
            didUploadManifest: manifestResult != .skippedUnchanged,
            deletedNotebookCount: deletedCount
        )
    }

    private func publishNotebooks(
        in library: LibraryState,
        selectedID: NotebookID?,
        destination: NotionDestination,
        generatedAt: Date,
        forceRemoteReconciliation: Bool
    ) async throws -> (uploaded: Int, skipped: Int) {
        var counts = (uploaded: 0, skipped: 0)
        for notebook in try notebooks(in: library, selectedID: selectedID).sorted(by: notebookOrder) {
            let preparation = try await payloadBuilder.prepare(
                notebook: notebook,
                library: library,
                exportedAt: generatedAt
            )
            let shouldUpload: Bool
            if forceRemoteReconciliation {
                shouldUpload = true
            } else {
                shouldUpload = try await registry.needsSync(
                    notebookID: preparation.snapshot.row.notebookID,
                    contentHash: preparation.snapshot.row.contentHash,
                    destination: destination
                )
            }
            guard shouldUpload else {
                counts.skipped += 1
                continue
            }
            let payload = try payloadBuilder.render(preparation)
            switch try await notebookCoordinator.sync(
                payload,
                to: destination,
                forceRemoteReconciliation: forceRemoteReconciliation
            ) {
            case .uploaded: counts.uploaded += 1
            case .skippedUnchanged: counts.skipped += 1
            }
        }
        return counts
    }

    private func reconcileDeletedNotebooks(
        in library: LibraryState,
        state: NotionSyncState
    ) async throws -> Int {
        let localNotebookIDs = Set(
            library.notebooks.map { $0.id.rawValue.uuidString.lowercased() }
        )
        let staleQueuedIDs = Set(state.queue.map(\.notebookID)).subtracting(localNotebookIDs)
        for notebookID in staleQueuedIDs {
            try await registry.removeQueuedSync(notebookID: notebookID)
        }
        return 0
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
