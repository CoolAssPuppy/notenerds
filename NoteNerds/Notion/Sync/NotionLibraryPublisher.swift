import Foundation

struct NotionPublishReport: Equatable, Sendable {
    let uploadedNotebookCount: Int
    let skippedNotebookCount: Int
    let didUploadManifest: Bool
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
    private let registry: NotionSyncRegistry
    private let notebookCoordinator: NotionSyncCoordinator
    private let manifestCoordinator: NotionManifestSyncCoordinator
    private let payloadBuilder: NotionNotebookPayloadBuilder
    private let now: @Sendable () -> Date

    init(
        api: any NotionSyncAPI,
        registry: NotionSyncRegistry,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.registry = registry
        notebookCoordinator = NotionSyncCoordinator(api: api, registry: registry, now: now)
        manifestCoordinator = NotionManifestSyncCoordinator(api: api, registry: registry)
        payloadBuilder = NotionNotebookPayloadBuilder()
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
        let manifestResult = try await manifestCoordinator.sync(
            NotionLibraryManifestCodec.encode(manifest),
            contentHash: NotionLibraryManifestCodec.contentHash(manifest)
        )

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
        return NotionPublishReport(
            uploadedNotebookCount: uploadedCount,
            skippedNotebookCount: skippedCount,
            didUploadManifest: manifestResult != .skippedUnchanged
        )
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
